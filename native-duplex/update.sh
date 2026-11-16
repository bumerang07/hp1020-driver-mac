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
STATUS=$(LC_ALL=C /usr/bin/lpstat -p "$QUEUE")
case "$STATUS" in *' is idle.'*|*' disabled '*) ;; *) echo 'Wait until the printer is idle or pause it in Print Center.' >&2; exit 1;; esac
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
printf 'Updated %s. No print jobs were resumed or resubmitted.\n' "$QUEUE"
