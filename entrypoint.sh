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
# run. Claude keeps no sign-in there: it reads CLAUDE_CODE_OAUTH_TOKEN (from
# `claude setup-token`) from the environment, and nothing goes back out.
# Codex's auth.json comes in from /auth (read-only) and, if the run changed
# it, goes out to /auth-out; codex-auth-sync writes it back after the
# container exits. AGENT_AUTH is that file's path in the home.
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  if [ "${1:-}" = claude ] && [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    echo "agent-entrypoint: no CLAUDE_CODE_OAUTH_TOKEN; put it in the env file compose.yaml names (see README.md, Sign-in)" >&2
    exit 1
  fi
  home=$CLAUDE_CONFIG_DIR
  mkdir -p "$home"
  chmod 700 "$home"
  # A driver launch mounts the skills it allows read-only under /skills (not
  # in the home, where the mount points would be root's). Link them in.
  if [ -d /skills ]; then
    mkdir -p "$home/skills"
    for d in /skills/*/; do
      [ -d "$d" ] || continue
      d=${d%/}
      ln -sfn "$d" "$home/skills/${d##*/}"
    done
  fi
  # What a kept home used to remember, fixed: first-run screens done and
  # /workspace trusted. Written only if absent.
  f=$home/.claude.json
  [ -e "$f" ] || printf '%s\n' '{"hasCompletedOnboarding":true,"projects":{"/workspace":{"hasTrustDialogAccepted":true}}}' >"$f"
elif [ -n "${AGENT_AUTH:-}" ]; then
  home=${AGENT_AUTH%/*}
  name=${AGENT_AUTH##*/}
  mkdir -p "$home"
  chmod 700 "$home"
  if [ -f "/auth/$name" ] && [ ! -L "/auth/$name" ]; then
    cp "/auth/$name" "$AGENT_AUTH"
    chmod 600 "$AGENT_AUTH"
  fi
  f=$home/config.toml
  [ -e "$f" ] || printf '[projects."/workspace"]\ntrust_level = "trusted"\n' >"$f"
else
  exec "$@"
fi

# Run the agent as a child, not exec, so stop signals are passed on and
# Codex's auth file can be copied out after it exits: `docker stop` still
# lets it exit and the copy happen; SIGKILL loses a refresh made in the run.
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
if [ -n "${AGENT_AUTH:-}" ] && [ -f "$AGENT_AUTH" ] && [ ! -L "$AGENT_AUTH" ] \
  && ! cmp -s "$AGENT_AUTH" "/auth/$name"; then
  cp "$AGENT_AUTH" "/auth-out/.$name.tmp" && mv -f "/auth-out/.$name.tmp" "/auth-out/$name" \
    || echo "agent-entrypoint: could not copy $name to /auth-out; a sign-in or refresh from this run is lost" >&2
fi
exit "$rc"
