#!/usr/bin/env bash
# Run one attempt for the driver: no terminal, `claude -p <prompt>`, and the
# agent's exit code as this script's. The agent's stdout is this script's
# stdout; everything else goes to stderr.
# Usage: ./drive.sh <project> <attempt-dir> <prompt> [claude option...]
#   <project>      the compose project, gauge-run-<loop>-<attempt>
#   <attempt-dir>  holds repo/ (mounted at /workspace), run/brief.json
#                  (read-only at /run/brief.json) and run/outbox/ (at
#                  /run/outbox, the brief's outbox_path)
# Environment:
#   AGENT_NAME, AGENT_EMAIL  the bot identity for commits (required)
#   RSB_SKILLS               the rsb-skills checkout whose implement, tdd and
#                            rsb-code-review skills are mounted read-only
#                            (default ~/code/software/rsb/factory/rsb-skills)
#   AGENT_BOX_CLAUDE_ENV     the env file holding CLAUDE_CODE_OAUTH_TOKEN
#                            (default ~/.config/rsb/agent-box/claude.env)
set -euo pipefail
cd "$(dirname "$0")"

# The same refusal as start.sh: a changed file is the one thing that would
# silently widen what the agent can reach.
if [ "$(git symbolic-ref --short -q HEAD)" != main ]; then
  echo "drive.sh: agent-box is not on main" >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "drive.sh: agent-box has uncommitted changes; commit or discard them first" >&2
  git status --short >&2
  exit 1
fi

usage="usage: drive.sh <project> <attempt-dir> <prompt> [claude option...]"
project=${1:?$usage}
attempt=${2:?$usage}
prompt=${3:?$usage}
shift 3
: "${AGENT_NAME:?set the bot identity in the environment}" "${AGENT_EMAIL:?set the bot identity in the environment}"
RSB_SKILLS=${RSB_SKILLS:-$HOME/code/software/rsb/factory/rsb-skills}
AGENT_BOX_CLAUDE_ENV=${AGENT_BOX_CLAUDE_ENV:-$HOME/.config/rsb/agent-box/claude.env}

if ! [[ $project =~ ^[a-z0-9][a-z0-9_-]*$ ]] || [ "$project" = agent-box ]; then
  echo "drive.sh: project $project is not a compose project name, or is the desk's" >&2
  exit 2
fi
if ! ATTEMPT_DIR=$(cd "$attempt" 2>/dev/null && pwd -P); then
  echo "drive.sh: no attempt directory $attempt" >&2
  exit 2
fi
for p in "$ATTEMPT_DIR/repo/.git" "$ATTEMPT_DIR/run/outbox" \
  "$RSB_SKILLS/skills/engineering/implement" "$RSB_SKILLS/skills/engineering/tdd" \
  "$RSB_SKILLS/skills/engineering/rsb-code-review"; do
  if [ ! -d "$p" ] || [ -L "$p" ]; then
    echo "drive.sh: $p is not a directory" >&2
    exit 2
  fi
done
if [ ! -f "$ATTEMPT_DIR/run/brief.json" ] || [ -L "$ATTEMPT_DIR/run/brief.json" ]; then
  echo "drive.sh: $ATTEMPT_DIR/run/brief.json is not a regular file" >&2
  exit 2
fi
# The sign-in: a regular file, not a link, that only its owner can read.
# Its contents are never read here; the entrypoint refuses an empty token.
if [ ! -f "$AGENT_BOX_CLAUDE_ENV" ] || [ -L "$AGENT_BOX_CLAUDE_ENV" ] \
  || [ -n "$(find "$AGENT_BOX_CLAUDE_ENV" -perm /077)" ]; then
  echo "drive.sh: $AGENT_BOX_CLAUDE_ENV is not a regular file of mode 600 (see README.md, Sign-in)" >&2
  exit 2
fi
if ! jq -e '.schema == "brief/v1" and .outbox_path == "/run/outbox"' \
  "$ATTEMPT_DIR/run/brief.json" >/dev/null; then
  echo "drive.sh: the brief is not brief/v1 with outbox_path /run/outbox" >&2
  exit 2
fi

# The agent runs as uid 0 (compose.driver.yaml). Only rootless Docker makes
# that the host user; anywhere else it would be the host's root.
if ! docker info --format '{{.SecurityOptions}}' | grep -q 'name=rootless'; then
  echo "drive.sh: Docker is not rootless; the agent runs as uid 0, which only rootless Docker maps to you (see README.md)" >&2
  exit 2
fi

export COMPOSE_PROJECT_NAME=$project
export COMPOSE_FILE=compose.yaml:compose.driver.yaml
BRANCH=$(git -C "$ATTEMPT_DIR/repo" symbolic-ref --short -q HEAD || :)
export ATTEMPT_DIR RSB_SKILLS AGENT_BOX_CLAUDE_ENV AGENT_NAME AGENT_EMAIL BRANCH
cname=$project-agent

# shellcheck disable=SC2317  # run by the EXIT trap
cleanup() {
  docker compose down --rmi local -v --remove-orphans >&2 \
    || echo "drive.sh: could not take down project $project" >&2
}

# Two networks per project, each with a /24 of 10.77.0.0/16 that no network
# has yet. Two launches can still pick the same one; docker then refuses
# the second, and it picks again.
free_subnets() {
  local used n out=()
  used=$(docker network ls -q | xargs -r docker network inspect \
    --format '{{range .IPAM.Config}}{{.Subnet}} {{end}}')
  for n in $(seq 2 254 | shuf); do
    case " $used " in *" 10.77.$n.0/24 "*) continue ;; esac
    out+=("10.77.$n.0/24")
    [ ${#out[@]} -lt 2 ] || break
  done
  [ ${#out[@]} -eq 2 ] || return 1
  echo "${out[@]}"
}

docker compose build agent >&2
tries=0
while :; do
  read -r BOX_SUBNET BOX_CODEX_SUBNET < <(free_subnets) || {
    echo "drive.sh: no free subnet in 10.77.0.0/16" >&2
    exit 1
  }
  export BOX_SUBNET BOX_CODEX_SUBNET
  if err=$(docker compose up --no-start --build proxy 2>&1); then
    break
  fi
  echo "$err" >&2
  docker compose down --rmi local --remove-orphans >&2 || :
  tries=$((tries + 1))
  if ! grep -qi overlap <<<"$err" || [ "$tries" -ge 5 ]; then
    exit 1
  fi
done
trap cleanup EXIT

echo "drive.sh: $project as $AGENT_NAME on ${BRANCH:-a detached head} in $ATTEMPT_DIR" >&2
# The run is a child so a stop signal can reach the container: docker stop
# gives the agent its 30 s to exit.
docker compose up -d proxy >&2
docker compose run --rm --no-deps -T --name "$cname" agent \
  claude -p "$prompt" "$@" </dev/null &
pid=$!
trap 'docker stop -t 30 "$cname" >/dev/null 2>&1 || :' TERM INT HUP
while :; do
  wait "$pid" && rc=0 || rc=$?
  kill -0 "$pid" 2>/dev/null || break
done
exit "$rc"
