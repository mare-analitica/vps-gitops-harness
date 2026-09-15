# Secrets

Golden rule for the agent: **work with names, never values.** Never print,
paste, commit, put in a URL or log the content of a secret, token or unseal key.

## Three kinds of secrets

| Kind | Examples | Created by | Stored in | Delivered as |
| --- | --- | --- | --- | --- |
| Infrastructure | Database, broker, cache passwords; encryption keys of self-hosted products | Stack hook, generated on the host | `/etc/<platform>/secrets/<name>` (root, 0600) | Docker Secret `<name>_v<N>` mounted as a file |
| Application | Payment API keys, JWT secrets, OAuth client secrets, CRM tokens | A person, in the vault UI | Vault KV `apps/<app>` (versioned) | `/run/secrets/app.env`, loaded by the app entrypoint |
| Human-provided infrastructure | Vendor license keys, CI read token for Git hosting | A person, on the host | Same host secrets directory | Docker Secret, required by the hook |

Non-secret configuration (URLs, hostnames, feature flags, OIDC issuer) goes in
the stack file or client config — not in the vault.

## Host-generated secrets

- `ensure_secret <name> [alnum|hex64|fernet]` creates the file if missing and
  publishes the Docker Secret; exports `<NAME>_SECRET=<name>_v<N>` for the
  stack file (`name: ${DB_PASSWORD_SECRET}`).
- Formats matter: Rails-style `SECRET_KEY_BASE` wants long hex; Python
  `cryptography` wants a Fernet key (32 bytes, URL-safe base64).
- Validate the character set before substituting a secret into SQL or config
  text.
- The secrets directory must be part of whatever backup exists: without it,
  initialized volumes become inaccessible.

## Human-provided secrets

The hook calls `require_secret <name>` and fails with the exact path when the
file is missing. The person writes it on the host without echo and without
shell history:

```bash
umask 077; read -rsp "value: " v; echo; printf "%s" "$v" > /etc/<platform>/secrets/<name>; unset v
```

Never ask for the value in chat. Verify only metadata:
`wc -c`, line count, mode — not the content.

## Delivering secrets to images that only read environment variables

Many vendor images have no `*_FILE` convention. Do not put values in
`environment:`. Instead:

1. In the stack file, set placeholders: `DB_PASSWORD: __APP_DB_PASSWORD__`,
   `REDIS_URL: redis://:__APP_REDIS_PASSWORD__@redis:6379/0`.
2. Mount the Docker Secrets and a small loader (Swarm Config) as the
   entrypoint wrapper: it replaces each `__NAME__` with the content of
   `/run/secrets/<name>` using pure shell string operations (secrets may contain
   `/ # &`), fails if any placeholder remains, then `exec`s the original
   entrypoint.
3. Values exist only in the process environment; `docker inspect` shows
   placeholders.

## Application env from the vault

| Step | Who | Detail |
| --- | --- | --- |
| Write | Person with the dev or admin group (OIDC login) | Every save creates a new version; deleting a version removes that rollback point |
| Read at deploy | Deploy queue on the host | Client-credentials token from the SSO → JWT login to the vault (policy: read-only on app paths) |
| Deliver | `deploy-queue app --env` | Rendered `KEY='value'` file → immutable Docker Secret `<service>_env_v<N>` |
| Load | App entrypoint | `set -a; . /run/secrets/app.env; set +a`, only inside the process |

- CI never sees vault values or tokens.
- Changing a value in the vault does **not** change running services. It takes
  effect on the next app deploy.
- History stores `image@digest + env version`: any past state is reproducible.
- The vault path must exist before the first deploy, even with empty keys.

## Rotation

| Secret | Procedure |
| --- | --- |
| Host-generated | Write the new value, increment `<name>.version`, redeploy the stack (Docker Secrets are immutable). For databases, change the password in the database first — or let the hook reapply it |
| Vault app secret | Save a new version, run the app's CI job |
| Human-provided | Write the new file, increment the version file, redeploy the stack |
| After someone leaves | Rotate every app secret that person's group could read (see `team-access.md`) |

## Where secrets must never be

- Git history (even removed later — history is permanent; CI scans all of it).
- Stack files, client config, CI job definitions.
- Chat, issues, pull request descriptions, screenshots.
- Command-line arguments on the host when avoidable (visible in `ps`). When a
  tool cannot read from stdin without a TTY, pipe the value into a shell
  inside the container and pass it there, so only root on the host could see it.
