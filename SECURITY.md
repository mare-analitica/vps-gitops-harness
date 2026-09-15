# Security policy

## Reporting a vulnerability

**Do not open a public issue.** Report privately through
[GitHub Security Advisories](https://github.com/mare-analitica/vps-gitops-harness/security/advisories/new).

Include:

- What is affected (file, script, documented procedure) and the impact.
- Steps to reproduce, with **all real hostnames, IPs, credentials and customer
  data redacted**.
- Any suggested fix.

You can expect an acknowledgement within 5 business days and a status update
within 15 business days.

## Scope

In scope:

- Scripts in this repository (e.g. a read-only script that could expose secret
  values, command injection through arguments).
- Documented procedures that would lead operators or AI agents to leak
  credentials, lose data or lock themselves out.
- CI configuration of this repository.

Out of scope:

- Vulnerabilities in third-party software referenced by the documentation
  (report them upstream).
- Findings on servers you do not own or are not authorized to test.

## Supported versions

| Version | Supported |
| --- | --- |
| Latest release on `main` | Yes |
| Older releases | No |

## If you committed a secret by mistake

Treat the secret as compromised: **revoke and rotate it first**, then remove it.
Deleting a commit or force-pushing does not undo exposure, because forks,
clones and caches may already hold it.
