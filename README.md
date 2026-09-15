# vps-gitops-harness

[![ci](https://github.com/mare-analitica/vps-gitops-harness/actions/workflows/ci.yml/badge.svg)](https://github.com/mare-analitica/vps-gitops-harness/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

GitOps platform harness for a single VPS running Docker Swarm, with an AI
operations skill that lets an agent observe, diagnose and change production
**through Git and a deploy queue — never as a loose root shell**.

> **Status:** early. Milestone
> [v0.1.0 — Skill foundation](https://github.com/mare-analitica/vps-gitops-harness/milestone/1)
> delivers the AI skill and the repository foundation. Platform components
> (deploy queue, stack templates, host roles) follow in later milestones.

## Why

Small teams run real products on a single VPS. What usually goes wrong is not
the technology but the operation: floating image tags that upgrade by surprise,
secrets pasted into env files, deploys without rollback, and access nobody can
revoke. This harness packages a predictable way to operate that setup — and
teaches AI agents to respect it.

## The `vps-gitops` skill

Located in [`.claude/skills/vps-gitops/`](.claude/skills/vps-gitops/SKILL.md).

| Part | What it gives the agent |
| --- | --- |
| `SKILL.md` | Access levels (local · observe · GitOps · break-glass), never-do list, workflow, response format |
| `references/architecture.md` | Reference platform, config layering, per-app isolation, networks |
| `references/access-and-guardrails.md` | Commands per level, read-only traps, break-glass checklist |
| `references/deploy-queue.md` | Queued, validated, health-checked deploys with rollback |
| `references/secrets.md` | Host, vault and human-provided secrets; rotation |
| `references/ci-pipeline.md` | CI without host Docker, restricted deploy key, jobs as code |
| `references/team-access.md` | Groups, 2FA, onboarding and same-day offboarding |
| `references/capacity.md` | Memory/CPU budgeting on small servers |
| `references/troubleshooting.md` | Symptom → root cause → verified fix, from real incidents |
| `scripts/diagnose.sh` | Read-only server report (never reads secret values) |
| `scripts/jenkins.sh` | CI status, logs and builds over REST |

### Use it

- **In this repository:** Claude Code loads project skills from
  `.claude/skills/` automatically.
- **In your own infrastructure repository:** copy the folder.

  ```bash
  mkdir -p .claude/skills
  cp -r path/to/vps-gitops-harness/.claude/skills/vps-gitops .claude/skills/
  ```

- **For all your projects:** copy it to `~/.claude/skills/vps-gitops`.

Then ask things like *"why is the api service 0/1?"*, *"prepare the deploy of
the new worker"* or *"offboard a developer"*. The agent reads production freely
but changes it only through Git, or when you explicitly ask for a break-glass
action.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: [SECURITY.md](SECURITY.md).

## License

Copyright 2026 Paulo. Licensed under the [Apache License 2.0](LICENSE);
see [NOTICE](NOTICE).
