#!/usr/bin/env bash
# =============================================================================
# jenkins.sh - Jenkins CLI over the REST API (curl + jq, no Java required).
#
#   jenkins.sh whoami                  current user and groups
#   jenkins.sh jobs                    jobs with last build and result
#   jenkins.sh status <job> [n]        build details (default: last build)
#   jenkins.sh logs   <job> [n] [-f]   console output (-f follows until done)
#   jenkins.sh build  <job> [-f]       trigger the job (and follow with -f)
#   jenkins.sh stop   <job> <n>        abort build n
#   jenkins.sh --help
#
# WARNING: building a job that deploys the default branch IS a production
# deploy. Agents only trigger builds when the user explicitly asks.
#
# Configuration (your own API token, never someone else's):
#   file ${JENKINS_CREDENTIALS_FILE:-~/.config/vps-gitops/jenkins.env}, mode 600:
#     JENKINS_URL=https://ci.example.com
#     JENKINS_USER=first.last
#     JENKINS_TOKEN=<API token>
#   or the same variables in the environment. The token is passed to curl
#   through stdin (not visible in the process list) and is never printed.
# =============================================================================
set -euo pipefail

CRED_FILE="${JENKINS_CREDENTIALS_FILE:-$HOME/.config/vps-gitops/jenkins.env}"

die() {
    echo "jenkins.sh: $*" >&2
    exit 1
}

usage() {
    # Prints the header comment block (after the first "# ===" line, until the next one).
    awk 'NR > 2 && /^# =+$/ { exit } NR > 2 { sub(/^# ?/, ""); print }' "$0"
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") usage >&2; exit 2 ;;
esac

command -v curl >/dev/null || die "curl is required"
command -v jq >/dev/null || die "jq is required"

_cred() {
    # Reads KEY=value from the credentials file without executing it.
    [ -f "$CRED_FILE" ] || return 0
    sed -n "s/^$1=//p" "$CRED_FILE" | tail -1 | tr -d '\r'
}

JENKINS_URL="${JENKINS_URL:-$(_cred JENKINS_URL)}"
JENKINS_USER="${JENKINS_USER:-$(_cred JENKINS_USER)}"
JENKINS_TOKEN="${JENKINS_TOKEN:-$(_cred JENKINS_TOKEN)}"
JENKINS_URL="${JENKINS_URL%/}"

[ -n "$JENKINS_URL" ] || die "JENKINS_URL is not set (environment or $CRED_FILE)"
[ -n "$JENKINS_USER" ] && [ -n "$JENKINS_TOKEN" ] \
    || die "JENKINS_USER and JENKINS_TOKEN are required (environment or $CRED_FILE)"

if [ -f "$CRED_FILE" ] && [[ "$(uname -s)" != MINGW* && "$(uname -s)" != MSYS* ]]; then
    perms="$(stat -c %a "$CRED_FILE" 2>/dev/null || stat -f %Lp "$CRED_FILE")"
    [ "$perms" = "600" ] || echo "jenkins.sh: warning: chmod 600 $CRED_FILE (currently $perms)" >&2
fi

_curl() {
    # user:token through stdin (-K -), not as a visible argument.
    printf 'user = "%s:%s"\n' "$JENKINS_USER" "$JENKINS_TOKEN" \
        | curl -sS --fail-with-body --max-time 60 -K - "$@"
}

_api() {
    _curl "$JENKINS_URL$1" | tr -d '\r'
}

_job_path() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid job name: $1"
    printf '/job/%s' "$1"
}

# Jenkins console output carries hidden annotations (ESC[8mha:////...ESC[0m).
_clean_console() {
    local esc
    esc="$(printf '\033')"
    sed -E "s/${esc}\[8mha:[^${esc}]*${esc}\[0m//g"
}

_build_number() {
    # Explicit build number, or the last build of the job.
    local job="$1" n="${2:-}"
    if [ -z "$n" ] || [ "$n" = "last" ]; then
        n="$(_api "$(_job_path "$job")/api/json?tree=lastBuild%5Bnumber%5D" | jq -r '.lastBuild.number // empty')"
        [ -n "$n" ] || die "job '$job' has no builds yet"
    fi
    [[ "$n" =~ ^[0-9]+$ ]] || die "invalid build number: $n"
    printf '%s' "$n"
}

cmd_whoami() {
    _api "/me/api/json?tree=id,fullName" | jq -r '"user: \(.id) (\(.fullName))"'
    _api "/whoAmI/api/json" \
        | jq -r '"authenticated: \(.authenticated)  groups: \(.authorities | map(select(. != "authenticated")) | join(", "))"'
}

