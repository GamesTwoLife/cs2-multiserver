#! /bin/bash
## vim: noet:sw=0:sts=0:ts=4

# Daily CS2 game update, followed by a restart of every instance - ONLY if the
# update succeeded. Meant to be run from cron (cron's environment is minimal,
# so this resolves the msm script by its own location instead of relying on
# $PATH/the `cs2-server` symlink).
#
# Install (crontab -e):
#   0 6 * * * /home/<USER>/cs2-multiserver/contrib/cron/daily-update.sh >> /home/<USER>/msm.d/cs2/log/daily-update.log 2>&1
#
# Uses `restart-all`, not `start-all`: `cs2-server update` only stops running
# instances itself when the CS2 GAME needed an update. If only a plugin pin
# (Metamod/CounterStrikeSharp/SwiftlyS2) got bumped, instances were never
# stopped, and `start-all` would be a no-op on them - `restart-all` forces a
# real stop+start on every instance either way, so newly deployed plugin files
# always actually get picked up.
#
# NOTE: `cs2-server update` also checks for newer Metamod/CounterStrikeSharp/
# SwiftlyS2 builds and asks "Update <name> to this version? (Y/n)". With no
# terminal attached (as under cron), that prompt gets an empty read and
# `promptY` treats empty input as the default answer - Y. So this WILL
# auto-update plugin pins to whatever is newest on GitHub at 6 AM, unreviewed.
# If you don't want that, remove the `update` line below and only keep
# `restart-all`, updating the game/plugins manually and interactively instead.

set -e

MSM_DIR="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"

"$MSM_DIR/msm" update
"$MSM_DIR/msm" restart-all
