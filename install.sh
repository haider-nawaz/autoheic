#!/bin/bash
# autoheic installer.
#
# Use one of:
#   git clone https://github.com/haider-nawaz/autoheic && cd autoheic && ./install.sh
#   curl -fsSL https://raw.githubusercontent.com/haider-nawaz/autoheic/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/haider-nawaz/autoheic/main/install.sh | bash -s -- --folders=downloads --format=jpeg --yes

set -eu

REPO_OWNER="haider-nawaz"
REPO_NAME="autoheic"
TARBALL_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/main.tar.gz"

# Defaults
PREFIX="$HOME/.local/bin"
FOLDERS=""
FORMAT="jpeg"
QUALITY=95
KEEP_ORIGINALS=0
ASSUME_YES=0
DRY_RUN=0
INTERACTIVE=1

usage() {
  cat <<'EOF'
autoheic installer

USAGE
  install.sh [options]

OPTIONS
  --folders=LIST       Comma-separated folder list. Shorthand names ("downloads",
                       "desktop", "pictures", "documents", "movies") or absolute paths.
                       Use "all" for the common-folders preset.
  --format=NAME        Output format: jpeg (default) | png | tiff | webp
  --quality=N          0–100; applies to jpeg & webp only (default: 95)
  --keep-originals     Don't delete .heic after conversion
  --prefix=PATH        Where to install binaries (default: ~/.local/bin)
  --yes, -y            Skip the confirmation prompt
  --dry-run            Print what would happen; change nothing
  --help, -h           Show this message

EXAMPLES
  ./install.sh                              # fully interactive
  ./install.sh --folders=all --yes          # all common folders, JPEG quality 95
  ./install.sh --folders=downloads,desktop --format=png --yes
EOF
}

die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

# Parse arguments.
for arg in "$@"; do
  case "$arg" in
    --folders=*)        FOLDERS="${arg#*=}"; INTERACTIVE=0 ;;
    --format=*)         FORMAT="${arg#*=}" ;;
    --quality=*)        QUALITY="${arg#*=}" ;;
    --keep-originals)   KEEP_ORIGINALS=1 ;;
    --prefix=*)         PREFIX="${arg#*=}" ;;
    --yes|-y)           ASSUME_YES=1 ;;
    --dry-run)          DRY_RUN=1 ;;
    --help|-h)          usage; exit 0 ;;
    *)                  die "unknown option: $arg (try --help)" ;;
  esac
done

# Bootstrap: when run via `curl | bash`, the script has no neighboring repo
# files. Detect that and clone the latest into a temp dir, then re-exec.
SCRIPT_DIR=$(cd "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
[[ -z "$SCRIPT_DIR" ]] && SCRIPT_DIR=$PWD
if [[ ! -f "$SCRIPT_DIR/applescript/autoheic-trigger.applescript" ]]; then
  command -v curl >/dev/null || die "curl is required for the one-liner install"
  command -v tar >/dev/null || die "tar is required"
  TMP=$(mktemp -d -t autoheic-install)
  trap 'rm -rf "$TMP"' EXIT
  printf 'Fetching autoheic source...\n'
  curl -fsSL "$TARBALL_URL" | tar -xz -C "$TMP" --strip-components=1
  cd "$TMP"
  exec bash ./install.sh "$@"
fi

# Preflight.
[[ "$(uname)" == "Darwin" ]] || die "macOS only (detected $(uname))"
[[ -x /usr/bin/sips ]] || die "/usr/bin/sips not found"
command -v osacompile >/dev/null || die "osacompile not found"
command -v osascript >/dev/null || die "osascript not found"

# Format validation (catches typos early, before any prompting).
case "$FORMAT" in
  jpeg|png|tiff|webp) ;;
  *) die "invalid --format=$FORMAT (must be jpeg, png, tiff, webp)" ;;
