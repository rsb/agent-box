#!/bin/sh
set -eu
if [ ! -d /workspace/.git ]; then
  : "${BRANCH:?no repo on the volume; start the box with ./start.sh <branch>}"
  git clone --branch "$BRANCH" /bundles/in.bundle /workspace
  git -C /workspace remote remove origin
  git -C /workspace config core.hooksPath .githooks
fi
exec "$@"
