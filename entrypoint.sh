#!/bin/sh
set -eu
if [ ! -d /workspace/.git ]; then
  : "${BRANCH:?no repo on the volume; start the box with ./start.sh <branch>}"
  git clone --branch "$BRANCH" /bundles/in.bundle /workspace
  git -C /workspace remote remove origin
  git -C /workspace config core.hooksPath .githooks
else
  # Keep the existing workspace, but say so: the bundle just made is not
  # what the agent will see. Warnings only; a failed lookup changes nothing.
  ws=$(git -C /workspace rev-parse HEAD 2>/dev/null) || ws=
  bundle=
  if [ -n "${BRANCH:-}" ] \
    && heads=$(git bundle list-heads /bundles/in.bundle "refs/heads/$BRANCH" 2>/dev/null); then
    bundle=${heads%% *}
  fi
  echo "agent-entrypoint: keeping the existing /workspace at $(printf %.7s "${ws:-unknown}"), not cloning the bundle; ./start.sh --fresh replaces it" >&2
  if [ -n "$bundle" ] && [ "$bundle" != "$ws" ]; then
    echo "agent-entrypoint: workspace HEAD $(printf %.7s "${ws:-unknown}") differs from the bundle's $BRANCH $(printf %.7s "$bundle"); bundle out any work before --fresh" >&2
  fi
fi
exec "$@"
