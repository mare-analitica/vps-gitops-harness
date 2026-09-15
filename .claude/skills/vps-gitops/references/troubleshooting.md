# Troubleshooting catalog

Every row below happened in a real single-VPS Swarm deployment. Check here
before debugging from scratch — most failures repeat.

## Investigation order (service `0/N`, deploy timeout, rollback)

1. **Overview** — `scripts/diagnose.sh` or `docker service ls`: what is `0/N`,
   which stack stopped.
2. **Tasks** — `docker service ps <service> --no-trunc --format '{{.CurrentState}} | {{.Error}}'`.
   The exit code points the way:
   - `137` → killed for memory (container limit or host OOM).
   - `1` / `2` → the application aborted: read the log.
   - `143` with `unhealthy container` → the healthcheck killed it.
   - `Complete` on a long-running service → the process exited cleanly (often
     a healthcheck-driven `SIGTERM`).
   - `Pending` / "no suitable node" → resources, constraints or image.
3. **Logs** — `docker service logs --tail 80 --raw <service>`. Find the
   **first** fatal line, not the last. Logs from old and new tasks mix; pick
   the latest task ID from `service ps` when in doubt.
4. **Resources** — `free -m`, `uptime` vs `nproc`, `df -h /`,
   `dmesg -T | grep -i oom`.
5. **Rendered config** — `docker stack config -c <file>` with the same
   variables: empty values, wrong image, wrong secret name.
6. **Drift** — repository on the server vs the expected commit; dirty tree.
7. **Reproduce** in a throwaway container with fake secrets.

## Deploy queue and Swarm

| Symptom | Root cause | Fix |
| --- | --- | --- |
| A deploy with no Git change restarted a service; `.PreviousSpec` and `.Spec` differ only by image digest | Floating tag resolved to a newer digest at deploy time — an unplanned upgrade (a vault restarted this way comes back sealed) | Pin every image as `tag@sha256`; upgrades are commits |
| Deploy reports success while a one-shot job shows `1/1 (0/1 completed)` | Checking for the word "completed" instead of comparing done vs expected | Compare counts; fail jobs with no active task after a few reads |
| One-shot service stuck `0/1`, deploy times out | `replicated` service with `restart_policy: none` is never "running" | `deploy.mode: replicated-job` |
| Queue exits silently, no history entry | A library sourced under `set -e` was missing (server repository older than the queue binary) | Explicit library checks that record a failure; `git pull` on the server |
| Queue log lines end up inside the rendered env file | Logging to stdout while the function output is redirected to a file | Log to stderr |
| `docker service update` fails when the env did not change | Re-adding a secret already mounted at the same target is rejected | Swap the secret only when its version changes |
| `secret not found: <placeholder>`; the log said "created" | Docker refuses empty secrets (`data is empty`) and the creation was not checked | Placeholder with a comment line; check the exit status |
| `service '<name>' does not exist` on the first CI deploy | The app deploy only updates services; the stack was never deployed | Deploy the app stack first (placeholders), then run CI |
| Removed service keeps running | `docker stack deploy` without `--prune` | Always `--prune` |
| Stack variable rendered as garbage (e.g. a script name) | `${VAR:?message}` is not supported by `docker stack deploy` | Plain `${VAR}` and validate empties before deploying |
| Stack deployed with empty variables | `docker stack deploy` does not read `.env` files | Load configuration explicitly (the queue does) |
| Edited config/secret has no effect | Swarm Configs and Secrets are immutable | New name (content hash or version suffix) |
| Services from different stacks talk to the wrong `redis`/`db` | Service short names are DNS aliases on every network they join | Unique names or a private network per stack |
| Registry disappears from the host port after joining a new network | Service only on `internal: true` networks loses host publishing | Keep it on a non-internal network too |
| Deploy hangs forever inside a hook | A tool waiting for interactive input (see RabbitMQ below) | Timeouts around external commands; kill by PID, not `pkill -f` over SSH |

## Healthchecks, first boot and ordering

| Symptom | Root cause | Fix |
| --- | --- | --- |
| SSO/JVM service `exit 143 unhealthy` right after "bootstrap completed" | First boot (schema migration + build) on 2 vCPU exceeds `start_period` + retries | Longer `start_period`; second attempt usually succeeds |
| Database healthy but root has **no password**; log shows init interrupted | Healthcheck killed the container mid-initialization; init never reruns on an existing data directory | Longer `start_period`; recreate the volume only if it is verifiably empty |
| Background workers restart every ~2 minutes, tasks `Complete`, log "Shutting down… Bye!" | `HEALTHCHECK` baked into the image checks the **web** port; the worker never serves it | `healthcheck: disable: true` on worker services |
| App backend killed repeatedly; frontend cannot resolve the backend | Healthcheck calls an endpoint that depends on data that does not exist yet (e.g. a site per hostname) | TCP healthcheck (`bash -c '</dev/tcp/127.0.0.1/<port>'`) |
| Services fail with `relation ... does not exist` on first boot | Cross-service migrations: a worker needs tables created by another service | Expected on first boot; Swarm restarts close the chain. Do not mask migration errors |
| Container "running" but its port refuses connections; no healthcheck defined | The main server process aborted and only a helper process remains | Always define a healthcheck so the queue sees the failure |
| Vendor worker service runs the **web server** instead of the worker; its queue never drains | The image entrypoint ignores `command` and always starts the server | Bypass the vendor entrypoint for that service (loader → worker command directly) |
| SSO forward-auth proxy restarts on first deploy with `x509: certificate is valid for ...default` | It started before the TLS certificate for the SSO host was issued | Transient: restart policy with delay resolves after issuance |

