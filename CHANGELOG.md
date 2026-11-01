# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.3.1] - 2026-11-01

### Changed

- **The Steam check's probe image is pinned by digest.** `tools/steam-uptodate.sh` asks A2S and Steam from a python container in the server's network namespace; 1.3.0 named it by tag, `python:3.13-alpine`, so whoever moved that tag decided what ran there. It is now `python:3.13-alpine@sha256:7984cf56…`, and `STEAM_UPTODATE_PROBE_IMAGE` still overrides it.
## [1.3.0] - 2026-11-01

### Added

- **`tools/steam-uptodate.sh` and a systemd timer: Steam is asked every fifteen minutes whether the server is current, and an empty server that is not gets restarted.** This image updates the game on every start, and nothing decided when a start was due. The script reads the version the server reports over A2S and asks Steam's `UpToDateCheck`, the question that, on the machine this template comes from, nobody asked while Team Fortress 2 sat out of date for days with every check green. Behind with people on, it says so once and waits. Behind and empty, it restarts the server and asks Steam again until Steam calls the new version current: the proof is Steam's answer, never the restart. At most three restarts in 24 hours, then it says so once and fails every run. One update per host per pass, by a lock and a stamp shared with the other Source templates: two 73 GB verifications back to back took a CPU there to 81 °C. A silent server or Steam decides nothing, for up to six hours. Something new also goes to `STEAM_UPTODATE_NOTIFY` when it is set. The timer is on UTC with an `OnUnitActiveSec` net (`tests/timers.sh`), the script is one brace group read whole before it runs (`tests/read-whole.sh`), and `tests/steam-uptodate.sh` drives every branch against stubbed answers, with four plants, one rule taken out each.
## [1.2.3] - 2026-10-27

### Fixed

- **`scripts/botguard.sh` is read whole before it runs.** bash reads a script as it executes it and, after each command, reads on from the same byte offset in whatever the file holds by then. Cron starts the guard every minute; on the server this template comes from, a timer started a script while its file was being edited in place, and the run died on a syntax error. The guard's body is now one brace group, parsed in full before its first line runs, ending in `exit`. `tests/read-whole.sh` checks its shape and rewrites its file under a running copy: wrapped, it finishes as it started; unwrapped, it runs the new text. CI now also runs ShellCheck on the guard and on `update.sh`.

## [1.2.2] - 2026-10-25

### Added

- **The image's user is declared and checked.** Every file in `cs2-classic-server-data` belongs to the user the image runs as, and `joedwards32/cs2` moved it twice in eight days in September 2026, 1000 to 999 and back; on the machine this template comes from, the first move left the servers unable to write their logs for a day and a half while every health check stayed green. The compose file declares `x-image-user: "1000:1000"`, and `tests/image-user.sh`, run in CI, fails when the pinned image runs as anyone else, so a pin refresh that moves the user stops before it ships as a patch. Nothing changes for a running server: every release so far, this one included, pins an image that runs as 1000:1000.

## [1.2.1] - 2026-10-24

### Changed

- **`joedwards32/cs2:5.0.0` moved to `joedwards32/cs2:5.0.1`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.
- **The freshness check has its own workflow, Pin Freshness.** It ran inside Deployment Verification, whose badge is the one at the top of this README. Across the fleet, nine red runs in ten were a pin one version behind - which the fleet's triage moves within the day - and a reader cannot tell that from a stack that does not boot. The badge now says whether the stack boots. The job itself is unchanged.

### Fixed

- **`update.sh` no longer stops without a word when a release adds a variable and no compose file requires one.** The search for `${VAR:?}` came back empty, and under `pipefail` that empty result ended the script with status 1 right after it listed the new variables.
- **`update.sh` stops on a `.env` it cannot read, before the checkout.** It used to fall through: every new required variable read as "not set", or, with none, the tree moved to the new tag and `docker compose up` failed on the permission. Now it names the file, its owner and mode, and changes nothing.
- **Pin Freshness names the variable when the pin is ahead of the latest joedwards32/CS2 release.** The line read `${var}`, which is set only in the step before, so it began with a blank. It now says `CS2_CLASSIC_SERVER_IMAGE_TAG`. Only the message changed; the check passes and fails as before.

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

[Unreleased]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/compare/v1.3.1...HEAD
[1.3.1]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/compare/v1.2.3...v1.3.0
[1.2.3]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/heyvaldemar/cs2-classic-server-docker-compose/releases/tag/v1.0.0
