#!/bin/bash
# Shared helpers for autoheic. Sourced by `autoheic` and `heic-convert-one`.
# shellcheck shell=bash

AUTOHEIC_VERSION="0.1.0"

AUTOHEIC_CONFIG_DIR="${AUTOHEIC_CONFIG_DIR:-$HOME/.config/autoheic}"
AUTOHEIC_CONFIG_FILE="${AUTOHEIC_CONFIG_FILE:-$AUTOHEIC_CONFIG_DIR/config}"
AUTOHEIC_DEFAULT_LOG="$HOME/Library/Logs/autoheic.log"
AUTOHEIC_SCRIPT_NAME="autoheic-trigger.scpt"
AUTOHEIC_SCRIPT_PATH="$HOME/Library/Scripts/Folder Action Scripts/$AUTOHEIC_SCRIPT_NAME"

# Set defaults, then source config if it exists.
autoheic_load_config() {
  AUTOHEIC_FORMAT="jpeg"
  AUTOHEIC_QUALITY=95
  AUTOHEIC_KEEP_ORIGINAL=0
  AUTOHEIC_LOG="$AUTOHEIC_DEFAULT_LOG"
  if [[ -f "$AUTOHEIC_CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$AUTOHEIC_CONFIG_FILE"
  fi
}

# Map format name -> output file extension.
autoheic_format_ext() {
  case "$1" in
    jpeg) printf 'jpg' ;;
    png) printf 'png' ;;
    tiff) printf 'tiff' ;;
    webp) printf 'webp' ;;
    *) return 1 ;;
  esac
}

# Map format name -> sips -s format value.
autoheic_sips_format() {
  case "$1" in
    jpeg) printf 'jpeg' ;;
    png) printf 'png' ;;
    tiff) printf 'tiff' ;;
    webp) printf 'webp' ;;
    *) return 1 ;;
  esac
}

# Append a timestamped line to the log.
autoheic_log() {
  local log="${AUTOHEIC_LOG:-$AUTOHEIC_DEFAULT_LOG}"
  mkdir -p "$(dirname -- "$log")" 2>/dev/null
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$log"
}

# Resolve a folder shorthand ("downloads") or path to an absolute directory path.
# Returns nonzero if it doesn't resolve to an existing directory.
autoheic_resolve_folder() {
  local input="$1"
  local resolved=""
  case "$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')" in
    downloads) resolved="$HOME/Downloads" ;;
    desktop)   resolved="$HOME/Desktop" ;;
    pictures)  resolved="$HOME/Pictures" ;;
    documents) resolved="$HOME/Documents" ;;
    movies)    resolved="$HOME/Movies" ;;
    *)
      # Treat as a path. Expand ~ and resolve.
      resolved="${input/#\~/$HOME}"
      ;;
  esac
  if [[ -d "$resolved" ]]; then
    (cd "$resolved" && pwd)
  else
    return 1
  fi
}
