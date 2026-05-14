# Development

Notes for hacking on `autoheic` itself.

## Local install for development

```bash
git clone https://github.com/haider-nawaz/autoheic.git
cd autoheic
./install.sh --folders=downloads --yes --prefix="$PWD/bin"
```

Pointing `--prefix` at the repo's own `bin/` means the installed binaries *are* the working-tree files. Edit, re-test, no reinstall needed (the AppleScript still needs recompiling — see below).

## Testing changes

### Shell scripts

After editing `bin/autoheic`, `bin/heic-convert-one`, or `bin/lib/common.sh`, validate syntax:

```bash
bash -n bin/autoheic
bash -n bin/heic-convert-one
bash -n bin/lib/common.sh
bash -n install.sh
bash -n uninstall.sh
```

Lint with [shellcheck](https://www.shellcheck.net/):

```bash
brew install shellcheck
shellcheck bin/autoheic bin/heic-convert-one bin/lib/common.sh install.sh uninstall.sh
```

CI runs shellcheck on every push (see `.github/workflows/ci.yml`).

### AppleScript

The trigger AppleScript at `applescript/autoheic-trigger.applescript` contains a `__CONVERTER_PATH__` token that `install.sh` substitutes before compiling. To test changes to the AppleScript:

```bash
# Substitute and compile to a scratch path
sed "s|__CONVERTER_PATH__|$PWD/bin/heic-convert-one|g" \
    applescript/autoheic-trigger.applescript > /tmp/at.applescript
osacompile -o /tmp/at.scpt /tmp/at.applescript

# Or just check syntax without compiling
osacompile -o /dev/null /tmp/at.applescript
```

The CI workflow does the syntax check with a dummy converter path.

### End-to-end smoke test

After installing:

```bash
# Make a sample HEIC from an existing JPEG (or use any real .heic)
sips -s format heic ~/some.jpg --out /tmp/sample.heic

# Drop it into a watched folder
cp /tmp/sample.heic ~/Downloads/

# Wait a few seconds, then check
sleep 6
ls ~/Downloads/sample.*
tail -3 ~/Library/Logs/autoheic.log
```

You should see `sample.jpg` (or whatever format you configured) and the original `.heic` gone.

## Adding a new output format

The format → extension and format → `sips` flag mapping lives in **two places** that must agree:

1. `bin/lib/common.sh` — `autoheic_format_ext()` and `autoheic_sips_format()`
2. `bin/autoheic` — the `case` in `cmd_config` that validates `format` values
3. `install.sh` — the `case` validating `--format=`
4. `README.md` — the format reference table

| Format | `sips` `-s format` | Output extension | Has quality? |
|---|---|---|---|
| `jpeg` | `jpeg` | `.jpg` | yes |
| `png` | `png` | `.png` | no |
| `tiff` | `tiff` | `.tiff` | no |
| `webp` | `webp` | `.webp` | yes |

If you add e.g. `bmp`, run `sips -h` first to confirm the correct format string macOS accepts.

`heic-convert-one` already keys off `$AUTOHEIC_FORMAT` to decide whether to pass `-s formatOptions $AUTOHEIC_QUALITY` — only `jpeg` and `webp` accept it. Add new lossy formats to that `case` in `bin/heic-convert-one`.

## Releasing

`autoheic` is versioned via the `AUTOHEIC_VERSION` constant in `bin/lib/common.sh`. Bump it on every user-facing change. Releases are git tags:

```bash
# Update the version
sed -i '' 's/AUTOHEIC_VERSION=".*"/AUTOHEIC_VERSION="0.2.0"/' bin/lib/common.sh
git commit -am "Bump to 0.2.0"

# Tag and push
git tag -a v0.2.0 -m "v0.2.0: <one-line summary>"
git push origin main v0.2.0

# Cut a GitHub release (optional, helps `curl` users pin a version)
gh release create v0.2.0 --generate-notes
```

The `install.sh` one-liner pulls from the `main` branch by default, so released code lands as soon as it's merged. If you want versioned installs, point users at a tag-pinned tarball URL.

## Project layout

```
autoheic/
├── README.md               # User-facing docs
├── LICENSE                 # MIT
├── install.sh              # Installer
├── uninstall.sh            # Convenience wrapper
├── bin/
│   ├── autoheic            # Management CLI
│   ├── heic-convert-one    # Per-file converter (called by trigger)
│   └── lib/common.sh       # Shared helpers + AUTOHEIC_VERSION
├── applescript/
│   └── autoheic-trigger.applescript    # Folder Action source
├── config/default.conf     # Config template
├── docs/                   # ARCHITECTURE / DEBUGGING / this file
└── .github/workflows/ci.yml
```

## Conventions

- All shell is `#!/bin/bash` (not `sh`) so we can use `[[ ]]`, `printf -v`, etc.
- We test on macOS-default bash 3.2 — avoid bash 4+ features (no `${var^^}`, no associative arrays).
- Indentation is two spaces in shell, two spaces in AppleScript (which is forgiving).
- Subcommand functions in `bin/autoheic` are named `cmd_<name>`; helpers start with `_` or `ah_`.
- Logging is structured: `<timestamp> <action>: <details>`. Keep it greppable.

## Things deliberately not in this project

- A daemon, watcher binary, or LaunchAgent. The whole point is using macOS's own infrastructure.
- A GUI. The Automator app already lets you inspect Folder Action state visually.
- Recursive folder watching. Folder Actions don't support it; faking it would require a daemon.
- Image editing beyond format conversion. `sips` can do more; we don't expose it.
- Any third-party dependency. Everything used here ships with macOS.
