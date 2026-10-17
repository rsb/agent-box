#!/usr/bin/env bash
# Copy a branch out of the box and fetch it into the owner's clone as
# agent/<branch>, with hooks and fsmonitor off. Nothing is pushed.
# Usage: ./bundle-out.sh <branch>
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=/dev/null
. "${GM_SLS_AGENT_ENV:-$HOME/.config/gm-sls-agent/app.env}"
: "${AGENT_NAME:?set in app.env}" "${AGENT_EMAIL:?set in app.env}" "${OWNER_CLONE:?set in app.env}"
branch=${1:?usage: bundle-out.sh <branch>}

export AGENT_NAME AGENT_EMAIL
mkdir -p bundles
docker compose run --rm --no-deps -T agent git bundle create - "$branch" >bundles/out.bundle
git -C "$OWNER_CLONE" -c core.hooksPath=/dev/null -c core.fsmonitor=false \
  fetch "$PWD/bundles/out.bundle" "+$branch:agent/$branch"
