# AGENTS.md

Read `README.md` first. Standards shared by rsb projects live in `../rules`;
read its `README.md`.

Commits follow Conventional Commits. Never add `Co-Authored-By` or any other AI
attribution to commits or pull requests. Outside ticket work, do not commit or
push unless asked. Dates and times are America/Los_Angeles.

Everything here is a security boundary. Any change to `compose.yaml`,
`proxy/`, `entrypoint.sh` or `managed-settings.json` widens or narrows what an
untrusted agent can do: say which in the commit message. Never add a host to
`proxy/allowlist` without stating what needs it. Never mount a credential,
socket or host path into `agent`.

Pins. `Dockerfile` pins every tool by version and `sqld` by checksum. Bump
pins in their own commit.

Checks:

- Lint: `shellcheck start.sh bundle-out.sh entrypoint.sh auth-sync.sh`
- Build: `docker compose build`
- Smoke: `./start.sh --fresh <branch> true` exits 0 and the proxy log shows
  only allowlisted hosts.
