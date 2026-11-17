# F07: macOS integrations and their permissions

**Test id:** F07 · **Date:** 2026-11-16 · **Plan:** `PLAN.md` rev 5, §5.2, §5.5, §5.8, §9 (per-process input detection)

## Verdict: PARTIAL

- **Call detection: PASS.** This is the item that mattered most.
  - The CoreAudio process-object API lists exactly which PIDs are capturing input.
  - It tells another process's capture apart from our own (compare PIDs).
  - It needs no permission prompt. A poll costs about 9 ms wall and about 1 ms CPU.
  - An event-driven listener also works, with about 35–45 ms latency. It has to listen on `kAudioProcessPropertyDevices` (`'pdv#'`), not on `IsRunningInput`.
- **Frontmost app: PASS. Browser URL: PASS.**
- **Window title and selected text (AX): BLOCKED.** The test process is not Accessibility-trusted, and I did not change settings.
- **Right-⌥ push-to-talk: UNVERIFIED.**
  - Neither Accessibility nor Input Monitoring is granted.
  - Nobody was at the keyboard, and synthetic events can't be posted without Accessibility.
- **Safe paste: PARTIAL.**
  - Verified: the frontmost check, newline stripping, and the full multi-type clipboard save and restore.
  - Not verified: the ⌘V `CGEvent` was silently dropped because Accessibility is missing.

Every BLOCKED or UNVERIFIED item comes down to one missing grant, **Accessibility**, plus Input Monitoring if we take the listen-only tap route. None of them is an API failure.

## Environment

- **OS and hardware:** macOS 26.6.1 (25G76), Apple Silicon (arm64).
- **Toolchain:** Swift 6.2 (swiftlang-6.2.0.19.9), Command Line Tools only, no Xcode.
- **How the binaries ran:** as unsigned, unbundled CLI binaries built with `swiftc -O`, started from Claude Code's Bash tool.
- **Permissions attribution:**
  - TCC attributes permissions to the **responsible process**, which here is very likely the Claude desktop app. The process tree is `claude` (Claude Code) → zsh. This is `unverified`: the TCC database couldn't be read without Full Disk Access.
  - So "granted" below means "already granted to the host app". It does **not** mean the CLI needs no grant.
  - The real assistant app will have its own bundle id and must get each grant itself.
- **Grants as seen from this process:**

  | Grant | State |
  |---|---|
  | Microphone | granted |
  | Automation (Safari, Brave, Chrome, TextEdit) | granted |
  | Screen Recording | apparently granted: `kCGWindowName` was readable |
  | Accessibility | **not** granted |
  | Input Monitoring | **not** granted |
  | Full Disk Access | **not** granted |

- **Other activity on the machine:** other feasibility spikes (f01, f02, f03) were running at the same time. f03 captured the mic during one listing, and their processes caused a lot of process-list churn. That was a useful real-world check.

## Results

