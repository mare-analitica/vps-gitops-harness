# CI pipeline

## Shape

```text
merge to main ──(polling)──► CI server (no host Docker access)
  1. checkout with a read-only Git hosting token
  2. docker buildx --builder <remote> ──► rootless BuildKit ──► local registry
  3. ssh deployer@<host-gateway> "app <service> <image@sha256> [--env <vault-path>]"
                                      │ forced command + restricted sudo
                                      ▼
  deploy-queue on the host: queue → vault env → Docker Secret → service update
                            → health → history | rollback image + env
```

| CI has | CI does not have |
| --- | --- |
| A `buildx` client pointed at a rootless BuildKit daemon on an isolated network | The host Docker socket or API (not even through a proxy) |
| Push credentials to the local registry | Access to the vault, databases or the Swarm |
| An SSH key that can only run `deploy-queue app/status/history` | A shell on the host, or stack deploys |
| A fine-grained, read-only Git hosting token | Write access to repositories |

Why no host Docker: whoever can create containers on the host is root on the
host. A socket proxy that allows `containers/create` gives that away.

## The deploy key

In `authorized_keys` of a dedicated user:

```text
restrict,command="/usr/local/bin/deploy-queue-ssh",from="<container-network-cidr>" ssh-ed25519 ...
```

`deploy-queue-ssh` parses `SSH_ORIGINAL_COMMAND`, validates every argument
(service name pattern `apps-<client>_<name>`, image from the local registry by
digest, env path pattern), logs denials to syslog, and calls
`sudo -n deploy-queue app ...`. `sudoers` allows only those subcommands.

## Application Dockerfiles that work with this pipeline

- Runtime user is **not root**; base images pinned by digest.
- **Explicit permissions**: `COPY --chmod=0644` for files the runtime reads,
  `--chmod=0555` for entrypoints, `chmod -R a+rX` on built static assets. The
  build context may arrive with `0600` files (see troubleshooting).
- Entrypoint loads `/run/secrets/app.env` and converts `*_FILE` variables.
- Database migrations run in the entrypoint before the server starts: CI
  cannot reach the database, and a failed migration exits the container, which
  triggers rollback.
- A healthcheck in the image, so the queue can judge the deploy.
- Per-Dockerfile ignore files (`Dockerfile.api.dockerignore`) keep large
  frontend assets out of the API build context.

## Pipeline file (per app repository)

- Build and push each image; read the digest from the build metadata file
  (`containerimage.digest`) — never grep for `sha256`, which may match a base
  image.
- Deploy only from the default branch. In a plain (non-multibranch) pipeline
  job, `when { branch 'main' }` never matches; compare `GIT_BRANCH` instead.
- Deploy the API first (migrations + env), then the frontend.
- Public build-time variables (API URL, OIDC authority) live in the pipeline
  file; they end up in the browser bundle and are not secrets.

## Jobs as code

- Platform CI configuration and per-client job definitions are versioned;
  jobs are generated at CI startup (configuration-as-code + a job DSL).
- A new app = one entry in the client's job file + a stack service + a vault
  path + DNS. Jobs created by hand in the UI disappear on rebuild.
- A syntax error in CI configuration prevents the CI server from starting;
  the queue rolls the CI stack back. Validate locally by booting the CI image
  with the configuration mounted and fake secrets, then check the generated
  job definitions.

## Personal API tokens and the CLI helper

- Each person creates their own token in the CI UI, one per machine, stored in
  a local file with mode 600 outside any repository.
- With SSO, token access must be explicitly allowed without an active SSO
  session. The token keeps the groups from the last SSO login; **disabling the
  user in the SSO provider does not revoke the token** — offboarding must
  revoke tokens in CI.
- `scripts/jenkins.sh` (REST, curl + jq): `whoami`, `jobs`, `status`, `logs -f`,
  `build -f`, `stop`. The token goes to curl through stdin.

### Agent rules

- `whoami`, `jobs`, `status`, `logs` are level 1: use them instead of asking
  the user to paste logs.
- `build` and `stop` on a job that deploys the default branch are production
  changes: only with an explicit request for that job.

## Known limits

- **No boundary between apps of the same client:** the deploy key accepts any
  `apps-*` service and any app vault path. A malicious pipeline change on the
  default branch of one repository could deploy its image into another app's
  service with that app's env. Mitigation: protected default branches with
  mandatory review and code owners for pipeline files. Fix: map each job to its
  allowed services and env paths in the forced command, or one key per app.
- The dev group can usually write every app path in the vault; per-app
  policies are needed as the team grows.
- Old `<service>_env_v<N>` Docker Secrets accumulate; clean them periodically.
