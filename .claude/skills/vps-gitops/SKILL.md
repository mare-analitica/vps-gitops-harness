---
name: vps-gitops
description: Operate and evolve a single-VPS Docker Swarm platform the GitOps way — deploy queue with health checks and rollback, reverse proxy with automatic TLS, SSO with 2FA, a secrets vault, CI that builds without host Docker access, and per-client app stacks. Use this skill WHENEVER the conversation touches deploys, a Swarm stack or service (0/1 replicas, crash loops, rollbacks, timeouts), stack files or deploy hooks, CI pipelines and build logs, app secrets or env files, SSO/2FA and team access (onboarding, offboarding, API tokens), VPS capacity (RAM, CPU, OOM), TLS/DNS/routing, or when the user asks to "check production", "look at the logs", "ship" or "roll back" something — even if they never say "DevOps".
---

# VPS GitOps operations

This skill makes an AI agent useful on a production VPS **without turning it
into a loose root shell**. The Git repository is the source of truth; the
server is derived from it. Every change is reviewable, repeatable and
reversible.

## 1. What success looks like

- A new client environment comes up from zero with **no manual step outside
  the repository**, except secrets that only a human can provide (vendor
  licenses, third-party tokens).
- Any server can be rebuilt from Git plus the host secrets directory.
- Deploys are boring: queued, validated, health-checked and rolled back
  automatically when they fail.
- Access is revocable in one place, per person, the same day.

Decisions that add manual steps or create drift between server and Git go
against the project, even when they "fix it now".

## 2. Decide the access level BEFORE acting

| Level | Allowed | Examples |
| --- | --- | --- |
| **0 · Local** | Freely | Read/edit the repo, render stack files (`docker stack config`), `bash -n`, linters, local container tests |
| **1 · Observe** | Freely, read-only | `scripts/diagnose.sh`, `docker service ls/ps/logs`, `free`, `df`, `git log` on the server, CI status and build logs |
| **2 · Change via GitOps** | Default for any change | Edit in the repo → commit → human pushes/merges → apply through the deploy queue or the CI job |
| **3 · Break-glass** | Only when the user explicitly asks for *that* action | Triggering a production deploy from CI, service updates outside the queue, editing files on the server, restarts, DNS/firewall changes |

Why: production holds customer data and every credential. A wrong command is
often irreversible, and a fix applied only on the server is silently undone by
the next deploy.

Rules for level 3:

1. State the exact command, its impact and how to undo it before running it.
2. Back up whatever changes (timestamped copy; snapshot for large changes).
3. Run long processes in `tmux` with output teed to a log.
4. Reproduce the change in the repository in the same session and report the
   drift until it is reconciled.

Commands per level, traps and the break-glass checklist:
**`references/access-and-guardrails.md`**.

## 3. Never (without an explicit, specific request)

- Remove volumes, secrets or stacks; `docker system prune -a`; destroy or
  reinstall the server.
- Print secret values: env files, Docker Secrets, tokens, unseal keys. Work
  with **names**, never values.
- Upgrade or downgrade a database major version on a populated volume.
- Touch firewall/SSH hardening out of order (you can lock everyone out).
- Commit host inventories, env files, state files or anything under a secrets
  path.
- Push, merge or open pull requests without being asked.
- Create or disable user accounts, or ask for passwords/API tokens in chat.

## 4. Standard workflow

1. **Understand the state.** Read the repository. For production, prefer the
   read-only report (`scripts/diagnose.sh`) over ad-hoc commands.
2. **Find the root cause, not the symptom.** Check
   `references/troubleshooting.md` first — most failures repeat.
3. **Fix it in the repository** (stack file, hook, script, pipeline), with a
   short comment explaining *why*.
4. **Validate locally**: render the stack, lint scripts, reproduce in a
   throwaway container when possible.
5. **Hand over the apply step** (level 2) or, if authorized, apply it through
   the deploy queue (level 3).
6. **Record the lesson**: a new incident becomes a row in the troubleshooting
   catalog.

## 5. Map

| Topic | Reference |
| --- | --- |
| Reference platform, stacks, isolation model, source of truth | `references/architecture.md` |
| Commands per level, traps, break-glass checklist | `references/access-and-guardrails.md` |
| Deploy queue, stack vs app deploys, config layering, image pinning | `references/deploy-queue.md` |
| Host secrets, vault-versioned app env, human-provided secrets, rotation | `references/secrets.md` |
| CI without host Docker, jobs as code, API tokens, known limits | `references/ci-pipeline.md` |
| Team groups, 2FA, onboarding/offboarding, access reviews | `references/team-access.md` |
| Memory/CPU budgeting and upgrade triggers | `references/capacity.md` |
| Symptom → cause → fix catalog | `references/troubleshooting.md` |

## 6. Response format

When reporting a diagnosis or a change:

```text
State:        what is healthy / what is not (short table if useful)
Root cause:   evidence (log line, command output) → explanation
Proposed fix: files + summarized diff + why
How to apply: exact command and who runs it (human / CI / authorized agent)
Risks:        data, server/Git drift, capacity, anything not verified
```

Always separate what was **verified** from what is **inferred**.
