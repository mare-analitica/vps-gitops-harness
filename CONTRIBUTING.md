# Contributing

Thanks for helping make small-server operations predictable.

## Ground rules

- **Never include real infrastructure data**: hostnames, domains, IP
  addresses, customer or company names, credentials, tokens, private keys or
  vendor-licensed files. Use `example.com`, `203.0.113.0/24` (RFC 5737) and
  `acme` as placeholders.
- Every change goes through a pull request. `main` is protected: direct
  pushes are rejected and all CI checks must pass.
- One logical change per pull request, linked to an issue.

## Workflow

1. Open or pick an issue. For anything non-trivial, agree on the approach in
   the issue first.
2. Create a branch from `main`:

   | Prefix | Use |
   | --- | --- |
   | `feat/` | New skill content, scripts or capabilities |
   | `fix/` | Corrections |
   | `docs/` | Documentation only |
   | `ci/` | Workflows and automation |
   | `chore/` | Repository maintenance |

3. Commit using [Conventional Commits](https://www.conventionalcommits.org/):
   `type(scope): imperative summary`, for example
   `feat(skill): add rollback matrix to deploy queue reference`.
   Explain **why** in the body when it is not obvious.
4. Open a pull request with `Closes #<issue>`, fill in the template and wait
   for CI.
5. Pull requests are **squash merged**; the pull request title becomes the
   commit subject, so keep it in Conventional Commits format.

## Local checks

The same pinned tools CI uses:

```bash
# Markdown
docker run --rm -v "$PWD:/workdir:ro" davidanson/markdownlint-cli2:v0.23.2 "**/*.md"

# Shell scripts
docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.11.0 --external-sources $(git ls-files '*.sh')

# Workflows
docker run --rm -v "$PWD:/repo:ro" -w /repo rhysd/actionlint:1.7.12 -color

# Secrets in the full history
docker run --rm -v "$PWD:/repo:ro" --entrypoint sh ghcr.io/gitleaks/gitleaks:v8.30.1 -c \
  'git config --global --add safe.directory /repo && gitleaks git /repo --redact --no-banner'
```

On Windows Git Bash, prefix commands with `MSYS_NO_PATHCONV=1`.

## Writing skill content

- `SKILL.md` stays short; details go to `references/` (progressive
  disclosure).
- Troubleshooting entries need **symptom as observed, root cause with
  evidence, verified fix**. Mark unverified fixes explicitly.
- State the access level (local, observe, GitOps, break-glass) for any
  procedure that touches a server.
- Explain *why* a rule exists; agents follow reasons better than commands.

## Scripts

- Bash with `set -euo pipefail` (or a documented reason not to), shellcheck
  clean, `--help` output, no hardcoded hosts/users/keys.
- Read-only scripts must never read secret values; use allowlists.
- Pass credentials through stdin or files with mode 600, never as arguments.
