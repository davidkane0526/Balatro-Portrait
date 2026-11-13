#!/system/bin/sh
# Runs once per boot: wait for the system and shared storage, then sync mods.
MODDIR=${0%/*}
until [ "$(getprop sys.boot_completed)" = "1" ] && [ -d /sdcard/Android ]; do
  sleep 5
done
sh "$MODDIR/sync_mods.sh" > "$MODDIR/sync_mods.log" 2>&1
