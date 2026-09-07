#!/bin/bash
# Keep the bot count where the config says, on a workshop-mode server.
#
# WHY A GUARD INSTEAD OF CONFIG. This server runs a workshop collection, and
# CS2's workshop mode ignores parts of gamemode_casual_server.cfg — the log
# literally says "DISALLOWED WORKSHOP CONVAR". So a bot_quota set to 0 in the
# config holds until the next map change, and then the bots come back. Run
# this from cron every minute: if the config says zero bots and A2S reports
# some, it kicks them over rcon. With any other quota it does nothing.
#
# Everything talks to the server from inside its own network namespace: the
# query port and rcon are never reached over the host, and the rcon password
# travels on stdin, never in argv where `ps` would show it.
set -u
cd "$(dirname "$0")/.." || exit 1

PROJECT="${CS2_CLASSIC_PROJECT:-cs2-classic}"
CFG=gamemode_casual_server.cfg

want="$(grep -oE '^bot_quota [0-9]+' "$CFG" | awk '{print $2}')"
[ "${want:-0}" = "0" ] || exit 0          # bots wanted: nothing to guard

cid="$(docker compose -p "$PROJECT" ps -q cs2-classic-server 2>/dev/null || true)"
[ -n "$cid" ] || exit 0

port="$(grep -E '^CS2_CLASSIC_SERVER_PORT=' .env 2>/dev/null | head -1 | cut -d= -f2-)"
port="${port:-27015}"

# How many bots are on right now? A2S_INFO carries the bot count; an
# unanswered query is treated as zero, because a server that does not answer
# has bigger problems than bots.
bots="$(docker run --rm --network "container:$cid" -e PORT="$port" python:3.13-alpine python3 -c '
import os, socket
port = int(os.environ["PORT"])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(5)
req = b"\xff\xff\xff\xff\x54Source Engine Query\x00"
try:
    s.sendto(req, ("127.0.0.1", port)); d, _ = s.recvfrom(4096)
    if d[4:5] == b"\x41":
        s.sendto(req + d[5:9], ("127.0.0.1", port)); d, _ = s.recvfrom(4096)
    b = d[6:]; p = b.split(b"\x00", 4)
    print(b[len(p[0]) + len(p[1]) + len(p[2]) + len(p[3]) + 4:][4])
except Exception:
    print(0)
' 2>/dev/null || echo 0)"
[ "${bots:-0}" -gt 0 ] || exit 0

pw="$(grep -E '^CS2_CLASSIC_SERVER_RCON_PASSWORD=' .env | head -1 | cut -d= -f2-)"
[ -n "$pw" ] || { echo "CS2_CLASSIC_SERVER_RCON_PASSWORD is not set in .env" >&2; exit 1; }

printf '%s\n' "$pw" | docker run --rm -i --network "container:$cid" -e PORT="$port" python:3.13-alpine python3 -c '
import os, socket, struct, sys, time
pw = sys.stdin.readline().rstrip("\n"); port = int(os.environ["PORT"])
def pkt(i, t, b):
    d = struct.pack("<ii", i, t) + b.encode() + b"\x00\x00"
    return struct.pack("<i", len(d)) + d
def rcon(cmd):
    s = socket.create_connection(("127.0.0.1", port), timeout=8)
    s.sendall(pkt(1, 3, pw)); s.recv(4096)
    s.sendall(pkt(2, 2, cmd)); time.sleep(0.4); s.close()
rcon("bot_quota 0"); rcon("bot_kick")
' >/dev/null 2>&1
echo "$(date '+%F %T') kicked $bots bot(s) after a map change"
