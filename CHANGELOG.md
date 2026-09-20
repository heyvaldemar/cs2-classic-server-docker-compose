# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.2.0] - 2026-09-20

### Added

- **`CS2_CLASSIC_SERVER_DELTATICKS_ENFORCE` and `CS2_CLASSIC_SERVER_TV_RELAYVOICE`.** Upstream added both in 5.0.0 with defaults baked into the image, so the server behaves the same whether or not they are set. They are wired through and documented because a knob nobody can find is a knob that does not exist. The second one decides whether GOTV relays player voice, which is a privacy question on a public server rather than a tuning one.

### Changed

- **`joedwards32/cs2:4.0.1` moved to `joedwards32/cs2:5.0.0`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.
- **The container's base runtime changed, and nothing in this file had to.** Upstream marked 5.0.0 breaking for moving off Steam Runtime "sniper" onto steamrt4, and for replacing the RCON forwarder `simpleproxy` with `socat`. Both live inside the image: the ports, the variables and the compose interface are unchanged, and the `socat` form forks per connection where the old one did not. The review was right to stop on that marker: the release notes carry the title and nothing else, so what `!` meant could not be read from them. It is readable from the change itself — upstream PR 218 is a directory rename plus two lines of Dockerfile, and that is what settled it.

## [1.1.0] - 2026-09-07

### Added

- **`update.sh`: move between release tags on purpose.** It updates to the latest release (a combination this repository's CI has booted and smoke-tested), refuses to cross a major version unattended, refuses to run over local changes, and names any new required variable before anything has moved. `--dry-run` says what would happen.

ired.** A Game Server Login Token drives one server;
  shared with another CS2 server, both drop off the list. Workshop downloads
  also require it, and without one the collection never arrives and nothing
  says why.
- **A bot guard for what workshop mode refuses.** Parts of
  `gamemode_casual_server.cfg` come back with `DISALLOWED WORKSHOP CONVAR` at
  the next map change, `bot_quota` among them. `scripts/botguard.sh` reads the
  quota from the config, asks the server over A2S, and kicks bots over rcon
  when the config says none. It talks to the server from inside its own
  network namespace and takes the password on stdin.
- **A curated rotation over the collection**, with the note that a name not
  in the collection is skipped.
- **The exact-match health check, the external volume and the port rule**
  inherited from the plain template, and a **6 GB ceiling with its reason**:
  the 14 GB peak once recorded was SteamCMD's page cache, not the server.
- **A one-line seed from a plain CS2 volume**, so the second 60 GB download
  never happens on a host that already has one.
- **Deployment Verification CI**: shell and workflow linting, a Trivy scan of
  the pinned image, a daily freshness check on the pin against the registry
  and the latest image release, and the health-check suite. It deliberately
  does not boot the game.

[Unreleased]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/releases/tag/v1.0.0
