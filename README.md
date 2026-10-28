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
  its auth file lasts (`agent-auth-sync`, `codex-auth-sync`). No project
  name: the desk runs as `agent-box`, each attempt as its own project.
  The auth volumes are external with fixed names
  (`agent-box-{claude,codex}-auth{,-out}`), so every project shares one
  sign-in. The box subnets come from `BOX_SUBNET` and `BOX_CODEX_SUBNET`
  (default `10.77.0.0/24`, `10.77.1.0/24`).
- `compose.driver.yaml`: what a driver launch puts on top. No terminal,
  and the agent's mounts are the attempt's and three skills only (see
  below).
- `proxy/`: tinyproxy, `CONNECT` on 443 only, default deny,
  `allowlist` (Claude Code) and `allowlist-codex` are the whole policy.
- `entrypoint.sh`: clones `/bundles/in.bundle` onto the volume on first
  start, drops `origin`, sets `core.hooksPath`. Links the skills under
  `/skills`, if mounted, into the agent's skills directory. Copies the auth file from
  `/auth` (read-only) into the empty home, runs the agent, and copies the
  auth file to `/auth-out` if the run changed it.
- `auth-sync.sh`: run by `start.sh` after the agent exits, with no network.
  Writes `/auth-out`'s auth file back to the auth volume only if it is a
  JSON object in a regular file, then empties `/auth-out`.
- `managed-settings.json`: Claude Code permission mode and denied tools
  inside the box, baked into the image at `/etc/claude-code/`.
- `codex/`: Codex's managed config and requirements, baked into
  `/etc/codex`. Codex's own sandbox is off; the container is the sandbox.
- `start.sh`, `bundle-out.sh`: the desk launcher and the way out. Both
  take the bot identity from `AGENT_NAME` and `AGENT_EMAIL` and the
  owner's clone from `OWNER_CLONE`, in the environment.
- `drive.sh`: the driver's entry. One attempt, non-interactive.

## Run by hand

```sh
export AGENT_NAME=... AGENT_EMAIL=... OWNER_CLONE=~/code/...
./start.sh [--fresh] <branch>   # bundle in, start claude on <branch>
./start.sh --codex <branch>     # the same with codex
./bundle-out.sh <branch>        # fetch the box's branch as agent/<branch>
docker compose -p agent-box logs proxy proxy-codex | grep CONNECT   # what the box reached
```

Commits inside carry the bot identity through `GIT_AUTHOR_*` and
`GIT_COMMITTER_*`. Nothing in the box can push.

## Run for the driver

```sh
AGENT_NAME=... AGENT_EMAIL=... ./drive.sh gauge-run-<loop>-<attempt> <attempt-dir> '<prompt>' [claude option...]
```

Runs `claude -p '<prompt>' [option...]` with no terminal, prints the
agent's stdout on stdout and everything else on stderr, and exits with
the agent's code. A stop signal stops the container (30 s grace), so the
entrypoint still saves a refreshed sign-in. On exit it writes the
sign-in back and takes the project down, images and volumes with it.

The agent's mounts, and no other host path:

| Host | In the box |
| --- | --- |
| `<attempt-dir>/repo` | `/workspace` (read-write) |
| `<attempt-dir>/run/brief.json` | `/run/brief.json` (read-only) |
| `<attempt-dir>/run/outbox` | `/run/outbox` (read-write) |
| `$RSB_SKILLS/skills/engineering/{implement,tdd,rsb-code-review}` | `/skills/<name>` (read-only), linked into `~/.claude/skills` |

`RSB_SKILLS` defaults to `~/code/software/rsb/factory/rsb-skills`. Every
path must exist; none is created. The brief must be `brief/v1` with
`outbox_path` `/run/outbox`. Each project picks two free /24s in
`10.77.0.0/16` for its networks, so attempts and the desk can run at
once. Like `start.sh`, it refuses to run from a checkout off `main` or
with changes.

## Auth volumes

Create them once, before the first run:

```sh
for v in claude-auth claude-auth-out codex-auth codex-auth-out; do docker volume create agent-box-$v; done
```

Sign in from the desk (`./start.sh <branch>`, then `/login` or
`codex login`); every project uses that sign-in.

## Planned

Per-repo images under `images/<repo>/`, and the driver as the only
launcher. See `../agent-driver/docs/handoff.md`.
