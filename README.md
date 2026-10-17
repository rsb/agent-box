# agent-box

The container coding agents run in for away mode. It holds no credentials
and has no route to the internet except a proxy sidecar with a host
allowlist. Code goes in and out as git bundles; `../agent-driver` starts
the box, runs the agent, and does all GitHub actions on the host.

## Layout

- `Dockerfile`: the image. Node 24, pnpm, Claude Code pinned, sqld,
  Playwright Chromium. Shaped for gm-serverless; lumen needs its own.
- `compose.yaml`: two services on an internal network. `proxy` is the only
  one with egress; `agent` is user 1000, read-only root, tmpfs, no
  capabilities, with the repo on a named volume.
- `proxy/`: tinyproxy, `CONNECT` on 443 only, default deny,
  `allowlist` is the whole policy.
- `entrypoint.sh`: clones `/bundles/in.bundle` onto the volume on first
  start, drops `origin`, sets `core.hooksPath`.
- `managed-settings.json`: Claude Code permission mode and denied tools
  inside the box.
- `start.sh`, `bundle-out.sh`: the manual launcher and the way out, until
  the driver replaces them. Both read `~/.config/gm-sls-agent/app.env` for
  the bot identity and the owner's clone path.

## Run by hand

```sh
./start.sh [--fresh] <branch>   # bundle in, start claude on <branch>
./bundle-out.sh <branch>        # fetch the box's branch as agent/<branch>
docker compose logs proxy | grep CONNECT   # what the box reached
```

Commits inside carry the bot identity through `GIT_AUTHOR_*` and
`GIT_COMMITTER_*`. Nothing in the box can push.

## Planned

Per-repo images under `images/<repo>/`, a compose project per run so two
tickets can run at once, and the driver as the only launcher. See
`../agent-driver/docs/handoff.md`.