| Feature | Works? | Permission needed | Latency | Notes |
|---|---|---|---|---|
| List processes capturing input (`kAudioHardwarePropertyProcessObjectList` + `ppid` / `piri` / `pbid`) | **Yes** | None observed (no prompt; reading it doesn't touch the mic) | ~9 ms wall, ~1 ms CPU per full poll of 37–39 objects | Idle: 0 capturing. Helper capturing: the helper's PID was shown with `self=false`. |
| Tell another process's capture from our own | **Yes** | — | — | Self + helper: 2 capturing, `another process capturing: true`. Self only: `false`. |
| Event-driven detection (property listener) | **Yes, with a caveat** | None | start ~33 ms, stop ~44 ms | A listener on `piri` **never fired**. A wildcard listener showed the change arrives as `'pdv#'` (`kAudioProcessPropertyDevices`). Re-read `piri` when it fires. Also listen for `prs#` (list changed). |
| Bundle id of a capturing process | Yes for apps | None | — | Empty for unbundled CLIs. Returns `us.zoom.xos`, `com.tinyspeck.slackmacgap`, browser helpers and so on. |
| Frontmost app and bundle id (`NSWorkspace`) | **Yes** | None | ~0.5–0.7 ms | |
| Focused window title (`AXUIElement`) | **No (blocked)** | **Accessibility** | AX call ~20 ms (`AXIsProcessTrusted` check ~24 ms on the first call) | `kAXErrorAPIDisabled` (-25211). `AXIsProcessTrustedWithOptions(prompt: false)` → `false`. |
| Window title fallback (`CGWindowListCopyWindowInfo`, `kCGWindowName`) | Yes here | **Screen Recording** (needed for `kCGWindowName` since 10.15) | ~37–45 ms | Worked only because the host app appears to have Screen Recording. Not a free fallback. |
| Selected text (AX `kAXSelectedTextAttribute`) | **No (blocked)** | **Accessibility** | — | Focused element: -25204. |
| Browser URL (AppleScript) | **Yes** | **Automation** (one entry per target browser) | Brave ~45–90 ms, Chrome ~50 ms, Safari ~160 ms warm (**6.4 s on the first call**) | Read the Brave active tab URL (only the host was logged). Chrome had no window (-1719). Safari's front tab had no URL (start page). Not denied (-1743): Automation is already granted to the host. Whether a prompt appeared on the first Safari call is `unverified`. |
| Right-⌥ via `NSEvent` global monitor (`flagsChanged`) | **Unverified** | Accessibility | — | The monitor is created even without trust, but it receives nothing. No real keypress was tested. |
| Right-⌥ via `CGEventTap` listen-only | **Unverified** | **Input Monitoring** | — | `tapCreate` **succeeded** even though `CGPreflightListenEventAccess() == false`. No events arrived. This call may have shown the system's Input Monitoring request (`unverified`). |
| Right-⌥ via `CGEventTap` default (active) | **No** | Accessibility | — | `tapCreate` returned nil. |
| Right-⌥ by polling `CGEventSource.flagsState` / `keyState(61)` | Unverified | Possibly none | — | Read OK (`0x100`, `false`). No real press, so whether it sees one without a grant is unknown. |
| Paste: frontmost re-check | **Yes** | None | <1 ms | Correctly refused when Brave was frontmost; the clipboard was untouched. |
| Paste: strip trailing newlines | **Yes** | — | — | 6/6 cases: `\n`, `\n\n`, `\r\n` and U+2028/2029 stripped; inner newlines kept. |
| Paste: save and restore all pasteboard types | **Yes** | None (`accessBehavior = alwaysAllow`) | snapshot ~5 ms, restore ~1–5 ms | 2 items: utf8 text, RTF, custom UTI and URL. All original types restored byte for byte. |
| Paste: ⌘V via `CGEvent.post` | **No (blocked)** | **Accessibility** (`CGPreflightPostEventAccess() == false`) | post ~40–57 ms | The event was silently dropped: the TextEdit document stayed empty. No error is returned, so the app must check `AXIsProcessTrusted()` **before** offering Paste. |

### Step 1: per-process call detection

`spikes/f07-macos/procaudio.swift` (`--loop`, `--all`, `--bench N`, `--listen S`, `--selfmic`) and `micgrab.swift` (an `AVAudioEngine` input tap, with an optional pause between connecting and starting).

**Idle.** 37 process objects, 0 with `IsRunningInput`. `another process capturing: false`.

**Helper capturing.** `micgrab` was authorized: 120 buffers, peak 0.83, so this was real audio. Three 1 s polls each showed `INPUT pid=3272 name=micgrab self=false`. After the helper exited, the count went back to 0.

**Our own capture vs another process's.**
- `procaudio --selfmic` alone: 1 capturing, `self=true`, so `another process capturing: false`.
- `--selfmic` together with `micgrab`: 2 capturing (one self, one not), so `true`.
- This confirms PID comparison is enough. It also showed f03 (another spike) capturing input, as `f03 in=true`, which is a real third-party case.

**What the per-process view gives.** It lists apps that are connected but idle: Zoom (`us.zoom.xos`, `us.zoom.caphost`), Slack, Brave and the WebKit GPU process, all with `in=false`. So "Zoom is open" and "Zoom is in a call" can be told apart.

**Polling cost.** The `--bench 1000` poll lists the objects, then reads PID and `IsRunningInput` for each, without the bundle id.
- Per poll: **8.9–9.3 ms wall, ~1.0 ms CPU** (0.24 s user + 0.76 s sys over 1000 polls).
- At 1 Hz that is about 0.1 % of one core.
- Most of the wall time is IPC to `coreaudiod`, so run it off the main thread.

**Listener.**
- `kAudioProcessPropertyIsRunningInput` (`'piri'`) on each process object **never fired**, in either global or wildcard scope.
- A wildcard selector on the same objects fired `'pdv#'` (`kAudioProcessPropertyDevices`):
  - `IsRunningInput → 1` 33 ms after `engine.start`;
  - `→ 0` 44 ms after `engine.stop`.
- `kAudioHardwarePropertyProcessObjectList` (`'prs#'`) fires whenever a process connects to or leaves the HAL.
  - With other spikes running, it fired about every 0.7 s, always in duplicate pairs.
  - So the handler must be cheap and must work from the diff.
- Recommended scheme:
  - listen for `prs#` on the system object;
  - listen for `pdv#` on each process object, re-attaching to new objects whenever `prs#` fires;
  - re-read `piri` on each callback;
  - keep a slow 2–5 s poll as a safety net.

**Not tested.** Whether two voice-processing apps at once cause trouble (§9 asks this): for example our voice-processing engine together with Zoom's, the echo-cancellation/ducking interaction. It needs a real call app in a call. That belongs to F-echo or phase 1.

### Step 2: frontmost context

`spikes/f07-macos/ctx.swift` (`--url` also queries browsers, **only those already running**, so it never launches one).

- **`NSWorkspace.frontmostApplication`:** 0.5 ms, no permission. It returned Brave, and then TextEdit when TextEdit was in front.
- **AX:**
  - `AXIsProcessTrustedWithOptions(prompt: false) = false`, so no prompt was shown.
  - Focused window → -25211 (`APIDisabled`). System-wide focused element → -25204, so no selected text.
  - **Missing permission: Accessibility.**
- **Browser URL:**
  - AppleScript `URL of active tab of front window` (Brave, Chrome) and `URL of current tab of front window` (Safari).
  - Warm latency: Brave about 45 ms, Chrome about 50 ms, Safari about 160 ms. The first Safari call took 6.4 s, cause `unverified`: a cold Apple Event, or an Automation prompt being answered.
  - The plan should treat the first call per browser as slow and run it off the hot path, with a timeout of 1–2 s.
  - Brave is Chromium and uses the same dictionary as Chrome. Add Arc, Edge and Brave bundle ids to the list.

### Step 3: push-to-talk on right ⌥

`spikes/f07-macos/ptt.swift` (`--synth` posts a synthetic right-⌥ down and up, keycode 61 with device bit `0x40`; `--wait N` listens for a real press).

- **Preflight:**
  - `AXIsProcessTrusted = false`;
  - `CGPreflightListenEventAccess` (Input Monitoring) `= false`;
  - `CGPreflightPostEventAccess` `= false`.
- **`NSEvent.addGlobalMonitorForEvents(.flagsChanged)`:** returns a monitor object but receives no events.
  - It needs **Accessibility**, per Apple's docs: global monitors for key events need trust.
  - Nothing arrived here, but the synthetic post was itself blocked, so this is not conclusive.
- **`CGEventTap` listen-only:** created OK even without Input Monitoring, but no events arrived.
  - On 10.15 and later, a listen-only keyboard tap needs **Input Monitoring**.
  - Creating it is what makes the system ask for that permission, so a prompt may have appeared (`unverified`).
- **`CGEventTap` default (active):** nil. It needs **Accessibility**.
- **Right vs left ⌥:** check the device-dependent bit `0x40` (`NX_DEVICERALTKEYMASK`), or keycode 61, on `flagsChanged`.
- **Still to test:** a live test with a human pressing right ⌥ after granting. It takes 2 minutes: `./ptt --wait 10`.

### Step 4: safe paste (TextEdit only)

`spikes/f07-macos/paste.swift` (`<bundle-id> <text>`, `--selftest`) and `pbinfo.swift` (`--seed` writes a test clipboard, `--clear`).

1. **Seeding.** The user's clipboard was **empty** at the start (changeCount 3998, 0 items, `accessBehavior = alwaysAllow`). So I seeded a 2-item test clipboard (utf8 text, RTF and a custom UTI; URL and text), and cleared it back to empty at the end. No user data was handled.
2. **Frontmost check.** With Brave frontmost, `paste com.apple.TextEdit …` aborted with exit 3. Nothing was pasted and the clipboard was untouched.
3. **The paste.** Created an empty `.txt` in the spike folder and ran `open -a TextEdit`. The frontmost check passed, the clipboard was set to `"F07 pasted line"` (the trailing `\n\n` stripped), ⌘V was posted, and the tool waited 250 ms and restored the clipboard.
   - **The document stayed empty**, read back through AppleScript: the post was dropped because Accessibility is missing.
   - Restore: all original types came back byte for byte.
   - On the first run, the comparison also flagged `public.utf16-external-plain-text`. That is a *derived* type the original writer serves lazily, and after the restore it becomes a concrete type. It is harmless, but **compare only the originally concrete types**, as the tool now does.
4. **Cleanup.** Closed the document with `saving no`, quit TextEdit (no other documents were open), deleted the test file, and cleared the clipboard back to empty.

**Not verified:**
- the restore delay needed once ⌘V actually lands (250 ms is a guess; too short pastes the old clipboard);
- paste into a terminal, Slack, Chrome or IDEs (that is phase 5 in §9).

## Implications for PLAN.md

**Permissions onboarding list.** These are grants for the assistant's own signed app bundle. Ask for each one just in time, with an explanation, and show its state in Settings.

| # | Permission | Needed for | Required? | Without it |
|---|---|---|---|---|
| 1 | **Microphone** | Wake word and speech (`AVAudioEngine`) | Required | No voice; typing only |
| 2 | **Accessibility** | Window title and selected text (§5.2); ⌘V paste (§5.8); `NSEvent` global monitor or active tap for right ⌥ (§5.5) | Required for "this", Paste and hold-to-talk | "This" loses its title and selection; Paste becomes copy-only ("copied, press ⌘V"); hold-to-talk needs #3 |
| 3 | **Input Monitoring** | Only if right ⌥ uses a listen-only `CGEventTap` instead of the AX-based monitor | Optional (prefer reusing #2) | — |
| 4 | **Automation, per browser** (Safari, Chrome, Brave, Arc…) | Browser URL (§5.2) | Optional; prompted per browser on first use | No URL; use the window title instead |
| 5 | **Screen Recording** | §5.2 click-to-screenshot; also `CGWindowList` window names | Optional (click-only feature) | No screenshot |
| — | None | Call detection, frontmost app, clipboard save/restore | — | — |

**Recommended changes to the plan:**
- §5.8: before offering Paste, the app must check `AXIsProcessTrusted()`. `CGEvent.post` fails silently with no error.
- §5.5, call detection approach (closes the §9 item, apart from the two-voice-processing-apps question):
  - Use CoreAudio process objects. A call is active if any PID other than ours has `kAudioProcessPropertyIsRunningInput == 1`.
  - Event-driven: `prs#` on `kAudioObjectSystemObject`, plus `pdv#` (`kAudioProcessPropertyDevices`) on each process object, then re-read `piri`. **Do not rely on a `piri` listener**: it never fired on macOS 26.6.1.
  - Add a 2–5 s poll as a safety net (about 9 ms wall and 1 ms CPU each) on a background queue.
  - Debounce about 1 s before stopping or restarting the engine. Also allow-list known non-call capturers, using `pbid` (for example `com.apple.CoreSpeech` / dictation, `corespeechd`), so that dictation or Siri doesn't trigger "call mode". Which system daemons capture briefly is `unverified`.
  - When we stop our own engine for a call, our PID drops out of the list. That's fine, because the check excludes self by PID anyway.
- §5.2: send the browser URL from AppleScript with a timeout. The first call per browser can take seconds.

## How to re-run

```sh
cd feasibility/spikes/f07-macos
for f in procaudio micgrab ctx ptt paste pbinfo; do swiftc -O $f.swift -o $f; done

# Step 1: call detection
./procaudio                       # idle listing
./micgrab 12 & sleep 3; ./procaudio --loop 3      # another process capturing
./procaudio --selfmic; (./micgrab 6 &); sleep 2; ./procaudio --selfmic   # self vs other
./procaudio --bench 1000          # poll cost
F07_WILDCARD=1 ./procaudio --listen 12 & sleep 1; ./micgrab 3 3   # listener latency ('pdv#' events)
./procaudio --all                 # every process object with its bundle id

# Step 2: frontmost context
./ctx            # NSWorkspace, AX, CGWindowList
./ctx --url      # adds the browser URL for running browsers (may prompt for Automation)

# Step 3: push-to-talk (after granting Accessibility and/or Input Monitoring to the host app)
./ptt --wait 10  # hold right ⌥ while it runs; expect keycode=61 rightOptDown=true/false

# Step 4: safe paste (TextEdit only)
./paste --selftest
./pbinfo --seed; F=$PWD/f07-target.txt; : > "$F"; open -a TextEdit "$F"; sleep 1
./paste com.apple.TextEdit $'F07 pasted line\n\n'
osascript -e 'tell application id "com.apple.TextEdit" to get text of document 1'
osascript -e 'tell application id "com.apple.TextEdit" to close document 1 saving no'; rm "$F"; ./pbinfo --clear
```

To finish the remaining checks, grant **Accessibility** (and optionally **Input Monitoring**) to the host terminal or app yourself in System Settings › Privacy & Security, then re-run `ctx`, `ptt --wait 10` and the paste step. Watch for the restore delay (`F07_RESTORE_DELAY`, default 0.25 s).

## Addendum (2026-11-17): re-run after granting Accessibility to the Claude app

The spikes run as children of the Claude app, so they inherit its permissions. `AXIsProcessTrusted` and the Input Monitoring and event-posting preflights all return **true**.

| Check | Result |
|---|---|
| Window title (AX) | ✔ e.g. TextEdit `f07-target.txt`, a Brave tab title; about 28–36 ms |
| Selected text, native app (TextEdit) | ✔ **after a fix:** ask the **frontmost app's** element for `AXFocusedUIElement`. The system-wide element returns −25204 (cannotComplete). 0.5 ms. `ctx.swift` updated. |
| Selected text, Chromium/Electron (Brave, Claude app) | ⚠ **unverified.** No focused element is returned (−25212). Setting `AXManualAccessibility` is unsupported in Brave (−25205) and accepted by the Claude app, but neither exposed anything. I couldn't select page text myself, so this is inconclusive. **Fallback:** send ⌘C and read the clipboard, with the same snapshot-and-restore as paste. `axmanual.swift` has the probe. |
| Safe paste into TextEdit | ✔ Cmd-V via CGEvent delivered (54 ms). Trailing newlines stripped, inner and leading ones kept. Every original clipboard type restored (one synthesised type is added, so the snapshot isn't byte-exact). |
| Push-to-talk: shortcut ⌃⌥Space (`RegisterEventHotKey`, `hotkey.swift`) | ✔ **press and release both arrive**: 9 of 9 holds, 0.29–0.82 s. Whether this works **without** Accessibility is still unknown, since it's granted now. |
| Push-to-talk: right ⌥ alone (`ptt --wait 12`) | ✔ both event taps (listen-only and default) saw all 8 down/up pairs of keycode 61. The `NSEvent` global monitor saw **0**, so use a `CGEventTap`. |

**Decision for phase 1:**
- **Default push-to-talk: hold right ⌥.** It's one key, and Accessibility is required anyway for paste, selection and window titles.
- **Alternative in settings: ⌃⌥Space** via `RegisterEventHotKey`.
- Read the selection through the frontmost app's element; for Chromium apps, fall back to a ⌘C copy with clipboard restore.
