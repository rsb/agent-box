#!/usr/bin/env bash
# Bundle a branch out of the owner's clone and start the box on it.
# No token: the box reaches nothing but the proxy, and commits carry
# the bot identity through the git environment variables.
# Usage: ./start.sh [--fresh] <branch> [command...]   (default command is claude)
#   --fresh removes the workspace volume so the box clones the new bundle.
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=/dev/null
. "${GM_SLS_AGENT_ENV:-$HOME/.config/gm-sls-agent/app.env}"
: "${AGENT_NAME:?set in app.env}" "${AGENT_EMAIL:?set in app.env}" "${OWNER_CLONE:?set in app.env}"

fresh=
if [ "${1:-}" = --fresh ]; then
  fresh=1
  shift
fi
branch=${1:?usage: start.sh [--fresh] <branch> [command...]}
shift

if [ -n "$fresh" ]; then
  docker volume rm -f gm-sls-agent_workspace >/dev/null
fi

mkdir -p bundles
git -C "$OWNER_CLONE" bundle create "$PWD/bundles/in.bundle" "$branch"

export BRANCH="$branch" AGENT_NAME AGENT_EMAIL
echo "Starting as $AGENT_NAME on $branch." >&2
exec docker compose run --rm agent "$@"
