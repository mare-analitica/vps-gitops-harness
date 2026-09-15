#!/usr/bin/env bash
# =============================================================================
# diagnose.sh - READ-ONLY state report of a single-node Docker Swarm host.
#
# Collects host resources, Swarm services, failing services with their tasks
# and logs, unhealthy containers, memory per container, repository drift and
# deploy-queue status. It never reads secret values: only names of Docker
# Secrets, and configuration keys from an explicit allowlist.
#
# Usage:
#   diagnose.sh <user@host> [-i ssh_key]     run remotely over SSH
#   diagnose.sh --local                      run on the host itself
#   diagnose.sh --help
#
# Environment:
#   DEPLOY_ROOT   repository path on the host   (default: /opt/platform)
#   LOG_LINES     log lines per failing service  (default: 60)
# =============================================================================
set -uo pipefail

DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/platform}"
LOG_LINES="${LOG_LINES:-60}"

usage() {
    # Prints the header comment block (after the first "# ===" line, until the next one).
    awk 'NR > 2 && /^# =+$/ { exit } NR > 2 { sub(/^# ?/, ""); print }' "$0"
}

die() {
    echo "diagnose.sh: $*" >&2
    exit 1
}

[[ "$LOG_LINES" =~ ^[0-9]+$ ]] || die "LOG_LINES must be a number"
[[ "$DEPLOY_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "DEPLOY_ROOT must be an absolute path"

# The report runs as a single script on the host (one SSH connection).
read -r -d '' REPORT <<'EOF'
set -uo pipefail
section() { printf '\n===== %s =====\n' "$1"; }

section "HOST"
echo "hostname: $(hostname)  kernel: $(uname -r)  vcpu: $(nproc)"
uptime
free -h | head -2
awk '/SwapTotal/ {printf "swap: %d MB\n", $2/1024}' /proc/meminfo
df -h / | tail -1
dmesg -T 2>/dev/null | grep -iE 'killed process|out of memory' | tail -5

section "SWARM"
docker info --format 'swarm: {{.Swarm.LocalNodeState}}  docker: {{.ServerVersion}}' 2>/dev/null
docker stack ls 2>/dev/null
echo
docker service ls --format 'table {{.Name}}\t{{.Replicas}}\t{{.Image}}' 2>/dev/null

section "FAILING SERVICES"
# Replicas like "0/1" or "1/1 (0/1 completed)"; completed jobs are not failures.
failing="$(docker service ls --format '{{.Name}} {{.Replicas}}' 2>/dev/null | awk '{
    split($2, r, "/"); current = r[1]; desired = r[2];
    if ($0 ~ /completed\)/) next;
    if (desired != "0" && current != desired) print $1 }')"
[ -n "$failing" ] || echo "none (all desired replicas are running)"
for svc in $failing; do
    echo "--- $svc: latest tasks"
    docker service ps "$svc" --no-trunc --format '  {{.CurrentState}} | {{.Error}}' | head -5
    echo "--- $svc: memory limit / image"
    docker service inspect "$svc" --format '  mem={{.Spec.TaskTemplate.Resources.Limits.MemoryBytes}} image={{.Spec.TaskTemplate.ContainerSpec.Image}}'
    echo "--- $svc: last __LOG_LINES__ log lines"
    docker service logs --tail "__LOG_LINES__" --raw "$svc" 2>&1 | tail -n "__LOG_LINES__" | sed 's/^/  /'
done

section "UNHEALTHY CONTAINERS"
docker ps --filter health=unhealthy --format '{{.Names}} ({{.Status}})'

section "MEMORY PER CONTAINER"
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}' 2>/dev/null | head -60

section "REPOSITORY DRIFT (__DEPLOY_ROOT__)"
if [ -d "__DEPLOY_ROOT__/.git" ]; then
    git -C "__DEPLOY_ROOT__" log --oneline -3
    echo "branch: $(git -C "__DEPLOY_ROOT__" rev-parse --abbrev-ref HEAD)"
    changes="$(git -C "__DEPLOY_ROOT__" status -s)"
    if [ -n "$changes" ]; then echo "CHANGES OUTSIDE GIT:"; echo "$changes"; else echo "clean working tree"; fi
else
    echo "repository not found"
fi

section "CLIENT CONFIG (allowlisted keys only)"
# Allowlist, never suffix filters: *_SECRET / *_KEY / *_TOKEN may hold values.
for cfg in "__DEPLOY_ROOT__"/clients/*/config.env; do
    [ -f "$cfg" ] || continue
    echo "--- $cfg"
    grep -E '^(DOMAIN_NAME|[A-Z0-9_]+_DOMAIN|[A-Z0-9_]+_TENANTS|[A-Z0-9_]+_IMAGE|[A-Z0-9_]+_VERSION|[A-Z0-9_]+_REPLICAS|[A-Z0-9_]+_MIDDLEWARES)=' "$cfg"
done

section "DOCKER SECRETS (names only)"
docker secret ls --format '{{.Name}}' 2>/dev/null | tr '\n' ' '
echo

section "DEPLOY QUEUE"
if command -v deploy-queue >/dev/null 2>&1; then
    deploy-queue status 2>/dev/null | tail -20
    pgrep -af 'deploy-queue (stack|app)' | grep -v pgrep || echo "no deploy running"
else
    echo "deploy-queue not installed"
fi
tmux ls 2>/dev/null || true
EOF

REPORT="${REPORT//__LOG_LINES__/$LOG_LINES}"
REPORT="${REPORT//__DEPLOY_ROOT__/$DEPLOY_ROOT}"

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    --local)
        bash -c "$REPORT"
        exit 0
        ;;
    "")
        usage >&2
        exit 2
        ;;
esac

target="$1"
shift
ssh_args=(-o BatchMode=yes -o ConnectTimeout=10)
while [ "$#" -gt 0 ]; do
    case "$1" in
        -i)
            [ -n "${2:-}" ] || die "-i requires a key path"
            ssh_args+=(-i "$2")
            shift 2
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

ssh "${ssh_args[@]}" "$target" bash -s <<<"$REPORT"
