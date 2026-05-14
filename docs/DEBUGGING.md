# Debugging

When `autoheic` isn't doing its job, work through these in order. Most issues fall out within the first three checks.

## The 30-second checklist

```bash
autoheic doctor
```

Every line should print `✓`. If any line prints `✗`, the message after it is the fix. Stop here unless `doctor` passes — fixing anything further down with a broken prerequisite is a waste of time.

```bash
tail -20 ~/Library/Logs/autoheic.log
```

If `doctor` passed but you don't see recent `converted: ...` lines after dropping a HEIC, something's blocking the dispatch chain. Continue below.

## "I dropped a HEIC and nothing happened"

Try, in order:

1. **Wait 5–10 seconds.** The trigger waits up to 5s for the file size to stabilize, plus dispatch latency.

2. **Force a folder change.** Folder Actions fire on directory mtime changes. `touch ~/Downloads/.tickle && rm ~/Downloads/.tickle` re-fires the action against the folder's current contents — if a HEIC is sitting there, it'll get processed (assuming it was *added* after the action was attached; pre-existing files require `autoheic sweep`).

3. **Check if Folder Actions are globally enabled.**
   ```bash
   osascript -e 'tell application "System Events" to return folder actions enabled'
   ```
   Should print `true`. If `false`:
   ```bash
   osascript -e 'tell application "System Events" to set folder actions enabled to true'
   ```

4. **Check the script is attached.**
   ```bash
   autoheic list
   ```
   Your folder should appear. If not: `autoheic add <folder>`.

5. **Verify the converter runs at all.**
   ```bash
   ~/.local/bin/heic-convert-one /path/to/some.heic
   tail -3 ~/Library/Logs/autoheic.log
   ```
   If this works directly but Folder Action triggers don't, the issue is in the AppleScript dispatch.

6. **Check the compiled trigger script exists.**
   ```bash
   ls -l "$HOME/Library/Scripts/Folder Action Scripts/autoheic-trigger.scpt"
   ```
   If missing, re-run `./install.sh`.

## "Operation not permitted" errors in the log

You'd see lines like:

```
... no access to /Users/you/Downloads (TCC denied): find: /Users/you/Downloads: Operation not permitted
```

This means macOS's TCC (Transparency, Consent, and Control) blocked the conversion script from reading the folder. Causes:

- The first time you drop a file in a newly attached folder, macOS prompts to allow System Events access to the folder. If you dismissed the prompt or it didn't appear, no access.
- You revoked the permission later in **System Settings → Privacy & Security → Files and Folders**.

**Fix:** trigger a fresh permission request. The easiest way:

```bash
# Reset the per-folder permission for System Events, then drop a file again.
tccutil reset SystemPolicyDownloadsFolder com.apple.systemevents
tccutil reset SystemPolicyDesktopFolder   com.apple.systemevents
tccutil reset SystemPolicyDocumentsFolder com.apple.systemevents
```

Then drop a HEIC. The prompt should reappear. Click **Allow**.

If `tccutil` complains the binary is unknown, the entry isn't there yet — System Events just hasn't been asked. Drop a file once first; the prompt comes up; allow it.

## "FAILED (sips error)" in the log

`sips` itself rejected the input. Most common causes:

- The HEIC is corrupted or zero-byte. Open it in Preview — if it doesn't display, the source is bad.
- The HEIC uses an exotic encoding macOS's `sips` doesn't support. Rare. Run `sips -g all path/to/file.heic` to inspect.
- Disk is full. Check `df -h ~`.

Run manually to see the actual `sips` error:

```bash
/usr/bin/sips -s format jpeg -s formatOptions 95 path/to/file.heic --out /tmp/out.jpg
```

## "FAILED (empty output)"

`sips` exited 0 but produced a zero-byte output file. Usually a partial write that got interrupted, or a permission issue writing to the source folder. Check folder permissions:

```bash
ls -ld /path/to/folder
```

You need write access (`w` in the owner field for your user).

## Output files appearing with `-1`, `-2` suffixes

That's intentional. If `IMG_1234.jpg` already exists when converting `IMG_1234.HEIC`, `autoheic` writes `IMG_1234-1.jpg` to avoid clobbering. This usually means a previous conversion already happened and the original re-arrived (or you have a sweep + folder-action race).

To dedup safely: keep the newer file, delete the older.

## The log is enormous

It's plain text. To trim:

```bash
: > ~/Library/Logs/autoheic.log
```

To preserve the last 100 lines:

```bash
tail -100 ~/Library/Logs/autoheic.log > /tmp/log && mv /tmp/log ~/Library/Logs/autoheic.log
```

There's no automatic log rotation — by design, since each line is ~100 bytes and the volume is tiny in practice.

## "It worked yesterday, doesn't today"

Things that change overnight on macOS:

- **System updates.** A macOS minor update sometimes resets TCC permissions. Re-trigger as in the "Operation not permitted" section above.
- **Disk full.** Conversions silently fail when the disk fills.
- **Folder moved/renamed.** `autoheic doctor` reports this as `watched dir exists: <path> ✗`.

## When all else fails

```bash
autoheic uninstall
./install.sh                # or the curl|bash one-liner
```

A clean reinstall takes 10 seconds and resolves most transient state issues. Your log is preserved.

## Opening an issue

If you've worked through this doc and the tool is still misbehaving, please file a bug at https://github.com/haider-nawaz/autoheic/issues with:

- Output of `autoheic doctor`
- Output of `autoheic status`
- Last ~20 lines of `~/Library/Logs/autoheic.log`
- macOS version (`sw_vers`)
- A description of what you dropped where and what happened (or didn't)
