#!/bin/sh
set -eu
if [ ! -d /workspace/.git ]; then
  : "${BRANCH:?no repo on the volume; start the box with ./start.sh <branch>}"
  git clone --branch "$BRANCH" /bundles/in.bundle /workspace
  git -C /workspace remote remove origin
  git -C /workspace config core.hooksPath .githooks
elif [ -e /bundles/in.bundle ]; then
  # Keep the existing workspace, but say so: the bundle just made is not
  # what the agent will see. Warnings only; a failed lookup changes nothing.
  # A driver launch mounts its clone at /workspace and no bundle.
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

# D8: the agent's home is on the /home/node tmpfs, so nothing the run writes
# there (a global AGENTS.md or CLAUDE.md, a config, a skill) reaches a later
# run. Only the sign-in lasts: the auth file comes in from /auth (read-only)
# and, if the run changed it, goes out to /auth-out. <service>-auth-sync
# writes it back after the container exits. AGENT_AUTH is the file's path in
# the home; a service without it just runs the command.
if [ -z "${AGENT_AUTH:-}" ]; then
  exec "$@"
fi
home=${AGENT_AUTH%/*}
name=${AGENT_AUTH##*/}
mkdir -p "$home"
chmod 700 "$home"
if [ -f "/auth/$name" ] && [ ! -L "/auth/$name" ]; then
  cp "/auth/$name" "$AGENT_AUTH"
  chmod 600 "$AGENT_AUTH"
fi
# A driver launch mounts the skills it allows read-only under /skills (not
# in the home, where the mount points would be root's). Link them in.
if [ "$name" = .credentials.json ] && [ -d /skills ]; then
  mkdir -p "$home/skills"
  for d in /skills/*/; do
    [ -d "$d" ] || continue
    d=${d%/}
    ln -sfn "$d" "$home/skills/${d##*/}"
  done
fi
# What a kept home used to remember, fixed: first-run screens done and
# /workspace trusted. Written only if absent.
case $name in
  .credentials.json)
    f=$home/.claude.json
    [ -e "$f" ] || printf '%s\n' '{"hasCompletedOnboarding":true,"projects":{"/workspace":{"hasTrustDialogAccepted":true}}}' >"$f"
    ;;
  auth.json)
    f=$home/config.toml
    [ -e "$f" ] || printf '[projects."/workspace"]\ntrust_level = "trusted"\n' >"$f"
    ;;
esac

# Run the agent as a child, not exec, so its auth file can be copied out
# after it exits. Stop signals are passed on, so `docker stop` still lets
# it exit and the copy happen; SIGKILL loses a refresh made in the run.
# Background jobs get /dev/null as stdin, so hand the terminal over on fd 3.
exec 3<&0
"$@" <&3 3<&- &
pid=$!
exec 3<&-
trap 'kill -TERM "$pid" 2>/dev/null || :' TERM HUP
trap 'kill -INT "$pid" 2>/dev/null || :' INT
while :; do
  wait "$pid" && rc=0 || rc=$?
  kill -0 "$pid" 2>/dev/null || break
done
if [ -f "$AGENT_AUTH" ] && [ ! -L "$AGENT_AUTH" ] && ! cmp -s "$AGENT_AUTH" "/auth/$name"; then
  cp "$AGENT_AUTH" "/auth-out/.$name.tmp" && mv -f "/auth-out/.$name.tmp" "/auth-out/$name" \
    || echo "agent-entrypoint: could not copy $name to /auth-out; a sign-in or refresh from this run is lost" >&2
fi
exit "$rc"
