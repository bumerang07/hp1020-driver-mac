#!/bin/sh
set -eu
cd "$(dirname "$0")"
printf 'Existing printer queues:\n'
/usr/bin/lpstat -e
printf '\nQueue to update [HP_LaserJet_1020]: '
read -r QUEUE
QUEUE=${QUEUE:-HP_LaserJet_1020}
printf '\nThis installs the prototype and its automatic confirmation agent. The original PPD is backed up.\n'
sudo /bin/sh ./install.sh "$QUEUE"
printf '\nPress Return to close. '
read -r ANSWER