cmd_jobs() {
    _api "/api/json?tree=jobs%5Bname,lastBuild%5Bnumber,result,timestamp,building%5D%5D" \
        | jq -r '.jobs[] | [
              .name,
              (if .lastBuild == null then "-" else "#\(.lastBuild.number)" end),
              (if .lastBuild == null then "no builds"
               elif .lastBuild.building then "RUNNING"
               else (.lastBuild.result // "?") end),
              (if .lastBuild == null then ""
               else (.lastBuild.timestamp / 1000 | strflocaltime("%Y-%m-%d %H:%M")) end)
            ] | @tsv' \
        | { column -t -s $'\t' 2>/dev/null || cat; }
}

cmd_status() {
    local job="$1" n
    n="$(_build_number "$job" "${2:-}")"
    _api "$(_job_path "$job")/$n/api/json?tree=number,result,building,duration,timestamp,actions%5BlastBuiltRevision%5BSHA1%5D,causes%5BshortDescription%5D%5D" \
        | jq -r '"build:     #\(.number)",
                 "state:     \(if .building then "RUNNING" else (.result // "?") end)",
                 "started:   \(.timestamp / 1000 | strflocaltime("%Y-%m-%d %H:%M:%S"))",
                 "duration:  \(if .building then "-" else "\(.duration / 1000 | floor)s" end)",
                 "commit:    \([.actions[] | .lastBuiltRevision.SHA1? // empty][0] // "-")",
                 "cause:     \([.actions[] | .causes[]?.shortDescription][0] // "-")"'
}

cmd_logs() {
    local job="$1" follow=false start=0 n headers more size arg
    shift
    local positional=()
    for arg in "$@"; do
        if [ "$arg" = "-f" ]; then follow=true; else positional+=("$arg"); fi
    done
    n="$(_build_number "$job" "${positional[0]:-}")"
    headers="$(mktemp)"
    # shellcheck disable=SC2064  # expand now: the local variable is gone on RETURN
    trap "rm -f '$headers'" RETURN
    while :; do
        _curl -D "$headers" "$JENKINS_URL$(_job_path "$job")/$n/logText/progressiveText?start=$start" | _clean_console
        more="$(tr -d '\r' < "$headers" | sed -n 's/^[Xx]-[Mm]ore-[Dd]ata: *//p' | tail -1)"
        size="$(tr -d '\r' < "$headers" | sed -n 's/^[Xx]-[Tt]ext-[Ss]ize: *//p' | tail -1)"
        [ -n "$size" ] && start="$size"
        if [ "$follow" = true ] && [ "$more" = "true" ]; then
            sleep 3
        else
            break
        fi
    done
    if [ "$follow" = true ]; then
        cmd_status "$job" "$n" | sed -n '2p'
    fi
}

cmd_build() {
    local job="$1" follow="${2:-}" headers location queue_path n="" _
    headers="$(mktemp)"
    _curl -X POST -D "$headers" -o /dev/null "$JENKINS_URL$(_job_path "$job")/build"
    location="$(tr -d '\r' < "$headers" | sed -n 's/^[Ll]ocation: *//p' | tail -1)"
    rm -f "$headers"
    [ -n "$location" ] || die "Jenkins did not return a queue location"
    queue_path="${location%/}"
    queue_path="/${queue_path#*://*/}"
    echo "queued: ${JENKINS_URL}${queue_path}"
    for _ in $(seq 1 100); do
        n="$(_api "$queue_path/api/json" | jq -r 'if .cancelled then "cancelled" else (.executable.number // empty) end')"
        [ -n "$n" ] && break
        sleep 3
    done
    [ "$n" = "cancelled" ] && die "build was cancelled in the queue"
    [ -n "$n" ] || die "build did not leave the queue within 5 minutes (busy executors?)"
    echo "build #$n: ${JENKINS_URL}$(_job_path "$job")/$n/"
    if [ "$follow" = "-f" ]; then
        cmd_logs "$job" "$n" -f
    fi
}

cmd_stop() {
    local job="$1" n="${2:-}"
    [[ "$n" =~ ^[0-9]+$ ]] || die "usage: stop <job> <build-number>"
    _curl -X POST -o /dev/null "$JENKINS_URL$(_job_path "$job")/$n/stop"
    echo "abort requested: $job #$n"
}

# Validate the job name in the main shell: die inside $(...) would not exit.
[ -z "${2:-}" ] || _job_path "$2" >/dev/null

case "$1" in
    whoami) cmd_whoami ;;
    jobs)   cmd_jobs ;;
    status) [ -n "${2:-}" ] || die "usage: status <job> [n]"; cmd_status "$2" "${3:-}" ;;
    logs)   [ -n "${2:-}" ] || die "usage: logs <job> [n] [-f]"; shift; cmd_logs "$@" ;;
    build)  [ -n "${2:-}" ] || die "usage: build <job> [-f]"; cmd_build "$2" "${3:-}" ;;
    stop)   [ -n "${2:-}" ] || die "usage: stop <job> <n>"; cmd_stop "$2" "${3:-}" ;;
    *)      usage >&2; exit 2 ;;
esac
