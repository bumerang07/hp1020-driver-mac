#!/bin/sh
set -eu
cd "$(dirname "$0")"
sudo /bin/sh ./uninstall.sh
printf '\nPress Return to close. '
read -r ANSWER
