# Team access

Read this for: adding or removing a developer, "give access to CI/vault",
groups, 2FA, API tokens, repository permissions, periodic access review.

## Principles

1. **One identity per person, in one place (the SSO provider).** CI, vault
   and admin tools trust it, so onboarding and — above all — offboarding happen
   once. Shared accounts are forbidden: they destroy traceability and cannot be
   revoked for one person.
2. **Permissions belong to groups, defined as code.** People join or leave
   groups; nobody gets ad-hoc permissions.
3. **2FA for every group.** Developers write production secrets and trigger
   deploys. A leaked password without 2FA is a compromised production.
4. **Machine credentials are personal and revocable.** API tokens are created
   by their owner, named per machine, revoked on departure.
5. **The default branch is production.** Branch protection is part of access
   control, not a nice-to-have.

## Group × system matrix (template)

| System | `/devs` | `/platform-admins` |
| --- | --- | --- |
| CI | Read jobs and logs, **trigger/cancel builds** (= deploy), workspace | Administer |
| Vault (OIDC login) | Create/read/update/delete versions under app paths | Everything |
| Internal tools behind team SSO | Access | Access |
| Admin panels behind admin SSO | — | Access |
| SSO admin console | — | Access (also IP-allowlisted) |
| SSH to the server, stack deploys | **Never** | Platform operators only (key + IP allowlist) |
| Business apps (CRM, ERP) | Their own accounts per app | Same |

Keep one or two platform admins. Every extra admin is extra attack surface.

## Onboarding (example: five developers)

### 0. Plan

A table with name, username (`first.last`), work email, group, Git hosting
account and repositories. Use a work email (account recovery) and never reuse
a former employee's username.

### 1. SSO provider (a platform admin)

1. Create the user in the platform realm, email marked verified if the realm
   does not send mail.
2. Required actions: update password and configure OTP.
3. Add to `/devs`. No direct permissions.
4. Set a strong temporary password.
5. Deliver username and password through **different channels**.

The provisioning job should also add the OTP requirement to any member of an
enforced group who has no OTP, on every run.

### 2. First login (the developer)

1. Log in → change password → configure the authenticator app.
2. Check CI (jobs visible), vault (OIDC method, app paths listed) and internal
   tools.
3. Groups are read at login: if something is missing, log out and in again.

### 3. Git hosting (an organization owner)

1. Invite to the organization and to a team; grant repository access to the
   team, not the person.
2. Require 2FA for the organization.
3. On every repository with a deploying job: pull request required, at least
   one approval, no direct or force pushes, up-to-date branch. Code owners for
   pipeline files, Dockerfiles and entrypoints.

### 4. CI API token (optional, for the CLI)

Created by the developer, one per machine, stored in a mode-600 file outside
any repository.

### 5. Vault usage rules

- Each save is a new version; the next app deploy picks `latest`.
- Production values never go into local `.env` files.
- Do not delete old versions without agreement: they are rollback points.

## Offboarding (same day, in this order)

1. **SSO**: disable the user (keep it for audit) and sign out all sessions.
2. **CI**: revoke the person's API tokens. Disabling the SSO user does **not**
   invalidate tokens that work without an SSO session.
3. **Git hosting**: remove from the organization.
4. **Vault**: check the audit log for recent reads.
5. **Rotate every secret the person's group could read**, highest impact
   first: payment keys, session signing secrets (this logs end users out),
   OAuth and CRM tokens. New vault version, then run each app's job.
6. Disable accounts in business apps.
7. Record date, executor and what was rotated.

A departing platform admin additionally requires: SSH key removal via config
management, admin password changes for SSO and vault, and a vault rekey if they
held an unseal key share.

## Quarterly review (30 minutes)

- SSO: group members match the access sheet; nobody without OTP; long-disabled
  users removed.
- CI: stale or unused tokens revoked.
- Git hosting: members, outside collaborators, branch rules intact.
- Vault: unusual reads of app paths in the audit log.

## What the agent does and does not do

- **Does:** explain the procedure, prepare the access sheet, review the
  permission matrix in code, propose changes through pull requests.
- **Does not:** create or disable users, generate or view people's passwords
  or tokens, change organization membership.
