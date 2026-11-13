#!/system/bin/sh
# The root manager's Action button: sync mods now, without a reboot.
MODDIR=${0%/*}
sh "$MODDIR/sync_mods.sh"