esac
if [[ ! "$QUALITY" =~ ^[0-9]+$ ]] || (( QUALITY < 0 || QUALITY > 100 )); then
  die "invalid --quality=$QUALITY (must be 0–100)"
fi

# Interactive prompts.
if [[ $INTERACTIVE -eq 1 ]]; then
  cat <<'EOF'

autoheic — HEIC auto-converter for macOS
========================================

EOF
  printf 'Install prefix [%s]: ' "$PREFIX"
  read -r ans
  [[ -n "${ans:-}" ]] && PREFIX="$ans"

  cat <<'EOF'

Which folders should be watched? Space-separated numbers:
  [1] Downloads
  [2] Desktop
  [3] Pictures
  [4] Documents
  [5] Movies
  [a] All of the above (common folders preset)
  [c] Custom paths (you'll be prompted)
EOF
  printf 'Choice [1]: '
  read -r ans
  ans="${ans:-1}"
  if [[ "$ans" == "a" ]]; then
    FOLDERS="downloads,desktop,pictures,documents,movies"
  elif [[ "$ans" == "c" ]]; then
    printf 'Enter folder paths (space-separated, ~ allowed): '
    read -r custom
    FOLDERS=$(printf '%s' "$custom" | tr ' ' ',')
  else
    folder_list=""
    for n in $ans; do
      case "$n" in
        1) folder_list+="downloads," ;;
        2) folder_list+="desktop," ;;
        3) folder_list+="pictures," ;;
        4) folder_list+="documents," ;;
        5) folder_list+="movies," ;;
        *) die "invalid choice: $n" ;;
      esac
    done
    FOLDERS="${folder_list%,}"
  fi

  printf '\nOutput format (jpeg | png | tiff | webp) [%s]: ' "$FORMAT"
  read -r ans
  [[ -n "${ans:-}" ]] && FORMAT="$ans"
  case "$FORMAT" in
    jpeg|png|tiff|webp) ;;
    *) die "invalid format: $FORMAT" ;;
  esac

  case "$FORMAT" in
    jpeg|webp)
      printf 'Quality 0–100 [%s]: ' "$QUALITY"
      read -r ans
      [[ -n "${ans:-}" ]] && QUALITY="$ans"
      if [[ ! "$QUALITY" =~ ^[0-9]+$ ]] || (( QUALITY < 0 || QUALITY > 100 )); then
        die "invalid quality: $QUALITY"
      fi
      ;;
  esac

  printf 'Delete originals after converting? [Y/n]: '
  read -r ans
  case "${ans:-y}" in
    n|N|no|No) KEEP_ORIGINALS=1 ;;
    *)         KEEP_ORIGINALS=0 ;;
  esac
fi

# Folder-list normalization: handle "all" shorthand for non-interactive flag.
if [[ "$FOLDERS" == "all" ]]; then
  FOLDERS="downloads,desktop,pictures,documents,movies"
fi

[[ -n "$FOLDERS" ]] || die "no folders specified (use --folders=... or run interactively)"

# Resolve each folder name to an absolute path.
RESOLVED_FOLDERS=()
IFS=',' read -r -a FOLDER_INPUTS <<< "$FOLDERS"
for raw in "${FOLDER_INPUTS[@]}"; do
  raw="${raw#"${raw%%[![:space:]]*}"}"  # ltrim
  raw="${raw%"${raw##*[![:space:]]}"}"  # rtrim
  [[ -z "$raw" ]] && continue
  case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')" in
    downloads) abs="$HOME/Downloads" ;;
    desktop)   abs="$HOME/Desktop" ;;
    pictures)  abs="$HOME/Pictures" ;;
    documents) abs="$HOME/Documents" ;;
    movies)    abs="$HOME/Movies" ;;
    *)
      abs="${raw/#\~/$HOME}"
      ;;
  esac
  if [[ ! -d "$abs" ]]; then
    printf 'warning: skipping non-existent folder: %s\n' "$abs" >&2
    continue
  fi
  abs=$(cd "$abs" && pwd)
  RESOLVED_FOLDERS+=("$abs")
