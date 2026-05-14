# autoheic

> Drop a HEIC anywhere watched, get a JPEG. No Full Disk Access, no daemon, no fuss.

[![CI](https://github.com/haider-nawaz/autoheic/actions/workflows/ci.yml/badge.svg)](https://github.com/haider-nawaz/autoheic/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform: macOS 11+](https://img.shields.io/badge/Platform-macOS%2011%2B-blue)

A tiny macOS utility that watches the folders you choose (Downloads, Desktop, anywhere) and auto-converts any HEIC/HEIF photo that lands there into JPEG (or PNG, TIFF, WebP), preserving quality and removing the original. Powered by macOS's built-in `sips` and AppleScript Folder Actions — no third-party daemons, no Full Disk Access required.

## Why

Photos taken on iPhone arrive on Mac as `.heic`, which most websites and chat apps still refuse to accept. The usual fix is to open every photo in Preview and re-export — painful when you AirDrop ten at a time. `autoheic` does it for you, the moment the file appears.

## Install

One line:

```bash
curl -fsSL https://raw.githubusercontent.com/haider-nawaz/autoheic/main/install.sh | bash
```

Or if you'd prefer to read the script first:

```bash
curl -fsSL https://raw.githubusercontent.com/haider-nawaz/autoheic/main/install.sh -o install.sh
less install.sh
bash install.sh
```

Or clone and install manually:

```bash
git clone https://github.com/haider-nawaz/autoheic.git
cd autoheic
./install.sh
```

The installer will prompt you to pick which folders to watch, the output format, and the quality. To skip the prompts:

```bash
# All common folders, JPEG quality 95 (recommended defaults)
curl -fsSL https://raw.githubusercontent.com/haider-nawaz/autoheic/main/install.sh \
  | bash -s -- --folders=all --yes

# Just Downloads, PNG output
curl -fsSL https://raw.githubusercontent.com/haider-nawaz/autoheic/main/install.sh \
  | bash -s -- --folders=downloads --format=png --yes
```

### Requirements

- macOS 11 (Big Sur) or newer — `sips` supports WebP from this version
- Apple's built-in command-line tools (already on every Mac): `sips`, `osascript`, `osacompile`

That's it. No Homebrew dependency, no Xcode, no Developer ID.

### First-time permission prompt

The first time a HEIC arrives in a freshly attached folder, macOS may ask whether System Events can access that folder. **Click Allow.** This is the OS's permission model handling things correctly — `autoheic` doesn't need or request Full Disk Access.

## Usage

You don't run anything. Just drop a HEIC into any watched folder (AirDrop, save dialog, drag-from-Photos, browser download) and within a few seconds:

- A `.jpg` appears next to it (or `.png` / `.tiff` / `.webp` depending on your config)
- The original `.heic` is deleted (unless `keep_originals` is on)
- A line is appended to `~/Library/Logs/autoheic.log`

Check what's happening:

```bash
autoheic status
```

```
autoheic 0.1.0

Config (/Users/you/.config/autoheic/config):
  format          jpeg
  quality         95
  keep_originals  no
  log             /Users/you/Library/Logs/autoheic.log

Watched folders:
  /Users/you/Downloads
  /Users/you/Desktop

Recent log entries:
  2026-05-15 14:22:01 converted: /Users/you/Downloads/IMG_1234.HEIC -> /Users/you/Downloads/IMG_1234.jpg
  ...
```

## Adding and removing watched folders

```bash
autoheic add ~/Pictures                  # absolute path
autoheic add downloads                    # shorthand (downloads | desktop | pictures | documents | movies)
autoheic add "/Volumes/External/Photos"   # any folder you can write to
autoheic remove ~/Desktop
autoheic list
```

Folder Actions on macOS are **not recursive** — they only fire for files added directly to the attached folder, not its subfolders. If you want to watch a subfolder, attach it explicitly.

> **What about watching the whole disk?** That would require a different mechanism (`launchd` + Full Disk Access) with significant TCC complications. The common-folders preset (`--folders=all`) catches ~99% of where HEICs actually land — Downloads, Desktop, Pictures, Documents, Movies — and stays out of FDA territory. If you've got an unusual workflow, just `autoheic add` whatever folder needs it.

## Changing output format and quality

```bash
autoheic config set format=png       # also: jpeg, tiff, webp
autoheic config set quality=92       # 0–100, only used by jpeg & webp
autoheic config set keep_originals=1 # don't delete the .heic
autoheic config list                 # show current settings
```

Format reference:

| Format | Extension | Lossy? | Quality knob | Notes |
|---|---|---|---|---|
| `jpeg` | `.jpg` | yes | 0–100 | Universal, best compatibility. Default. |
| `png` | `.png` | no | — | Lossless. Larger files. |
| `tiff` | `.tiff` | no | — | Lossless, common in photo pipelines. |
| `webp` | `.webp` | yes | 0–100 | Modern, ~30% smaller than JPEG at same quality. macOS 11+. |

Changes take effect immediately — no reload, no restart. The next HEIC dropped uses the new setting.

## Converting pre-existing HEICs

Folder Actions only fire on **newly added** files. To bulk-convert files that were already in a folder before you set this up:

```bash
autoheic sweep ~/OldPhotos           # convert all HEICs in a folder
autoheic sweep                       # default: sweeps all attached folders
```

Sweep is non-recursive too — pass a subfolder explicitly if you need it.

## Status, health, debugging

```bash
autoheic status                      # config + watched folders + recent log
autoheic doctor                      # PASS/FAIL checks for every prerequisite
tail -f ~/Library/Logs/autoheic.log  # watch live
```

`autoheic doctor` checks: macOS, `sips` & `osascript` present, trigger `.scpt` installed, config file readable, Folder Actions globally enabled, at least one folder attached, all attached folders still exist, log directory writable.

For deeper troubleshooting: [docs/DEBUGGING.md](docs/DEBUGGING.md)

## Uninstall

```bash
autoheic uninstall
# or, equivalently
./uninstall.sh
```

Removes binaries, config, the Folder Action attachments, and the trigger `.scpt`. **Preserves the log** so you have a record. To zap the log too: `rm ~/Library/Logs/autoheic.log`.

## Limitations

- **Newly-added files only.** Folder Actions don't fire for files that existed before the action was attached. Use `autoheic sweep` for those.
- **Non-recursive.** Each folder is watched independently — subfolders aren't included automatically.
- **Mac must be awake and logged in.** Folder Actions run in your user session. Files dropped while you're at the lock screen will queue and convert on next login + folder change.
- **First-time permission prompt.** macOS may ask for folder access the first time. One click, done.
- **AirDrop bursts.** The trigger waits up to 5 seconds for each file's size to stabilize, so partial-write artifacts are avoided. For very large RAW transfers, conversions may stack briefly.

## How it works

Two-file design — an AppleScript Folder Action attached to your chosen folders via `System Events`, and a shell script that does the actual `sips` conversion.

```
File added to ~/Downloads
        │
        ▼
System Events fires the Folder Action
        │
        ▼
~/Library/Scripts/Folder Action Scripts/autoheic-trigger.scpt
        │  (filters .heic/.heif by extension)
        ▼
~/.local/bin/heic-convert-one  <file>
        │  (waits for stable size, then)
        ▼
/usr/bin/sips -s format jpeg ...
        │
        ▼
.jpg written next to .heic, .heic deleted, log line appended
```

The config at `~/.config/autoheic/config` is sourced on every conversion, so changing settings via `autoheic config set` takes effect immediately.

Deep dive in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Contributing

Bug reports and pull requests welcome. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for local setup, the test harness, and tips on extending the converter.

## License

MIT — see [LICENSE](LICENSE).
