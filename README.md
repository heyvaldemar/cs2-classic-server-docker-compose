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
docker compose -p cs2-classic ps          # healthy once the game process is up
```

This is the [cs2-server-docker-compose](https://github.com/heyvaldemar/cs2-server-docker-compose) template with a workshop collection in front of it. Everything that template knows — the exact-match health check, the external volume, the port rule, the measured limits — applies here and is not repeated. What follows is what changes when the maps come from the Workshop.

## What this file knows that a fresh one does not

**The collection needs its own token, and the token needs to be its own.** A Game Server Login Token drives one server; share it with a plain CS2 server on the same host and both drop off the list. Workshop downloads also require the token — without one the collection never arrives and the server starts on whatever it has, with nothing in the log to say why the maps are missing.

**Workshop mode refuses part of the config, and says so quietly.** `gamemode_casual_server.cfg` is exec'd after the game's defaults and wins for most settings. In workshop mode, some of them come back with `DISALLOWED WORKSHOP CONVAR` in the log and the game's own value at the next map change; `bot_quota` is one of them, and so is `mapcyclefile`. A server configured for zero bots gets its bots back on the second map. `scripts/botguard.sh` is the answer: run from cron every minute, it reads the quota from the config, asks the server over A2S how many bots are on, and kicks them over rcon if the config says none. With any other quota it does nothing.

**The rotation names maps that have to be in the collection.** `mapcycle.txt` is the curated cycle; a name that is not in the collection is skipped. Switch by hand with `ds_workshop_changelevel <mapname>`; `ds_workshop_listmaps` shows what the collection brought.

**The memory ceiling is 6 GB, and the number it is not is 14.** Peak reads 14 GB on the machine this template comes from, and that is SteamCMD's page cache during a game update, not the server: resident stays under 1 GB. Cache is reclaimed under a limit, never OOM-killed, so the ceiling only has to clear the resident set with room for a workshop download.

**Seed the volume from a plain CS2 server if you have one.** Same game, same 60 GB. `docker run --rm -v cs2-server-data:/from:ro -v cs2-classic-server-data:/to alpine cp -a /from/. /to/` once, and the second download never happens. The volume is external for the same reason as in the plain template: `docker compose down -v` must not be able to delete 80 GB.

**The image's user is written down, and checked against the registry.** Every file in the volume belongs to the user the image runs as, and a volume does not follow when an image moves it. `joedwards32/cs2` moved it twice in eight days in September 2026, 1000 to 999 and back. On the machine this template comes from, the first move left both CS2 servers unable to write their logs for a day and a half, with the containers healthy, the games answering and Steam listing them. The compose file now declares `x-image-user: "1000:1000"`, and `tests/image-user.sh` fails when the pinned image runs as anyone else, so a pin refresh that moves the user cannot ship as a patch. Every release of this template so far has pinned an image that runs as 1000:1000. If one ever moves it, its notes carry the one command that re-owns the volume: `docker run --rm -v cs2-classic-server-data:/v alpine chown -R <uid>:<gid> /v`.

## Administration

```bash
docker compose -p cs2-classic exec cs2-classic-server rcon status
docker compose -p cs2-classic exec cs2-classic-server rcon ds_workshop_listmaps
docker compose -p cs2-classic exec cs2-classic-server rcon ds_workshop_changelevel cs_assault

# a cron line for the bot guard
* * * * * /path/to/cs2-classic-server-docker-compose/scripts/botguard.sh >> /var/log/cs2-classic-botguard.log 2>&1
```

The bot guard is read whole before it runs. bash reads a script as it executes it, from the same byte offset in whatever the file holds by then, so a guard started by cron while its file is being saved in place by an editor would run shifted text. Its body is one brace group ending in `exit`, which bash parses in full first; `tests/read-whole.sh` rewrites the file under a running copy, with and without the braces. A `git pull` or `./update.sh` writes a new file, which a running copy never sees.

## Keeping the game current

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

**The timer runs on UTC, with a net under it.** On 2026-11-01, when the clocks went back an hour, the server this template comes from ran none of its local-time timers between 06:00 and 07:00 UTC: systemd reads a local calendar in wall-clock time and took the repeated hour as already gone. A calendar in UTC has no repeated hour, and `OnUnitActiveSec=16min` makes up a run missed for any other reason. `tests/timers.sh` checks both with `systemd-analyze` on Toronto time that night. The script is one brace group read whole before it runs, so an edit to its file mid-run cannot change what the run does (`tests/read-whole.sh`).

## Updating

The pin lives in the `x-images` block at the top of the compose file, as an interpolation default, so a `git pull` delivers the version this repository has tested. Valve updates CS2 often and the server refuses connections from a client on a newer build; the daily freshness check compares the pin against the latest image release and against the registry. `./update.sh` does that on purpose: it moves to the latest release tag, refuses to cross a major unattended, and names any new required variable before anything has moved.

## Testing

`tests/e2e-healthcheck.sh` runs five assertions against a real container and needs no CS2 download: the exact check is green with the game running, the substring check is green too, and after the game is killed the exact one goes red while the substring one stays green with the wrapper still standing.

`tests/image-user.sh` asks the registry, without pulling, what the pinned image runs as, compares it with `x-image-user`, and then runs again on a copy of the compose file declaring another user, which must fail.

`tests/steam-uptodate.sh` drives every branch of `tools/steam-uptodate.sh` against stubbed A2S and Steam answers (current, behind with people on, behind and empty, a restart Steam does not accept, three tries a day, silence, another update on the host), then runs four copies with one rule taken out each (the player count, the proof by Steam, the host lock, the daily limit) and sees each do what the rule prevents. `tests/read-whole.sh` and `tests/timers.sh` check the script and its timer.

CI runs all of them on every push alongside shell and workflow linting, a Trivy scan of the pinned image, and a daily check that the pin still resolves to what upstream publishes and matches the latest release.

CI does not boot the game. A GitHub runner has neither the disk for 60 GB of game content nor the hours, and a test that pretends otherwise never runs.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · CNCF Ambassador · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
