#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run with sudo from the logged-in account.' >&2; exit 1; }
BASE=/Library/Printers/HP1020Duplex
[ -f "$BASE/queue" ] || { echo 'Installation record not found.' >&2; exit 1; }
QUEUE=$(cat "$BASE/queue")
case "$QUEUE" in ''|*[!A-Za-z0-9_.-]*) exit 1;; esac
[ -f "$BASE/backups/$QUEUE.ppd" ] || { echo 'Original PPD backup missing; leaving installation intact.' >&2; exit 1; }
[ -z "$(/usr/bin/lpstat -W not-completed -o "$QUEUE")" ] || { echo "Finish or cancel queued jobs first." >&2; exit 1; }
/usr/sbin/lpadmin -p "$QUEUE" -P "$BASE/backups/$QUEUE.ppd"
OWNER_UID=$(id -u "${SUDO_USER:?Run with sudo from your user account}")
/bin/launchctl bootout "gui/$OWNER_UID/community.hp1020.duplex.agent" 2>/dev/null || true
rm -f /Library/LaunchAgents/community.hp1020.duplex.agent.plist
# Keep the original PPD backup for recovery. Remove only our executable components.
rm -f "$BASE/hp1020duplex" "$BASE/HP1020-ManualDuplex.ppd" "$BASE/queue"
rm -rf "$BASE/HP1020 Duplex Agent.app"
echo "Original PPD restored for $QUEUE. Backup retained in $BASE/backups."
