#!/usr/bin/env bash
# Bundle a branch out of the owner's clone and start the box on it.
# No token: the box reaches nothing but the proxy, and commits carry
# the bot identity through the git environment variables.
# Usage: ./start.sh [--fresh] [--codex] <branch> [command...]
#   --fresh removes the workspace volume so the box clones the new bundle.
#   --codex runs the codex service (default command codex) instead of
#   agent (default command claude).
# Environment: AGENT_NAME, AGENT_EMAIL (the bot identity for commits) and
# OWNER_CLONE (the clone the branch is bundled from).
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

# The bot identity and the owner's clone come from the environment.
: "${AGENT_NAME:?set the bot identity in the environment}" "${AGENT_EMAIL:?set the bot identity in the environment}"
: "${OWNER_CLONE:?set OWNER_CLONE to the clone to bundle from}"
# The desk's project; drive.sh runs each attempt as its own.
export COMPOSE_PROJECT_NAME=agent-box

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

# Name the source repo before anything runs, so a wrong OWNER_CLONE shows.
if ! head=$(git -C "$OWNER_CLONE" rev-parse --short HEAD); then
  echo "start.sh: OWNER_CLONE=$OWNER_CLONE is not a git clone" >&2
  exit 1
fi
if ! tip=$(git -C "$OWNER_CLONE" rev-parse --short --verify --quiet "$branch^{commit}"); then
  echo "start.sh: no branch $branch in $OWNER_CLONE" >&2
  exit 1
fi
echo "Starting $service as $AGENT_NAME on $branch ($tip) from $OWNER_CLONE (HEAD $head)." >&2

if [ -n "$fresh" ]; then
  docker volume rm -f agent-box_workspace >/dev/null
fi

mkdir -p bundles
git -C "$OWNER_CLONE" bundle create "$PWD/bundles/in.bundle" "$branch"

export BRANCH="$branch" AGENT_NAME AGENT_EMAIL

# The home is per run (D8); only the auth file lasts. Write back first what
# an interrupted run left in auth-out, then run, then write back this run's.
sync_auth() {
  docker compose run --rm --no-deps -T "$service-auth-sync" </dev/null \
    || echo "start.sh: $service-auth-sync failed; the stored sign-in was kept" >&2
}
docker compose build "$service" "$service-auth-sync" >&2
sync_auth
rc=0
docker compose run --rm "$service" "$@" || rc=$?
sync_auth
exit "$rc"
