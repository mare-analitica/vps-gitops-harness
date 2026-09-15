# Capacity

A small VPS runs far more than people expect — until a first boot, a build or
a migration spike turns into an OOM kill. Budget explicitly.

## Limits versus real usage

- `deploy.resources.limits.memory` is what Swarm lets a service grow to; real
  usage is usually lower. Sum both:

  ```bash
  grep -h 'memory:' setup/docker/*-stack.yml                      # declared limits
  docker stats --no-stream --format '{{.Name}} {{.MemUsage}}'       # real usage
  ```

- A healthy target: real usage under ~70% of RAM at idle, leaving room for CI
  builds and first boots.
- Reservations (`resources.reservations`) are enforced by the scheduler: a
  vendor stack reserving more than the node has left will not schedule at all.

## Where memory goes on a small server

| Component type | Typical idle footprint | Notes |
| --- | --- | --- |
| Reverse proxy, socket proxy, registry | Tens of MB each | Cheap |
| SSO provider (JVM) | 400–600 MB | Heavy first boot |
| PostgreSQL / Redis shared | 50–150 MB / 10–50 MB | Grows with data and connections |
| CI server (JVM) | 300–500 MB | Builds run in BuildKit, which spikes separately |
| Rails app + background worker | 250–500 MB each | Reduce worker concurrency on small servers |
| ClickHouse | 100 MB+ | Default caches assume a dedicated server; shrink caches and disable internal log tables |
| Node/NestJS API | 40–150 MB | |
| Static frontend (nginx) | < 10 MB | |

## Tuning that pays off

- Worker concurrency (Sidekiq, queues) down to 3–5.
- Database/cache caches sized explicitly below the container limit (e.g.
  WiredTiger cache, ClickHouse mark cache). Many engines size caches from
  **host** RAM, not the container limit.
- Node heap (`--max-old-space-size`) below the container limit; with too small
  a limit some apps cannot boot at all.
- Do **not** shrink internal thread pools blindly: some engines refuse to start
  when pools fall below dependent settings.

## CPU

- With 2 vCPU, parallel first boots (migrations, JVM warm-up) push load average
  far above the core count. Deploy heavy stacks one at a time and wait for load
  to drop.
- Long `start_period` on healthchecks for services that migrate on boot, or
  the healthcheck kills them mid-migration.

## Saturation signals

- Tasks exiting with `137` → memory limit or host OOM (`dmesg -T | grep -i oom`).
- Load average persistently above vCPU count.
- `available` memory in `free -m` under ~15% at idle.
- Healthchecks timing out without application errors.
- Disk: registry and build cache growth (`docker system df`); prune build cache,
  never volumes.

## Upgrade triggers

Propose a bigger plan (or moving a heavy product out) when:

- Adding a product would push idle usage above ~80%.
- OOM kills repeat after tuning.
- CI builds regularly degrade production latency.
- A product the client depends on (e.g. CRM with messaging) needs to run next
  to test environments (ERP sandboxes) that could be switched off instead.

When proposing, show the arithmetic: current real usage, the new component's
expected footprint, the resulting headroom, and the options (tune, switch off
non-essential stacks, add swap as a buffer, upgrade).
