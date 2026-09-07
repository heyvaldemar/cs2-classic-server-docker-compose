# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.0] - 2026-09-07

### Added

- **A CS2 server playing a Steam Workshop collection**, image pinned by
  digest as an interpolation default, so `git pull` delivers the version this
  repository has tested and `.env` overrides survive it. The plain
  cs2-server-docker-compose template with a collection in front of it.
- **Its own token, required.** A Game Server Login Token drives one server;
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

[Unreleased]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/releases/tag/v1.0.0