done

[[ ${#RESOLVED_FOLDERS[@]} -gt 0 ]] || die "no valid folders to watch"

# Echo the plan.
cat <<EOF

Install plan
============
  Install prefix:    $PREFIX
  Output format:     $FORMAT
  Quality:           $QUALITY
  Keep originals:    $([[ $KEEP_ORIGINALS == 1 ]] && echo yes || echo no)
  Watched folders:
EOF
for f in "${RESOLVED_FOLDERS[@]}"; do printf '    - %s\n' "$f"; done

if [[ $ASSUME_YES -eq 0 && $DRY_RUN -eq 0 ]]; then
  printf '\nProceed? [Y/n] '
  read -r ans
  case "${ans:-y}" in
    n|N|no|No) echo "aborted"; exit 1 ;;
  esac
fi

if [[ $DRY_RUN -eq 1 ]]; then
  printf '\n(dry run — no changes made)\n'
  exit 0
fi

# --- actually install ---

printf '\nInstalling...\n'

mkdir -p "$PREFIX" "$PREFIX/lib" "$HOME/.config/autoheic" \
         "$HOME/Library/Scripts/Folder Action Scripts" "$HOME/Library/Logs"

# Copy binaries.
install -m 0755 ./bin/autoheic           "$PREFIX/autoheic"
install -m 0755 ./bin/heic-convert-one   "$PREFIX/heic-convert-one"
install -m 0644 ./bin/lib/common.sh      "$PREFIX/lib/common.sh"
printf '  installed binaries to %s\n' "$PREFIX"

# Write config.
cat > "$HOME/.config/autoheic/config" <<EOF
# autoheic configuration — managed by 'autoheic config set ...'
AUTOHEIC_FORMAT="$FORMAT"
AUTOHEIC_QUALITY=$QUALITY
AUTOHEIC_KEEP_ORIGINAL=$KEEP_ORIGINALS
AUTOHEIC_LOG="\$HOME/Library/Logs/autoheic.log"
EOF
printf '  wrote %s/.config/autoheic/config\n' "$HOME"

# Compile AppleScript with the actual converter path baked in.
TMPSCRIPT=$(mktemp -t autoheic-applescript)
sed "s|__CONVERTER_PATH__|$PREFIX/heic-convert-one|g" \
    ./applescript/autoheic-trigger.applescript > "$TMPSCRIPT"
osacompile -o "$HOME/Library/Scripts/Folder Action Scripts/autoheic-trigger.scpt" "$TMPSCRIPT"
rm -f "$TMPSCRIPT"
printf '  compiled Folder Action trigger to ~/Library/Scripts/Folder Action Scripts/autoheic-trigger.scpt\n'

# Attach to each folder using the management CLI we just installed.
for f in "${RESOLVED_FOLDERS[@]}"; do
  "$PREFIX/autoheic" add "$f" >/dev/null
  printf '  watching %s\n' "$f"
done

# PATH check.
case ":$PATH:" in
  *":$PREFIX:"*) ON_PATH=1 ;;
  *)             ON_PATH=0 ;;
esac

cat <<EOF

Done.

Try it now: drop a HEIC into one of the watched folders. Within ~5 seconds it
should be converted and the original removed (unless you chose --keep-originals).

Useful commands:
  $PREFIX/autoheic status      Show current state and recent log entries
  $PREFIX/autoheic doctor      Run health checks
  $PREFIX/autoheic add <dir>   Watch another folder
  $PREFIX/autoheic help        All commands
EOF

if [[ $ON_PATH -eq 0 ]]; then
  cat <<EOF

Note: $PREFIX is not on your PATH. Add this to your shell profile (~/.zshrc):

  export PATH="$PREFIX:\$PATH"

Then 'autoheic' will work without the full path.
EOF
fi
