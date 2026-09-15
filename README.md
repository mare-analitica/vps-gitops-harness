# vps-gitops-harness

GitOps platform harness for a single VPS running Docker Swarm, with an AI
operations skill that lets an agent observe, diagnose and change production
**through Git and a deploy queue — never as a loose root shell**.

> **Status:** early. Milestone
> [v0.1.0 — Skill foundation](https://github.com/mare-analitica/vps-gitops-harness/milestone/1)
> delivers the AI skill (guardrails, runbooks, field-tested troubleshooting)
> and the repository foundation. Platform components follow in later milestones.

## Why

Small teams run real products on a single VPS. What usually goes wrong is not
the technology but the operation: floating image tags that upgrade by surprise,
secrets pasted into env files, deploys without rollback, and access that nobody
can revoke. This harness packages a predictable way to operate that setup.

## License

Copyright 2026 Paulo. Licensed under the [Apache License 2.0](LICENSE);
see [NOTICE](NOTICE).
