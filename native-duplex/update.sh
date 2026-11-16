#!/bin/sh
# Update installed components without removing or resubmitting any print job.
set -eu
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] || { echo 'Run with sudo from your logged-in account.' >&2; exit 1; }
OWNER=${SUDO_USER:?Run sudo from your user account}
[ "$OWNER" != root ] || exit 1
OWNER_UID=$(id -u "$OWNER")
BASE=/Library/Printers/HP1020Duplex
QUEUE=$(cat "$BASE/queue")
case "$QUEUE" in ''|*[!A-Za-z0-9_.-]*) exit 1;; esac
# Failed/held jobs are preserved. Never update while a job is processing.
./build/queue-state "$QUEUE" || { echo 'Wait until the printer is idle or pause it in Print Center.' >&2; exit 1; }
# Pausing a queue with no processing job prevents new work during replacement.
PREVIOUS_STATE=$(./build/queue-state --state "$QUEUE")
/usr/sbin/cupsdisable "$QUEUE"
# Recover orphaned converters left by older builds, for this user only.
HP=/Library/Printers/hp/laserjet/hplaserjetzjs.bundle/Contents/MacOS/rasterToHPZJS
LP_UID=$(id -u _lp)
owned_orphan() {
    /bin/ps -p "$1" -o ppid=,uid=,args= | /usr/bin/awk -v uid="$LP_UID" -v hp="$HP" -v user="$OWNER" '
        $1==1 && $2==uid && $3==hp && $5==user {found=1} END {exit !found}'
}
for PID in $(/bin/ps -axo pid=,ppid=,uid=,comm= | /usr/bin/awk -v uid="$LP_UID" -v hp="$HP" '$2==1 && $3==uid && $4==hp {print $1}'); do
    if owned_orphan "$PID"; then
        kill -TERM "$PID" 2>/dev/null || true
        sleep 2
        if owned_orphan "$PID"; then kill -KILL "$PID" 2>/dev/null || true; fi
    fi
done
[ -x build/hp1020duplex ] && [ -x 'build/HP1020 Duplex Agent.app/Contents/MacOS/HP1020DuplexAgent' ]
install -o root -g wheel -m 555 build/hp1020duplex "$BASE/hp1020duplex.new"
/bin/launchctl bootout "gui/$OWNER_UID/community.hp1020.duplex.agent" 2>/dev/null || true
ditto 'build/HP1020 Duplex Agent.app' "$BASE/HP1020 Duplex Agent.app"
chown -R root:wheel "$BASE/HP1020 Duplex Agent.app"
chmod -R go-w "$BASE/HP1020 Duplex Agent.app"
mv -f "$BASE/hp1020duplex.new" "$BASE/hp1020duplex"
/bin/launchctl bootstrap "gui/$OWNER_UID" /Library/LaunchAgents/community.hp1020.duplex.agent.plist
# Check from CUPS's actual account, not from the owner of the IPC directory.
ATTEMPT=0
until /usr/bin/sudo -u _lp "$BASE/hp1020duplex" --check-agent "$OWNER"; do
    ATTEMPT=$((ATTEMPT + 1))
    [ "$ATTEMPT" -lt 10 ] || { echo 'Updated, but agent IPC check failed. Do not resume printing yet.' >&2; exit 1; }
    sleep 1
done
# Refresh stale job-0 state only when doing so cannot start a queued document.
ACTIVE_COUNT=$(./build/queue-state --job-count "$QUEUE")
if [ "$PREVIOUS_STATE" != 5 ] && [ "$ACTIVE_COUNT" = 0 ]; then
    /usr/sbin/cupsenable "$QUEUE"
else
    echo 'Queue remains paused; resume it manually in Print Center when ready.'
fi
printf 'Updated %s. No print jobs were resumed or resubmitted.\n' "$QUEUE"
