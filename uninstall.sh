#!/bin/bash
# Convenience uninstaller — finds the installed `autoheic` binary and runs
# `autoheic uninstall`. If the binary can't be found, falls back to manual
# cleanup of the well-known install locations.

set -eu

for candidate in \
  "$HOME/.local/bin/autoheic" \
  "/usr/local/bin/autoheic" \
  "/opt/homebrew/bin/autoheic"
do
  if [[ -x "$candidate" ]]; then
    exec "$candidate" uninstall "$@"
  fi
done

# Fallback — autoheic CLI not found. Do a best-effort manual cleanup.
echo "autoheic CLI not found in the standard locations." >&2
echo "Falling back to manual cleanup..." >&2

SCRIPT_NAME="autoheic-trigger.scpt"
SCRIPT_PATH="$HOME/Library/Scripts/Folder Action Scripts/$SCRIPT_NAME"

AH_SCRIPT="$SCRIPT_NAME" osascript <<'APPLESCRIPT' >/dev/null || true
set scriptName to system attribute "AH_SCRIPT"
tell application "System Events"
  set toDelete to {}
  repeat with fa in folder actions
    set hasOurs to false
    set otherScripts to 0
    repeat with s in scripts of fa
      if (name of s) is scriptName then
        set hasOurs to true
      else
        set otherScripts to otherScripts + 1
      end if
    end repeat
    if hasOurs then
      if otherScripts is 0 then
        set end of toDelete to (path of fa)
      else
        repeat with s in scripts of fa
          if (name of s) is scriptName then delete s
        end repeat
      end if
    end if
  end repeat
  repeat with p in toDelete
    repeat with fa in folder actions
      if (path of fa) is (p as text) then
        delete fa
        exit repeat
      end if
    end repeat
  end repeat
end tell
APPLESCRIPT

rm -f -- "$SCRIPT_PATH"
rm -rf -- "$HOME/.config/autoheic"
echo "Manual cleanup complete. Log preserved at: $HOME/Library/Logs/autoheic.log"
