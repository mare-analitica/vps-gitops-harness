# Deploy queue

Every change to the Swarm goes through one command on the host. Nobody — human,
CI or agent — runs `docker stack deploy` or `docker service update` directly.

## Why a queue

| Problem without it | What the queue does |
| --- | --- |
| Two deploys at once (CI + operator) leave services half-updated | Global `flock`: deploys wait in line |
| `docker stack deploy` renders missing variables as empty strings, silently | Refuses to deploy when any `${VAR}` without default is empty |
| A deploy "succeeds" while tasks crash-loop | Waits for two consecutive healthy reads per service |
| A bad version stays up until someone notices | `failure_action: rollback`; the queue triggers rollback if Swarm did not |
| One-shot jobs reported done while still `0/1` | Compares completed vs expected tasks; fails idle jobs fast |
| "Who deployed what, when?" | Append-only history: actor, target, commit, image digest, env version, result |
| Files edited on the server get deployed | Refuses a dirty repository |

## Commands

```bash
cd <repo-on-server> && git pull --ff-only     # clean tree = no drift
deploy-queue stack <name>                     # setup/docker/<name>-stack.yml + hook
deploy-queue app <service> <registry>/<image>@sha256:<digest> [--env <vault-path>] [--env-version N|latest]
deploy-queue status                           # last result per target
deploy-queue history 30                       # audit trail
```

Exit codes worth knowing: `1` failed (timeout or rollback), `3` timed out
waiting for the queue, `4` refused by validation (dirty repo, empty variable,
invalid stack, secret missing from the vault).

## Stack deploys

1. Load configuration in layers (last wins): `clients/<client>/config.env` →
   host env → `setup/docker/hooks/<stack>.sh`.
2. The hook generates or publishes secrets, prepares per-app databases/users,
   computes content hashes for Swarm Configs, and exports variables.
3. Validate: no empty variables, `docker stack config` renders, images pinned
   (the queue warns about images without a digest).
4. `docker stack deploy --prune --with-registry-auth` (`--prune` removes
   services deleted from the file).
5. Wait until every service converges; record the result.

A hook that fails (`return 1`) aborts the deploy before Swarm is touched.

## App deploys

`deploy-queue app` changes **only** the image and the mounted env of one
existing service:

1. Validate the service belongs to an app stack (`apps-*`) and the image comes
   from the local registry pinned by digest.
2. If `--env` is given: log into the vault with the deploy service account
   (read-only on app paths), resolve `latest` to a version number, render the
   key/values with shell escaping into a temp file (0600), create the immutable
   Docker Secret `<service>_env_v<N>`, and swap it at `/run/secrets/app.env`.
3. `docker service update --image ... --secret-rm/--secret-add ...` in a single
   update, so image and env move together and roll back together.
4. Wait for health; record `image=<ref> env <path>@v<N>` in history.

The service must already exist: the **stack** creates services (with
placeholders before the first build); the **app** deploy only updates them.

### Keeping stack redeploys from undoing app deploys

If a stack file hardcodes an image, redeploying the stack reverts the app to
that image and drops the vault env. The hook reads the last successful app
deploy from history and exports it:

- image → last good `image=` or a placeholder for brand-new services;
- env secret → last good `<service>_env_v<N>` or an "empty env" placeholder.

Docker refuses empty secrets (`data is empty`), so the placeholder must contain
at least a comment line, and its creation must be checked.

## Image pinning

- Always `name:tag@sha256:<digest>`. Resolve with
  `docker buildx imagetools inspect <name:tag>`.
- Upgrades are commits that change a digest — reviewable and revertible.
- A deploy that restarts a service with no Git change is the signature of a
  floating tag: compare `.PreviousSpec` and `.Spec` of the service.

## First boot and ordering

- Services that depend on each other's migrations fail and restart until the
  chain completes (e.g. worker needs tables from the API). That is expected on
  first boot; do not "fix" it by ignoring migration errors.
- Give slow first boots room: `start_period` on healthchecks, and a longer
  convergence timeout exported by the hook for heavy stacks.
- Datastores that key their state on hostname (e.g. RabbitMQ) need a fixed
  `hostname:` in the service.

## Rollback

| Situation | Action |
| --- | --- |
| Deploy failed | Automatic: Swarm or the queue rolls back image **and** env |
| Healthy but wrong (bug found later) | Redeploy a previous commit through CI, or (break-glass) `deploy-queue app <service> <previous-image@digest> --env <path> --env-version <N>` using pairs from `history` |
| Bad stack change | Revert the commit, `git pull`, `deploy-queue stack <name>` |

## Operating long deploys

Run on the host in `tmux` with a log, and poll the log instead of holding an
SSH session open:

```bash
tmux new-session -d -s deploy "deploy-queue stack <name> 2>&1 | tee /root/deploy-<name>.log"
```
