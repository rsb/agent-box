#!/usr/bin/env bash
# Bundle a branch out of the owner's clone and start the box on it.
# No token: the box reaches nothing but the proxy, and commits carry
# the bot identity through the git environment variables.
# Usage: ./start.sh [--fresh] [--codex] <branch> [command...]
#   --fresh removes the workspace volume so the box clones the new bundle.
#   --codex runs the codex service (default command codex) instead of
#   agent (default command claude).
set -euo pipefail
cd "$(dirname "$0")"

# Refuse to run from a box whose files differ from the committed main.
# A session in another repo cannot edit here, but a changed file is the
# one thing that would silently widen what the agent can reach.
if [ "$(git symbolic-ref --short -q HEAD)" != main ]; then
  echo "start.sh: agent-box is not on main" >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "start.sh: agent-box has uncommitted changes; commit or discard them first" >&2
  git status --short >&2
  exit 1
fi

# shellcheck source=/dev/null
. "${GM_SLS_AGENT_ENV:-$HOME/.config/gm-sls-agent/app.env}"
: "${AGENT_NAME:?set in app.env}" "${AGENT_EMAIL:?set in app.env}" "${OWNER_CLONE:?set in app.env}"

fresh=
service=agent
while [ $# -gt 0 ]; do
  case $1 in
    --fresh) fresh=1 ;;
    --codex) service=codex ;;
    *) break ;;
  esac
  shift
done
branch=${1:?usage: start.sh [--fresh] [--codex] <branch> [command...]}
shift

if [ -n "$fresh" ]; then
  docker volume rm -f gm-sls-agent_workspace >/dev/null
fi

mkdir -p bundles
git -C "$OWNER_CLONE" bundle create "$PWD/bundles/in.bundle" "$branch"

export BRANCH="$branch" AGENT_NAME AGENT_EMAIL
echo "Starting $service as $AGENT_NAME on $branch." >&2
exec docker compose run --rm "$service" "$@"