## Datastores and messaging

| Symptom | Root cause | Fix |
| --- | --- | --- |
| MongoDB 8.x exits: "Linux kernel versions 6.19 and newer has a known incompatibility" | Known incompatibility below specific kernel/MongoDB versions | Use a kernel/MongoDB combination outside the affected range; never downgrade a populated volume |
| RabbitMQ loses vhosts and users after a restart | Node data is keyed by `rabbit@<hostname>`; Swarm tasks get random hostnames | Fixed `hostname:` on the service |
| `rabbitmqctl add_user <user>` with the password on stdin hangs forever | `rabbitmqctl` reads passwords from stdin only with a TTY | Pipe the password into a shell inside the container and pass it as an argument there |
| ClickHouse aborts at boot: `number_of_free_entries_in_pool_to_execute_mutation` | A thread pool was reduced below a dependent MergeTree setting | Do not shrink background pools; tune caches instead |
| Python service crashes: `connect() got an unexpected keyword argument 'sslmode'` | `?sslmode=` is libpq syntax; asyncpg rejects it | Remove the parameter from async connection strings |
| An app stores its encryption key only in its data volume | The app generates its own key when it does not receive one | Export the key from a Docker Secret at startup; verify the stored key matches |
| Secret "differs" when comparing hashes of equal values | Secret files have no trailing newline; `echo`/`sed` add one | Strip `\r\n` on both sides before hashing (never print values) |

## CI and builds

| Symptom | Root cause | Fix |
| --- | --- | --- |
| Non-root app image fails with `Permission denied` on its entrypoint — only when built by CI | CI entrypoint set `umask 077` for writing a credential and it leaked into the CI process: checkouts became `0600` | Scope `umask` to a subshell; Dockerfiles set permissions explicitly (`COPY --chmod`, `chmod -R a+rX`) |
| `buildx` through the socket proxy gets 403 on `/containers/...` | buildx needs the containers API; allowing it gives root on the host | Remote rootless BuildKit; CI without host Docker |
| Rootless BuildKit: `fork/exec /proc/self/exe: operation not permitted` | Default seccomp/AppArmor block user namespaces; Swarm does not accept `security_opt` | Run BuildKit as a host-managed container with those profiles relaxed only there |
| BuildKit cannot resolve registries | Container only on an internal network | Add a network with egress |
| `invalid reference format` pushing to `platform_registry:5000` | `_` is invalid in an image reference hostname | Network alias without underscores |
| Deploy uses the wrong digest | Grepping `sha256` in build output matched a base image | Read `containerimage.digest` from the build metadata file |
| Git checkout fails with `403 — Write access to repository not granted` using a fine-grained token | Misleading message: the token lacks the **Contents** permission (metadata-only tokens can call the API but not clone) | Grant Contents: read-only; editing a fine-grained token keeps its value |
| Deploy stage never runs in a plain pipeline job | `when { branch 'main' }` only works in multibranch jobs | Compare `GIT_BRANCH` (`origin/main`) |
| CI server does not start after a configuration change; stack rolls back | Invalid configuration-as-code or job DSL | Validate locally by booting the CI image with the configuration and fake secrets |
| OIDC login to CI fails with `invalid_scope` | Provider rejects scopes the plugin requests by default | Override scopes explicitly (`openid profile email`) |
| CLI calls return 401 with a valid token after SSO login works | Token access without an SSO session is disabled | Enable token access without session; groups refresh on next web login |
| Build console shows `ha:////...` noise | CI console annotations in raw progressive logs | Strip ESC-delimited annotations in the CLI helper |

## Identity, vault and edge

| Symptom | Root cause | Fix |
| --- | --- | --- |
| `400 Request Header Or Cookie Too Large` behind SSO forward-auth | Session cookie with tokens and groups exceeds header limits | Server-side session store (Redis) for the forward-auth proxy |
| Vault service-account login fails: `unsupported config type` | JWT login attempted on the mount configured for interactive OIDC | Separate JWT auth mount with the provider's discovery URL only |
| Sync job cannot update its own vault policy | Anti-escalation: the job token may not edit its own policy | An admin updates that policy manually before the deploy |
| Vault sealed after a restart | Expected behavior of a sealed-by-default vault | Unseal procedure with key shares held outside the server |
| Wildcard certificate never issues | DNS-01 needs a DNS provider API the account can actually use | HTTP-01 with explicit hostnames per tenant |
| Product's first-run page reachable by anyone | "Create the first administrator" belongs to whoever opens it first | Keep the host behind the IP allowlist until the admin exists |
| Image scripts fail with `awk: command not found` | Minimal (UBI micro) images ship without `awk` | Parse with `while IFS=, read` in bash |

## Host access

| Symptom | Root cause | Fix |
| --- | --- | --- |
| `ssh ... port 22: Connection timed out` suddenly, HTTPS fine; admin panels return 403 | The operator's public IP changed; firewall and proxy allowlists still hold the old one | Provider web console → allow new IP on port 22 → update the admin CIDR in host config → redeploy the platform stack → update the config-management inventory. Long term: VPN |
| `Connection timed out` in the middle of many commands | Firewall/fail2ban rate limit on port 22 | Wait; batch commands in one session; stream files with `tar` |
| The SSH session dies when killing a process | `pkill -f "<pattern>"` matched the SSH command line itself | `ps` to find the PID, `kill <pid>` |

## Recording a new incident

Add a row to the matching table: **symptom as observed** (exact error text when
it helps searching), **root cause with evidence**, and the **fix that was
verified**. If the fix is not verified yet, say so.
