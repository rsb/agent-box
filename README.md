# agent-box

The container coding agents run in for away mode. It holds no credentials
and has no route to the internet except a proxy sidecar with a host
allowlist. Code goes in and out as git bundles; `../agent-driver` starts
the box, runs the agent, and does all GitHub actions on the host.

## Layout

- `Dockerfile`: the image. Node 24, pnpm, Claude Code and Codex pinned,
  sqld, Playwright Chromium. Shaped for one Node project; others need their own (see Planned).
- `compose.yaml`: `agent` (Claude Code) and `codex` share one shape:
  user 1000, read-only root, tmpfs, no capabilities, the repo on a named
  volume. Each gets only its own sign-in (see Sign-in) and sits on its own
  internal network with its own proxy (`proxy`, `proxy-codex`), the only
  services with egress. The agent's home is tmpfs, new each run. Claude
  signs in with a token from an env file and keeps nothing; Codex's auth
  file lasts (`codex-auth-sync`). No project name: the desk runs as
  `agent-box`, each attempt as its own project. Codex's auth volumes are
  external with fixed names (`agent-box-codex-auth{,-out}`), so every
  project shares one Codex sign-in. The box subnets come from
  `BOX_SUBNET` and `BOX_CODEX_SUBNET` (default `10.77.0.0/24`,
  `10.77.1.0/24`).
- `compose.driver.yaml`: what a driver launch puts on top. No terminal,
  and the agent's mounts are the attempt's and three skills only (see
  below).
- `proxy/`: tinyproxy, `CONNECT` on 443 only, default deny,
  `allowlist` (Claude Code) and `allowlist-codex` are the whole policy.
- `entrypoint.sh`: clones `/bundles/in.bundle` onto the volume on first
  start, drops `origin`, sets `core.hooksPath`. Links the skills under
  `/skills`, if mounted, into the agent's skills directory. Refuses to
  start `claude` without `CLAUDE_CODE_OAUTH_TOKEN`. For Codex, copies the
  auth file from `/auth` (read-only) into the empty home, runs the agent,
  and copies the auth file to `/auth-out` if the run changed it.
- `auth-sync.sh`: Codex only. Run by `start.sh` after the agent exits,
  with no network. Writes `/auth-out`'s auth file back to the auth volume only if it is a
  JSON object in a regular file, then empties `/auth-out`.
- `managed-settings.json`: Claude Code permission mode and denied tools
  inside the box, baked into the image at `/etc/claude-code/`.
- `codex/`: Codex's managed config and requirements, baked into
  `/etc/codex`. Codex's own sandbox is off; the container is the sandbox.
- `start.sh`, `bundle-out.sh`: the desk launcher and the way out. Both
  take the bot identity from `AGENT_NAME` and `AGENT_EMAIL` and the
  owner's clone from `OWNER_CLONE`, in the environment, and the sign-in
  file from `AGENT_BOX_CLAUDE_ENV` (see Sign-in).
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
the agent's code. A stop signal stops the container (30 s grace). On exit
it takes the project down, images and volumes with it. It refuses to
start unless the sign-in file is a regular file of mode 600.

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

## Sign-in

Claude signs in with `CLAUDE_CODE_OAUTH_TOKEN`, the long-lived token
`claude setup-token` prints (one year, model requests only). See
Anthropic's [authentication docs](https://code.claude.com/docs/en/authentication).
Mint it once on the desk and keep it in an env file outside every repo:

```sh
claude setup-token     # prints the token; it is not saved
install -d -m 700 ~/.config/rsb/agent-box
install -m 600 /dev/null ~/.config/rsb/agent-box/claude.env
$EDITOR ~/.config/rsb/agent-box/claude.env   # CLAUDE_CODE_OAUTH_TOKEN=...
```

Both compose files give the `agent` service that file as its `env_file`.
`AGENT_BOX_CLAUDE_ENV` overrides the path, for `start.sh`, `drive.sh` and
the driver alike. The token reaches the box as an environment variable
only: no auth volume, no file in the home, and nothing written back, so
attempts running side by side share no state to race on.

The token is tied to the subscription of whoever ran `claude setup-token`.
Do not share it, commit it, or put it in any other box; rotate it by
running `claude setup-token` again and replacing the file.

Codex is unchanged: it still copies `auth.json` in from its auth volume
and writes a refresh back through `codex-auth-sync`. Create its volumes
once, before the first run, and sign in from the desk
(`./start.sh --codex <branch>`, then `codex login`):

```sh
for v in codex-auth codex-auth-out; do docker volume create agent-box-$v; done
```

## Planned

Per-repo images under `images/<repo>/`, and the driver as the only
launcher. See `../agent-driver/docs/handoff.md`.
