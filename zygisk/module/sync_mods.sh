#!/system/bin/sh
# Copies mods from /sdcard/BalatroMods into the official app's Mods folder.
#
# The app's folder is private: a file manager running as root leaves files the
# app cannot read (wrong owner and SELinux label), so the copy is done here and
# every file gets the app's own. Run at boot (service.sh) and from the root
# manager's Action button (action.sh). A mod taken out of the drop folder is
# removed from the app too; anything the game wrote into the Mods folder itself
# (config, Lovely's logs) stays.

PKG=com.playstack.balatro.android
DROP=/sdcard/BalatroMods
BASE=/data/data/$PKG

log() { echo "$1"; }

if [ ! -d "$BASE" ]; then
  log "Balatro is not installed."
  exit 0
fi
mkdir -p "$DROP"

# LOVE names the save folder per build: use the one the game has made.
SAVE=
for name in ASET game; do
  [ -d "$BASE/files/save/$name" ] && SAVE=$name && break
done
if [ -z "$SAVE" ]; then
  log "Open Balatro once first, then run this again."
  exit 0
fi

MODS=$BASE/files/save/$SAVE/Mods
LIST=$MODS/.synced_by_module
mkdir -p "$MODS"

if [ -f "$LIST" ]; then
  while IFS= read -r old; do
    [ -n "$old" ] && [ ! -e "$DROP/$old" ] && rm -rf "$MODS/$old" && log "Removed $old"
  done < "$LIST"
fi

: > "$LIST"
for path in "$DROP"/*; do
  [ -e "$path" ] || continue
  name=${path##*/}
  # Copied over what is there: some mods keep their settings in their own folder.
  if [ -d "$path" ]; then
    mkdir -p "$MODS/$name"
    cp -rf "$path/." "$MODS/$name/" && log "Copied $name"
  else
    cp -f "$path" "$MODS/$name" && log "Copied $name"
  fi
  echo "$name" >> "$LIST"
done

OWNER=$(stat -c '%u:%g' "$BASE")
LABEL=$(ls -Zd "$BASE/files" | awk '{print $1}')
chown -R "$OWNER" "$BASE/files/save/$SAVE/Mods"
[ -n "$LABEL" ] && chcon -R "$LABEL" "$BASE/files/save/$SAVE/Mods"
log "Done. Mods are in $MODS"
