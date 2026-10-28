#!/usr/bin/env bash
# Copy a branch out of the box and fetch it into the owner's clone as
# agent/<branch>, with hooks and fsmonitor off. Nothing is pushed.
# Usage: ./bundle-out.sh <branch>
# Environment: AGENT_NAME, AGENT_EMAIL and OWNER_CLONE, as for start.sh.
set -euo pipefail
cd "$(dirname "$0")"

# The bot identity and the owner's clone come from the environment.
: "${AGENT_NAME:?set the bot identity in the environment}" "${AGENT_EMAIL:?set the bot identity in the environment}"
: "${OWNER_CLONE:?set OWNER_CLONE to the clone to bundle from}"
# The desk's project; drive.sh runs each attempt as its own.
export COMPOSE_PROJECT_NAME=agent-box
branch=${1:?usage: bundle-out.sh <branch>}

export AGENT_NAME AGENT_EMAIL
mkdir -p bundles
docker compose run --rm --no-deps -T agent git bundle create - "$branch" >bundles/out.bundle
git -C "$OWNER_CLONE" -c core.hooksPath=/dev/null -c core.fsmonitor=false \
  fetch "$PWD/bundles/out.bundle" "+$branch:agent/$branch"
