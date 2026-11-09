#!/bin/bash
# Can the game's user install into a FRESH volume?
#
# The server bind-mounts mapcycle.txt and gamemode_casual_server.cfg inside
# the install directory. On an empty volume Docker creates the directories
# for those mount points, game/, game/csgo/ and game/csgo/cfg/, owned by
# root, and the image runs as 1000: SteamCMD downloads 73 GB and then cannot
# move a file into game/ ("Error! App '730' state is 0x602 after update job",
# measured in CI on 2026-11-09). cs2-classic-server-init hands them to the
# image's user before the server starts.
#
# Each case on a fresh scratch volume, through compose, in the pinned image
# (nothing is downloaded, nothing listens):
#
#   the control   the server alone (--no-deps): its user cannot create
#                 game/bin, so the failure this guards against is real here
#   the fix       with the init first: the server's user creates game/bin and
#                 writes game/csgo/cfg/server.cfg, as SteamCMD and the image do,
#                 and the install path belongs to 1000:1000
#   again         a second start: the init changes nothing and both stay
#   declared      the init hands them to x-image-user, the user
#                 tests/image-user.sh holds the pinned image to
#
# The real volume is never touched: an override names a scratch volume, and
# the scratch .env holds placeholders only.
# shellcheck disable=SC2015   # pass and fail always exit 0, so "A && pass || fail" is if-then-else here
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PASSED=0; FAILED=0
pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }

F=cs2-classic-server-docker-compose.yml
VOL="cs2c-volume-owner-test-$$"
T=$(mktemp -d)
ARGS=(--env-file "$T/env" -f "$F" -f "$T/scratch-volume.yml" -p "cs2c-volume-owner-test-$$")
cleanup() { docker compose "${ARGS[@]}" down -t 1 >/dev/null 2>&1; docker volume rm -f "$VOL" >/dev/null 2>&1; rm -rf "$T"; }
trap cleanup EXIT

printf 'volumes:\n  cs2-classic-server-data:\n    name: %s\n    external: true\n' "$VOL" > "$T/scratch-volume.yml"
printf '%s\n' CS2_CLASSIC_SERVER_STEAM_TOKEN=placeholder CS2_CLASSIC_SERVER_RCON_PASSWORD=placeholder \
  CS2_CLASSIC_SERVER_WORKSHOP_COLLECTION=placeholder > "$T/env"

# shellcheck disable=SC2016  # expanded by the container's shell
WRITE='d=/home/steam/cs2-dedicated
stat -c "%u:%g %n" "$d" "$d/game" "$d/game/csgo" "$d/game/csgo/cfg"
mkdir "$d/game/bin" && touch "$d/game/csgo/cfg/server.cfg" && echo wrote'
# shellcheck disable=SC2016
KEPT='d=/home/steam/cs2-dedicated
[ -d "$d/game/bin" ] && [ -f "$d/game/csgo/cfg/server.cfg" ] && echo kept'
fresh() { docker volume rm -f "$VOL" >/dev/null 2>&1; docker volume create "$VOL" >/dev/null; }
server() {  # [--no-deps] script
  local deps=()
  [ "$1" = --no-deps ] && { deps=(--no-deps); shift; }
  out=$(docker compose "${ARGS[@]}" run --rm -T ${deps[@]+"${deps[@]}"} --entrypoint bash cs2-classic-server -c "$1" 2>&1); rc=$?
}

echo "=== a fresh volume, and the user the image runs as ==="
echo

fresh
server --no-deps "$WRITE"
if [ "$rc" != 0 ] && grep -q 'Permission denied' <<<"$out" && ! grep -qx wrote <<<"$out"; then
  pass "the control: without the init, the image's user cannot create game/bin (Docker made it root's)"
else
  fail "the control: exit $rc, $out"
fi

fresh
server "$WRITE"
owners=$(grep -E '^[0-9]+:[0-9]+ /home/steam/cs2-dedicated' <<<"$out")
if [ "$rc" = 0 ] && grep -qx wrote <<<"$out" && [ "$(grep -c . <<<"$owners")" = 4 ] && [ -z "$(awk '$1 != "1000:1000"' <<<"$owners")" ]; then
  pass "the fix: with the init, game/bin and cfg/server.cfg are written and the install path is 1000:1000"
else
  fail "the fix: exit $rc, $out"
fi

server "$KEPT"
[ "$rc" = 0 ] && grep -qx kept <<<"$out" && pass "again: a second start keeps what the first wrote" || fail "again: exit $rc, $out"

declared=$(grep -m1 -oE '^x-image-user: "[0-9]+:[0-9]+"' "$F" | grep -oE '[0-9]+:[0-9]+')
if [ -n "$declared" ] && grep -qF "chown $declared " "$F"; then
  pass "declared: the init hands the directories to x-image-user ($declared)"
else
  fail "declared: the init's chown does not name x-image-user (${declared:-none declared})"
fi

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
