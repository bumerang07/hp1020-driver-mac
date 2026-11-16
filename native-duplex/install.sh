#!/bin/sh
# Install only after building. Does not disable SIP or the CUPS sandbox.
set -eu
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] || { echo 'Run: sudo sh native-duplex/install.sh QUEUE_NAME' >&2; exit 1; }
QUEUE=${1:-HP_LaserJet_1020}
case "$QUEUE" in ''|*[!A-Za-z0-9_.-]*) echo 'Invalid queue name' >&2; exit 1;; esac
OWNER=${SUDO_USER:-}
[ -n "$OWNER" ] && [ "$OWNER" != root ] || { echo 'Run sudo from the logged-in user account.' >&2; exit 1; }
OWNER_UID=$(id -u "$OWNER")
BASE=/Library/Printers/HP1020Duplex
HP=/Library/Printers/hp/laserjet/hplaserjetzjs.bundle/Contents/MacOS/rasterToHPZJS
[ -x "$HP" ] || { echo 'Install the original HP driver first (main README).' >&2; exit 1; }
[ -f build/HP1020-ManualDuplex.ppd ] && [ -x build/hp1020duplex ] || { echo 'Run sh native-duplex/build.sh first.' >&2; exit 1; }
/usr/bin/lpstat -p "$QUEUE" >/dev/null
[ -z "$(/usr/bin/lpstat -W not-completed -o "$QUEUE")" ] || { echo "Finish or cancel queued jobs before installation." >&2; exit 1; }
[ -f "/etc/cups/ppd/$QUEUE.ppd" ] || { echo 'Existing queue PPD not found.' >&2; exit 1; }
if [ -f "$BASE/queue" ] && [ "$(cat "$BASE/queue")" != "$QUEUE" ]; then
    echo 'Prototype supports one queue per installation. Uninstall the previous queue first.' >&2; exit 1
fi
/usr/bin/cupstestppd -W filters -q build/HP1020-ManualDuplex.ppd
mkdir -p "$BASE/backups"
chown root:wheel "$BASE" "$BASE/backups"
chmod 755 "$BASE"
chmod 700 "$BASE/backups"
if [ ! -f "$BASE/backups/$QUEUE.ppd" ]; then
    cp "/etc/cups/ppd/$QUEUE.ppd" "$BASE/backups/$QUEUE.ppd"
    chmod 600 "$BASE/backups/$QUEUE.ppd"
fi
install -o root -g wheel -m 555 build/hp1020duplex "$BASE/hp1020duplex"
ditto 'build/HP1020 Duplex Agent.app' "$BASE/HP1020 Duplex Agent.app"
chown -R root:wheel "$BASE/HP1020 Duplex Agent.app"
chmod -R go-w "$BASE/HP1020 Duplex Agent.app"
install -o root -g wheel -m 644 build/HP1020-ManualDuplex.ppd "$BASE/HP1020-ManualDuplex.ppd"
PLIST=/Library/LaunchAgents/community.hp1020.duplex.agent.plist
cat > "$PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>community.hp1020.duplex.agent</string>
<key>ProgramArguments</key><array><string>/Library/Printers/HP1020Duplex/HP1020 Duplex Agent.app/Contents/MacOS/HP1020DuplexAgent</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>LimitLoadToSessionType</key><string>Aqua</string>
<key>ThrottleInterval</key><integer>10</integer>
</dict></plist>
PLIST
chown root:wheel "$PLIST"
chmod 644 "$PLIST"
/usr/bin/plutil -lint "$PLIST"
/bin/launchctl bootout "gui/$OWNER_UID/community.hp1020.duplex.agent" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$OWNER_UID" "$PLIST"
/usr/sbin/lpadmin -p "$QUEUE" -P "$BASE/HP1020-ManualDuplex.ppd" -o HPManualDuplex=LongEdge
printf '%s\n' "$QUEUE" > "$BASE/queue"
chmod 600 "$BASE/queue"
printf 'Installed for %s. Reopen the print dialog and find Manual Two-Sided Printing under Printer Features.\n' "$QUEUE"
