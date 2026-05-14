# Architecture

`autoheic` is intentionally small. Three files do the real work:

| File | Role |
|---|---|
| `~/Library/Scripts/Folder Action Scripts/autoheic-trigger.scpt` | AppleScript fired by macOS when files are added to a watched folder. Dispatches HEIC/HEIF files one at a time to the converter. |
| `~/.local/bin/heic-convert-one` (or wherever you installed it) | Shell script — receives one file path, converts via `sips`, deletes original. |
| `~/.config/autoheic/config` | Format / quality / keep-originals settings. Sourced on every conversion. |

The `~/.local/bin/autoheic` CLI is purely management surface — it doesn't participate in the runtime conversion path.

## The dispatch chain

```
1. iPhone AirDrops a photo, or anything else creates a file in ~/Downloads
        │
2. macOS's System Events daemon sees the directory change and fires every
   Folder Action attached to that directory
        │
3. autoheic-trigger.scpt runs:
        for each added item:
          if extension is "heic" or "heif":
            shell-out to heic-convert-one <file>
        │
4. heic-convert-one:
        - waits up to 5s for the file's size to stop changing (AirDrop chunks)
        - computes output path (collision-safe)
        - runs /usr/bin/sips to convert
        - if output is non-empty, deletes the original
        - appends a log line
```

Each step runs in the user's session, in the user's permission context. No daemons, no LaunchAgent, no Full Disk Access.

## Why Folder Actions instead of `launchd` + WatchPaths

The "obvious" macOS way to react to files appearing in a folder is a `launchd` LaunchAgent with `WatchPaths`. We tried that first. It has two killer problems on modern macOS:

1. **TCC denials.** `launchd`-spawned binaries trying to read `~/Downloads` or `~/Desktop` get `Operation not permitted` even with Full Disk Access granted, unless the binary is properly Developer-ID signed. An ad-hoc-signed app bundle's FDA grant is silently dropped when `launchd` re-spawns it. Re-signing the bundle invalidates the existing grant.

2. **Sledgehammer permissions.** Even when FDA works, you've granted an automation tool **the entire disk**. That's wildly out of proportion to "convert HEICs in my Downloads."

Folder Actions sidestep both. They live in the AppleScript / Finder permission domain, which has per-folder TCC entries Apple maintains correctly. The user grants exactly what's needed — access to *this folder* — and `autoheic` never sees anything else.

## Why not macOS Shortcuts

Shortcuts.app has a "Folder" automation trigger as of macOS 26 (Tahoe). It would be nicer to share — a single iCloud link, one tap to add. We considered it. The tradeoffs:

- The Shortcuts folder trigger is younger and historically less reliable than Folder Actions, especially after sleep / reboot.
- Shortcuts' `Convert Image` action exposes only a coarse quality slider, not `sips`'s fine `formatOptions` knob.
- An imported Shortcut can't auto-create its own automation — recipients still need ~30 seconds of manual GUI setup.
- The shortcut runs through Shortcuts.app, which adds its own notification banner on every run unless suppressed in Settings.

For this tool's specific job — reliable, silent, quality-controllable HEIC conversion — Folder Actions win.

## File format & idempotency

Folder Action attachments are stored in macOS's `System Events` database. `autoheic` manipulates them via `osascript`:

```applescript
tell application "System Events"
  set folder actions enabled to true
  make new folder action at end of folder actions with properties \
      {name: "/Users/you/Downloads", path: "/Users/you/Downloads", enabled: true}
  tell folder action "/Users/you/Downloads"
    make new script with properties {name: "autoheic-trigger.scpt"}
  end tell
end tell
```

The `name` is set to the absolute path of the watched folder, guaranteeing uniqueness (two folders with the same basename in different paths don't collide). All `autoheic add` and `autoheic remove` operations check for existing attachments before mutating — they're safe to re-run.

When `autoheic uninstall` runs, it walks every Folder Action, removes the `autoheic-trigger.scpt` script, and deletes the parent Folder Action only if no other scripts remain attached (so it doesn't clobber unrelated Folder Action setups you may have).

## The stable-size wait

`heic-convert-one` polls the source file's size up to five times at 1s intervals, returning as soon as it sees the same size twice in a row. This handles:

- AirDrop, which writes the file in chunks and may trigger the Folder Action before the last chunk lands
- Browser downloads that rename `.crdownload` → `.heic` mid-write
- Photos.app exports

If the file is gone before stabilization (e.g., another tool moved it), the converter logs a `skip (vanished)` and exits 0.

## Config reload semantics

The config file is sourced fresh on every invocation of `heic-convert-one`. There's no daemon caching state. This means `autoheic config set format=png` takes effect for the next file dropped — no reload, no restart, no re-attach.

## What's deliberately *not* here

- **No file watcher daemon.** Folder Actions are the watcher.
- **No log rotation.** The log is plain text; users can `: > ~/Library/Logs/autoheic.log` if it grows. Conversion lines are ~100 bytes; you'd need to AirDrop ten thousand photos to hit 1 MB.
- **No GUI.** Everything is `autoheic <command>`. Folks who want a GUI can use the Automator app to inspect the same Folder Action state.
- **No recursion.** Each watched folder is independent. Per the Folder Actions API, subfolders are not included.
- **No update mechanism.** Re-run the installer to upgrade.
