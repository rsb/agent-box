# agent-box

The container coding agents run in for away mode. It holds no credentials
and has no route to the internet except a proxy sidecar with a host
allowlist. Code goes in and out as git bundles; `../agent-driver` starts
the box, runs the agent, and does all GitHub actions on the host.

## Layout

- `Dockerfile`: the image. Node 24, pnpm, Claude Code and Codex pinned,
  sqld, Playwright Chromium. Shaped for gm-serverless; lumen needs its own.
- `compose.yaml`: `agent` (Claude Code) and `codex` share one shape:
  user 1000, read-only root, tmpfs, no capabilities, the repo on a named
  volume. Each mounts only its own auth volumes and sits on its own
  internal network with its own proxy (`proxy`, `proxy-codex`), the only
  services with egress. The agent's home is tmpfs, new each run; only
  its auth file lasts (`agent-auth-sync`, `codex-auth-sync`).
- `proxy/`: tinyproxy, `CONNECT` on 443 only, default deny,
  `allowlist` (Claude Code) and `allowlist-codex` are the whole policy.
- `entrypoint.sh`: clones `/bundles/in.bundle` onto the volume on first
  start, drops `origin`, sets `core.hooksPath`. Copies the auth file from
  `/auth` (read-only) into the empty home, runs the agent, and copies the
  auth file to `/auth-out` if the run changed it.
- `auth-sync.sh`: run by `start.sh` after the agent exits, with no network.
  Writes `/auth-out`'s auth file back to the auth volume only if it is a
  JSON object in a regular file, then empties `/auth-out`.
- `managed-settings.json`: Claude Code permission mode and denied tools
  inside the box.
- `codex/`: Codex's managed config and requirements, baked into
  `/etc/codex`. Codex's own sandbox is off; the container is the sandbox.
- `start.sh`, `bundle-out.sh`: the manual launcher and the way out, until
  the driver replaces them. Both read `~/.config/gm-sls-agent/app.env` for
  the bot identity and the owner's clone path.

## Run by hand

```sh
./start.sh [--fresh] <branch>   # bundle in, start claude on <branch>
./start.sh --codex <branch>     # the same with codex
./bundle-out.sh <branch>        # fetch the box's branch as agent/<branch>
docker compose logs proxy proxy-codex | grep CONNECT   # what the box reached
```

Commits inside carry the bot identity through `GIT_AUTHOR_*` and
`GIT_COMMITTER_*`. Nothing in the box can push.

## Planned

Per-repo images under `images/<repo>/`, a compose project per run so two
tickets can run at once, and the driver as the only launcher. See
`../agent-driver/docs/handoff.md`.
