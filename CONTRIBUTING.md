# Contributing

agent-box is a personal project, shaped for one owner's setup and shared
as-is. It has one maintainer with limited time, so the rules for pull
requests are strict.

- **Issues are welcome.** Bug reports, questions and ideas all start as an
  issue.
- **Open an issue before a pull request.** A pull request needs an issue
  where the maintainer has agreed to the change. Typo and broken-link fixes
  are the only exception.
- **A person must have read and understood every line.** Using AI tools to
  write a change is fine. Opening a pull request you haven't reviewed
  yourself is not: you should be able to explain any line in it, and
  you're expected to answer review comments yourself.
- **Unsolicited or unreviewed pull requests are closed without review.**
  Accounts that keep opening them are blocked.

Security problems: see [SECURITY.md](SECURITY.md), not an issue.

Changes to `compose.yaml`, `proxy/`, `entrypoint.sh` or
`managed-settings.json` change what an untrusted agent can do. Say in the
pull request whether the change widens or narrows that, and why. A new
host in `proxy/allowlist` needs a stated reason.

Before opening a pull request:

- `shellcheck start.sh bundle-out.sh entrypoint.sh auth-sync.sh drive.sh`
- `docker compose build`

Commits follow [Conventional Commits](https://www.conventionalcommits.org).
More rules for people and agents are in [AGENTS.md](AGENTS.md).
