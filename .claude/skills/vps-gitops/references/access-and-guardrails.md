# Access levels and guardrails

Policy: **read + GitOps**. The agent observes production and proposes changes
in the repository; humans, CI or the deploy queue apply them. Direct execution
on the server is break-glass only, with an explicit request.

## Why this policy exists

- The server holds customer data and every credential. `volume rm`,
  `prune -a` or a removed secret cannot be undone.
- A change made only on the server creates **drift**: the next `git pull` or
  config-management run overwrites it, or fails because of it.
- The platform is meant to be replicated per client. A fix that does not live
  in the repository never reaches the next client.

## Level 0 — Local (free)

Anything that does not touch a server:

```bash
docker stack config -c setup/docker/<stack>-stack.yml > /dev/null   # render + validate
bash -n setup/docker/hooks/<stack>.sh                                # syntax
shellcheck scripts/*.sh
docker run --rm <image>@sha256:<digest> <command>                     # reproduce in isolation
```

Local reproduction is cheap and safe: a throwaway container with fake secrets
catches most boot-order, permission and config errors before production.

## Level 1 — Observe production (free, read-only)

Prefer `scripts/diagnose.sh`: it aggregates host, Swarm, failing services,
logs and drift, and never reads secret values. Individual commands allowed:

```bash
docker stack ls
docker service ls
docker service ps <service> --no-trunc --format '{{.CurrentState}} | {{.Error}}'
docker service logs --tail 100 --raw <service>
docker service inspect <service> --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'
docker secret ls --format '{{.Name}}'                 # names only
free -h; df -h /; uptime; nproc
git -C <repo-on-server> log --oneline -3; git -C <repo-on-server> status -s
deploy-queue status; deploy-queue history 20
```

CI: build status and logs through the CI helper script (read-only commands).

### Looks read-only, but is not

| Command | Why it is not level 1 |
|---|---|
| `docker exec -it <container> sh` | Interactive shell inside production |
| `env` / `printenv` inside a container | Prints secrets that were loaded into the process |
| `cat` of any file under the secrets directory | Prints secret values |
| Logs of a service that logs its config at boot | Check before pasting output anywhere |
| Triggering a CI build of the default branch | That **is** a production deploy |

### Allowlist, never suffix filters

Never filter environment/config files by suffix assuming it is safe.
`*_SECRET` names both *references* to Docker Secrets
(`DB_PASSWORD_SECRET=db_password_v1`) and *actual secret values*
(`COOKIE_SECRET=...`). The same goes for `*_KEY` and `*_TOKEN`. Use an explicit
allowlist of known-safe variables. A suffix filter has leaked values before.

## Level 2 — Change via GitOps (default)

1. Edit in the repository: stack files, hooks, scripts, pipeline, docs.
2. Validate at level 0.
3. Show the summarized diff and the reason.
4. Commit only when asked; push/merge only when asked.
5. Hand over the apply command and say who runs it:
   - Stack/platform change: on the server, `git pull` then
     `deploy-queue stack <name>`.
   - Application change: the CI job (triggered by merge to the default branch).
   - Secret the agent cannot generate: the exact command for a human to run on
     the host, reading the value without echo (`read -rsp`).

## Level 3 — Break-glass (explicit request only)

Examples: running the deploy queue yourself, `docker service update` outside
the queue, editing files on the server, restarting services or the server,
DNS or firewall changes, triggering or cancelling a production CI build.

Checklist:

- [ ] The user asked for **this** action (authorization does not carry over).
- [ ] Announce command, impact and how to undo it.
- [ ] Back up what changes; suggest a provider snapshot before large changes.
- [ ] Nothing else is deploying (`deploy-queue status`, `tmux ls`).
- [ ] Long processes in `tmux` + `tee` to a log file.
- [ ] Few SSH connections: hardening rate-limits port 22. Batch commands in
      one session and stream files with `tar | ssh ... tar x`.
- [ ] Follow the change to completion; never fire and forget.
- [ ] Reproduce the fix in the repository and report the drift.

### Killing a hung process safely

`pkill -f "<pattern>"` inside `ssh host '...'` also matches the SSH session's
own command line and kills it. List candidates first, then kill by PID:

```bash
ps -eo pid,etime,args | grep -E '[d]eploy-queue stack'
kill <pid>
```

## Forbidden without an explicit, specific request

| Action | Why |
|---|---|
| `docker volume rm`, `docker system prune -a --volumes` | Deletes customer data |
| `docker secret rm` | Services mounting it stop starting; the value cannot be recovered from Swarm |
| `docker stack rm` | Takes everything down; recreated networks/volumes may differ |
| Destroying, reinstalling or restoring the server | Irreversible |
| Database major version change on a populated volume | Incompatible on-disk format; requires dump/restore |
| Firewall or SSH hardening changes out of order | Can lock everyone out |
| Printing or pasting secret values, tokens, unseal keys | Credential leak |
| Committing inventories, env files, state files, secrets | Secrets in Git history are permanent |
| Purchases, renewals, plan upgrades | Real cost |
| Creating/disabling user accounts, handling people's passwords or tokens | Human administrator's responsibility |
