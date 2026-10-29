# Security policy

agent-box is a security boundary. It is meant to keep an unattended coding
agent to its workspace, one credential and a short list of hosts. A way
around that is a vulnerability.

## Reporting

Report privately through GitHub: on this repository's Security tab, choose
"Report a vulnerability". Please don't open a public issue.

Include what you ran, what the agent could reach or keep that it shouldn't
have, the agent-box commit, and your Docker Engine and Compose versions.

This is a one-person project maintained in spare time. Reports are read and
answered as soon as practical; there is no bounty. Only the latest `main`
is supported.

## In scope

- Reaching a host that isn't in `proxy/allowlist` or `proxy/allowlist-codex`,
  or any route out that bypasses the proxy.
- Escaping the container, or writing to the host outside what the README's
  "Security model" lists.
- Reaching a credential the box shouldn't hand to that agent (for example
  Claude reading Codex's `auth.json`, or the reverse).
- State that carries from one run into a later run beyond what the README
  describes.
- A bundle from the box that runs code on the host when `bundle-out.sh`
  fetches it.
- `start.sh` or `drive.sh` running from a changed or off-`main` checkout.

## Out of scope

- Everything under "Limits and non-goals" in the README, for example
  sending data to an allowlisted host, or reading the agent's own token
  from inside the box.
- Flaws in Claude Code, Codex, Docker, tinyproxy, Node or Debian
  themselves: report those upstream. Do report it here if agent-box's
  configuration makes one worse.
