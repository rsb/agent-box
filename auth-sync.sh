#!/bin/sh
# Write a run's auth file back to its auth volume (D8). <service>-auth-sync
# runs this with no network after the agent's container has exited.
# /auth-out was writable by the agent, so only one name is read there, and
# only a regular file that parses as a JSON object is kept. Anything else is
# reported and the stored file stands. /auth-out is emptied either way.
# Usage: auth-sync <auth file name>
set -eu
name=${1:?usage: auth-sync <auth file name>}
out=/auth-out/$name
status=0
if [ ! -e "$out" ] && [ ! -L "$out" ]; then
  echo "auth-sync: the run left no new $name; the stored one stands" >&2
elif [ -L "$out" ] || [ ! -f "$out" ] || [ "$(wc -c <"$out")" -gt 1048576 ] \
  || ! jq -e 'type == "object"' "$out" >/dev/null 2>&1; then
  echo "auth-sync: the run's $name is not a JSON object in a regular file; kept the stored one" >&2
  status=1
else
  cp "$out" "/auth/.$name.tmp"
  chmod 600 "/auth/.$name.tmp"
  mv -f "/auth/.$name.tmp" "/auth/$name"
  echo "auth-sync: wrote the run's $name back" >&2
fi
find /auth-out -mindepth 1 -delete || {
  echo "auth-sync: could not empty /auth-out" >&2
  status=1
}
exit "$status"
