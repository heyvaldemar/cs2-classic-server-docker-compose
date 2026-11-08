# CS2 classic-maps server using Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/cs2-classic-server-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/cs2-classic-server-docker-compose/actions/workflows/deployment-verification.yml)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14895/badge)](https://www.bestpractices.dev/projects/14895)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Counter-Strike 2 server that plays a Steam Workshop collection of the classic maps — Assault, Militia, Dust, Aztec, Tuscan — pinned by digest, with the two things workshop mode does differently from a stock server written down.

```bash
git clone https://github.com/heyvaldemar/cs2-classic-server-docker-compose
cd cs2-classic-server-docker-compose
cp .env.example .env && $EDITOR .env          # a Steam token, an rcon password, a collection id
docker volume create cs2-classic-server-data  # see "the volume", below
docker compose -f cs2-classic-server-docker-compose.yml -p cs2-classic up -d
```

The first start downloads roughly 60 GB through SteamCMD and then the collection, so it is slow once and fast afterwards. Watch it:

```bash
docker compose -p cs2-classic logs -f cs2-classic-server
docker compose -p cs2-classic ps          # healthy once the game answers A2S_INFO
```

This is the [cs2-server-docker-compose](https://github.com/heyvaldemar/cs2-server-docker-compose) template with a workshop collection in front of it. Everything that template knows — the exact-match health check, the external volume, the port rule, the measured limits — applies here and is not repeated. What follows is what changes when the maps come from the Workshop.

## What this file knows that a fresh one does not

**The collection needs its own token, and the token needs to be its own.** A Game Server Login Token drives one server; share it with a plain CS2 server on the same host and both drop off the list. Workshop downloads also require the token — without one the collection never arrives and the server starts on whatever it has, with nothing in the log to say why the maps are missing.

**Workshop mode refuses part of the config, and says so quietly.** `gamemode_casual_server.cfg` is exec'd after the game's defaults and wins for most settings. In workshop mode, some of them come back with `DISALLOWED WORKSHOP CONVAR` in the log and the game's own value at the next map change; `bot_quota` is one of them, and so is `mapcyclefile`. A server configured for zero bots gets its bots back on the second map. `scripts/botguard.sh` is the answer: run from cron every minute, it reads the quota from the config, asks the server over A2S how many bots are on, and kicks them over rcon if the config says none. With any other quota it does nothing.

**The rotation names maps that have to be in the collection.** `mapcycle.txt` is the curated cycle; a name that is not in the collection is skipped. Switch by hand with `ds_workshop_changelevel <mapname>`; `ds_workshop_listmaps` shows what the collection brought.

**The memory ceiling is 6 GB, and the number it is not is 14.** Peak reads 14 GB on the machine this template comes from, and that is SteamCMD's page cache during a game update, not the server: resident stays under 1 GB. Cache is reclaimed under a limit, never OOM-killed, so the ceiling only has to clear the resident set with room for a workshop download.

**Seed the volume from a plain CS2 server if you have one.** Same game, same 60 GB. `docker run --rm -v cs2-server-data:/from:ro -v cs2-classic-server-data:/to alpine cp -a /from/. /to/` once, and the second download never happens. The volume is external for the same reason as in the plain template: `docker compose down -v` must not be able to delete 80 GB.

**The image's user is written down, and checked against the registry.** Every file in the volume belongs to the user the image runs as, and a volume does not follow when an image moves it. `joedwards32/cs2` moved it twice in eight days in September 2026, 1000 to 999 and back. On the machine this template comes from, the first move left both CS2 servers unable to write their logs for a day and a half, with the containers healthy, the games answering and Steam listing them. The compose file now declares `x-image-user: "1000:1000"`, and `tests/image-user.sh` fails when the pinned image runs as anyone else, so a pin refresh that moves the user cannot ship as a patch. Every release of this template so far has pinned an image that runs as 1000:1000. If one ever moves it, its notes carry the one command that re-owns the volume: `docker run --rm -v cs2-classic-server-data:/v alpine chown -R <uid>:<gid> /v`.

**Docker Engine 29.4.2 stops SteamCMD, and only that release does.** Its default seccomp profile answers the 32-bit `socketcall` system call with "not implemented" ([moby/moby#52506](https://github.com/moby/moby/issues/52506); for GitHub Actions, the ubuntu-26.04 runner image ships it: [actions/runner-images#14790](https://github.com/actions/runner-images/issues/14790), with the move to 29.7.2 in [actions/runner-images#15205](https://github.com/actions/runner-images/pull/15205)), and SteamCMD is a 32-bit program that makes every socket with it. With Steam and the network both up, it prints `!!! Fatal Error: Steamcmd needs to be online to update.` or `CreateBoundSocket: failed to create socket, error [no name available] (38)`, and the game is never installed or updated. Measured in [a CI run on GitHub's ubuntu-26.04 runner, which ships 29.4.2](https://github.com/heyvaldemar/tf2-server-docker-compose/blob/main/docs/evidence/docker-29.4.2-socketcall.md): SteamCMD failed in this template's pinned image there, and logged in once the daemon had the profile Docker 29.4.3 ships. 29.4.3 reverted the rule, and Ubuntu 26.04's own `docker.io` (27.5.1) never had it. Check with `docker version --format '{{.Server.Version}}'` and upgrade; until you can, point [`seccomp-profile` in `daemon.json`](https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file) at [moby/profiles seccomp v0.2.3](https://github.com/moby/profiles/blob/836ae4d37ef2ec995c77c99fc55f5b5f3af3a897/seccomp/default.json) and restart Docker.

## Administration

```bash
tools/rcon.sh status
tools/rcon.sh ds_workshop_listmaps
tools/rcon.sh ds_workshop_changelevel cs_assault

# a cron line for the bot guard
* * * * * /path/to/cs2-classic-server-docker-compose/scripts/botguard.sh >> /var/log/cs2-classic-botguard.log 2>&1
```

Up to v1.3 this said `docker compose -p cs2-classic exec cs2-classic-server rcon status`, and rcon could not work at all, for two reasons. The image has no rcon program. And the compose file set `CS2_RCON_PORT` to the game port, which makes the image's entry script start `socat` on that TCP port, forwarding it to itself, before the game starts: the game never got its rcon socket, and every connection was closed unanswered. Both were measured on a real CS2 booted on a CI runner in the plain CS2 template, from the same image on 2026-11-01 (73 GB, 22 minutes): with the old file the connection was closed ([run](https://github.com/heyvaldemar/cs2-server-docker-compose/actions/runs/41369517037)); without `CS2_RCON_PORT`, `tools/rcon.sh status` came back with the hostname and version 1.41.9.4, a wrong password was refused, and Steam called the server current ([run](https://github.com/heyvaldemar/cs2-server-docker-compose/actions/runs/41372125676)). `tools/rcon.sh` runs the protocol in the image's own python3 from inside the container and takes the password from `.env` on stdin, never from the command line where `ps` would show it. The bot guard's kicks went over the same socket and never reached the game either; it does now.

The bot guard is read whole before it runs. bash reads a script as it executes it, from the same byte offset in whatever the file holds by then, so a guard started by cron while its file is being saved in place by an editor would run shifted text. Its body is one brace group ending in `exit`, which bash parses in full first; `tests/read-whole.sh` rewrites the file under a running copy, with and without the braces. A `git pull` or `./update.sh` writes a new file, which a running copy never sees.

## Keeping the game current

**The health check asks the game, not its process.** `tools/healthcheck.sh`, mounted read-only, sends A2S_INFO, the query every server browser sends, to the game port and is healthy only on the engine's reply. Up to v1.3.3 it looked for `cs2` in `/proc`, and a hung or stopped game keeps its process. A map change, a workshop map's included, silences it for seconds; one check tries twice, and Docker allows three misses at a 60-second interval. Each check ends within 7 seconds. **It asks from inside the container**, at the address the game answers on: healthy proves the server answers there, not that the port is published on the host or open in your firewall.

**A healthy server is not a joinable one.** On the machine this template comes from, Team Fortress 2 ran out of date for days in October 2026 while every check passed: the container was healthy, A2S answered, Steam listed the server, and the image watchers had nothing to say because the image had not changed. Players on the current client cannot join a server Steam calls out of date. Steam answers that question directly: `ISteamApps/UpToDateCheck` takes the version a server reports over A2S and says whether it is still accepted. `tools/steam-uptodate.sh` asks it every fifteen minutes, and this image updates the game on every start, so a restart is the update:

- **current**: nothing.
- **behind, people on**: it says so once and waits. A restart drops them.
- **behind, nobody on**: it restarts the server and asks Steam again until Steam calls the new version current. Steam's answer is the proof, not the restart.
- **still behind after three restarts in 24 hours**: it says so once, stops trying, and fails every run, so the timer shows up in `systemctl --failed`.
- **no answer** from the server or from Steam: nothing is decided. A player count it cannot read is never zero. Six hours of silence (`STEAM_UPTODATE_SILENCE`) and it fails.

**One update per host per pass.** On the machine this template comes from, CS2 and CS2 Classic were both behind on the same evening and were updated back to back; each restart had SteamCMD verify 73 GB, and the CPU reached 81 °C. The TF2, CS2, CS2 Classic and Left 4 Dead 2 templates ship the same script and share one host-wide lock and stamp (`/var/tmp/steam-uptodate.*`), so a second server that is behind waits for a pass fifteen minutes after the first one finished. Their timers fire three minutes apart for the same reason.

"Says so" is one line in the journal every run, and, when `STEAM_UPTODATE_NOTIFY` is set, a message on its stdin the first time something new happens: a webhook, mail, anything that reads stdin. The service file has an example.

```bash
# edit the two paths in the service file to where this repository is checked out
sudo cp systemd/steam-uptodate.service systemd/steam-uptodate.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now steam-uptodate.timer
tools/steam-uptodate.sh --check      # what Steam says right now
```

**The timer runs on UTC, with a net under it.** The night the clocks went back an hour, the server this template comes from ran none of its local-time timers for that hour: systemd reads a local calendar in wall-clock time and took the repeated hour as already gone. A calendar in UTC has no repeated hour, and `OnUnitActiveSec=16min` makes up a run missed for any other reason. `tests/timers.sh` checks both with `systemd-analyze` from one second before a fall-back (Berlin's, on 25 October 2026). The script is one brace group read whole before it runs, so an edit to its file mid-run cannot change what the run does (`tests/read-whole.sh`).

## Updating

The pin lives in the `x-images` block at the top of the compose file, as an interpolation default, so a `git pull` delivers the version this repository has tested. Valve updates CS2 often and the server refuses connections from a client on a newer build; the daily freshness check compares the pin against the latest image release and against the registry. `./update.sh` does that on purpose: it moves to the latest release tag, refuses to cross a major unattended, and names any new required variable before anything has moved.

## Testing

`tests/e2e-healthcheck.sh` runs the health check in the pinned image against a stand-in that answers A2S_INFO, answers after a challenge, stays silent, or is not there: healthy, healthy, unhealthy within 7 seconds, unhealthy.

`tests/image-user.sh` asks the registry, without pulling, what the pinned image runs as, compares it with `x-image-user`, and then runs again on a copy of the compose file declaring another user, which must fail.

`tests/steam-uptodate.sh` drives every branch of `tools/steam-uptodate.sh` against stubbed A2S and Steam answers (current, behind with people on, behind and empty, a restart Steam does not accept, three tries a day, silence, another update on the host), then runs four copies with one rule taken out each (the player count, the proof by Steam, the host lock, the daily limit) and sees each do what the rule prevents. `tests/read-whole.sh` and `tests/timers.sh` check the script and its timer.

CI runs all of them on every push alongside shell and workflow linting, a Trivy scan of the pinned image, and a daily check that the pin still resolves to what upstream publishes and matches the latest release.

`tests/rcon.sh` runs `tools/rcon.sh` in the pinned image's own python3 against `tests/fixtures/fake-rcon.py`, started in the pinned image as this compose file's service: `status` read to its end marker, a server that never answers the marker (read until it goes quiet, no hang), a wrong password, no password, and a plant, a client that waits only for the marker. It also fails if `CS2_RCON_PORT` comes back at the game port, with a plant that puts it back.

**The real server** runs in `.github/workflows/real-server.yml`, on GitHub's ubuntu-24.04 runner and not on every push: the install is 73 GB and took 22 minutes on a runner (measured 2026-11-01, from the same image in the plain CS2 template). It installs and boots the game, samples the health check before the game runs and needs it red, waits for it to go green on the engine's A2S answer, changes the map over rcon and needs it answering again on the new map with Docker healthy throughout, then **stops the game** with SIGSTOP and needs it red while the old `/proc` check stays green, and green again after SIGCONT. It runs on a push or pull request that touches the health check, its stand-in test, the compose file (every image pin is there), `.env.example` or the workflow itself, so a pin update meets the real server before it is merged; every Tuesday at 04:17 UTC; and by hand. On the ubuntu-26.04 runner, with Docker Engine 29.4.2, the server logged "We're not logged into Steam" for 80 minutes and never bound its port (2026-11-08), so the workflow stays on 24.04 until that is understood.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · CNCF Ambassador · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
