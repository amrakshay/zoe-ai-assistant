# F06: Rive character in a floating transparent panel

**Test id:** F06 · **Date:** 2026-11-16 · **Plan:** PLAN.md rev 5 (§2, §2.1, §5.11, §7 "Character spec")
**Spike:** `feasibility/spikes/f06-rive/`

## Verdict: PASS (with three caveats)

RiveRuntime 6.30.1 resolves and builds with SwiftPM and the **Command Line Tools only, without Xcode**. It renders a Rive state machine in a borderless, non-activating, clear, floating, all-Spaces `NSPanel`. Areas with no artboard background are truly transparent: 90.6 % of the captured window's pixels have alpha 0. Setting a number input from code changed the state (callback logged). `setPreferredFramesPerSecond` holds 30 and 10 fps exactly.

Measured cost on this machine:

| Mode | CPU (one core) |
|---|---|
| Default (120 fps on ProMotion) | 10–13 % |
| 30 fps | about 4 % |
| 10 fps | about 2 % |
| Paused | 0 % |

RSS is 42–53 MB with Rive and 32–35 MB without it.

**Caveats:**
1. **Memory budget.** While Rive animates, the physical footprint (`footprint`, which counts Metal/IOSurface memory) is **about 126 MB**. That is over the §2.1 "App memory, idle ≤ 80 MB" budget on its own. It drops to **25 MB when paused**.
2. **Idle CPU.** At 10 fps, Rive alone uses about 2 % CPU. That already equals the whole "CPU, idle ≤ 2 % app + core" budget.
3. **Dragging is unverified.** Synthetic mouse events were blocked (no Accessibility permission), so dragging was not tested with real input (see below).

## Environment
- macOS 26.6.1 (Darwin 25.6.0), Apple Silicon. Main display 3024×1964 Retina, ProMotion (120 Hz); second display 1080p.
- Swift 6.2 (swiftlang-6.2.0.19.9), `xcode-select -p` = `/Library/Developer/CommandLineTools`. Xcode is not installed.
- RiveRuntime **6.30.1** (latest tag on 2026-11-16) from `https://github.com/rive-app/rive-ios`, MIT.
- The machine was not idle during the runs: WindowServer used 7–47 % over the same windows, driven by other apps. Process CPU was measured per process, so it is not affected by that.

## Results

### Build
| Check | Result |
|---|---|
| `swift package resolve` | OK. Clone plus a 145 MB binary download `RiveRuntime.xcframework.zip` (about 2 min cold). |
| `swift build -c release` with CLT only | **OK**: first build 103 s, incremental builds about 2 s. The xcframework contains `macos-arm64_x86_64`. |
| Output | Executable 126 KB, plus `RiveRuntime.framework` 15 MB copied next to it (`@rpath` → `@loader_path`). An app bundle must embed this framework. |
| API status | The whole `RiveViewModel` / `RiveModel` / state machine input / delegate API used here is marked **deprecated** in 6.30. It still works, but Rive points to its newer "concurrency runtime" (`Rive`, `File`, `StateMachine`, async) and to **Data Binding** in place of state machine inputs. The newer API was not tried. |

### Asset
Official samples from `rive-ios/Example-iOS/Assets` (repo licence MIT; the artwork's own licence is not stated separately, so it is **unverified for reuse beyond testing**). They are copied to `spikes/f06-rive/assets/` along with the MIT licence file. I listed the state machines and inputs of all 70+ samples with `RiveSpike --list`. The ones used:

| File | Artboard | State machine | Inputs | Background |
|---|---|---|---|---|
| `lip-sync_test.riv` (607 KB) | `Mouth` 500×500 | `State Machine 1` | `numViseme: number` | **transparent** |
| `marty_v2.riv` (31 KB) | `New Artboard` 800×800 | `State Machine 1` | none (continuous idle loop) | opaque gradient |

Other usable samples: `neostream.riv` `Character_animation` (`isLoaded: bool`, `Flame Hover: number`, `isDucking: trigger`; white background) and `rating_animation.riv` (`rating: number`).

**Finding:** transparency depends on the artwork. The panel and Rive's Metal layer are transparent, but artboards with a background fill (marty, neostream) render as an opaque square. The plan's character must have **no artboard background fill**.

### Window
The panel is set up as `NSPanel([.borderless, .nonactivatingPanel])` with:
- `isOpaque=false`, `backgroundColor=.clear`, `hasShadow=false`
- `level=.floating` (logged as 3)
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` (logged raw value 337)
- `isMovableByWindowBackground=true`
- the `RiveView` from `RiveViewModel.createRiveView()`, 240×240 pt

The app runs as an `.accessory` activation policy (no Dock icon). Logs confirm each property. Showing on all Spaces and over full-screen apps is **configured but not checked visually** (I didn't switch Spaces).

### Driving the state machine
`input-test.log` (also seen in `results/shot.log`):
```
[  0.07s] STATE State Machine 1 -> Newtral
[  2.16s] SET number numViseme: 0.0 -> 3.0
[  2.16s] STATE State Machine 1 -> L
```
The value was read back from `RiveSMINumber`, and the state change arrived through `stateMachine(_:didChangeState:)`. The "talk" runs also cycled `numViseme` 0–12 every 120 ms through a timer.

### Dragging: unverified
- A synthetic `CGEvent` drag was dropped: the cursor did not move, because the posting process lacks Accessibility permission.
- A hit test at the panel centre returns `RiveView` with `mouseDownCanMoveWindow=true`. But `RiveView` overrides `mouseDown` (it forwards pointer events to the state machine), so background-drag may not trigger. **Not verified.**
- The spike includes a fallback, `--drag-overlay`: a transparent `NSView` above the `RiveView` that calls `window.performDrag(with:)`. Its hit test returns the overlay. That fallback is also **not verified with real input**.
- **Manual check (10 s):** run the re-run command below and drag the mouth, with and without `--drag-overlay`. `MOVED frame=…` lines in stdout confirm a move.

### CPU and RSS (35 s runs; CPU = process CPU time over t=5–35 s; RSS = mean of 30 one-second samples; footprint from `footprint -p` at t=30 s; fps counted from Rive advance callbacks)

| Run | fps setting | Measured fps | CPU % (1 core) | RSS mean / max (MB) | Phys footprint |
|---|---|---|---|---|---|
| **Rive, marty** (continuous idle loop) | default | 119.6 | **10.5** | 51 / 51 | 127 MB |
| | 30 | 29.9 | **4.1** | 42 / 51 | 126 MB |
| | 10 | 9.8 | **1.8** | 50 / 51 | 126 MB |
| | paused | 0.0 | **0.0** | 51 / 51 | **25 MB** |
| **Rive, mouth "talking"** (transparent, input changed every 120 ms) | default | 119.8 | **12.7** | 52 / 53 | 128 MB |
| | 30 | 30.0 | **4.2** | 52 / 52 | 126 MB |
| | 10 | 9.9 | **2.1** | 44 / 44 | 126 MB |
| | paused | 0.0 | **0.0** | 52 / 52 | **25 MB** |
| **Baseline, no Rive** (same panel, CAShapeLayer circle) | CA animation (render server) | n/a | 0.0 | 34 / 35 | 9.3 MB |
| | app timer 30 Hz | n/a | 0.3 | 32 / 35 | 9.5 MB |
| | app timer 10 Hz | n/a | 0.13 | 33 / 35 | 9.5 MB |
| | static | n/a | 0.0 | 35 / 35 | 9.2 MB |

Notes:
- Rive with no fps setting runs at the display's refresh rate (120 Hz here). **Always set the fps explicitly.**
- **What Rive adds:** about +15–20 MB RSS, and about +115 MB physical footprint while animating (Metal resources; not broken down further). Pausing releases most of it (25 MB vs 9 MB baseline).
- WindowServer compositing cost is not attributed here; it was too noisy because of other apps on the machine.
- The panel is 240×240 pt (480×480 px). A larger panel would likely raise both CPU and footprint (unverified).

## Screenshot
- `feasibility/spikes/f06-rive/shot.png`: raw `screencapture -o -l <window>` of the Rive panel (lip-sync `Mouth`, `numViseme=3`), 480×480 px with alpha: 90.6 % fully transparent, 9.1 % opaque, 0.3 % partial (anti-aliasing).
- `feasibility/spikes/f06-rive/shot-on-checker.png`: the same image composited on a checkerboard, so the transparency is visible.
- `screencapture` worked without a prompt; Screen Recording permission was already granted to the host terminal.

## Implications for PLAN.md
- **Rive stays.** It builds without Xcode, renders transparently in the planned panel, accepts number inputs from code, reports state changes, and its frame rate is controllable.
- **Xcode is not needed** to build or run with Rive. SwiftPM + CLT is enough. Bundling the 15 MB `RiveRuntime.framework` into a `.app`, plus signing and notarisation, was not tested here (separate concern).
- **fps policy (§2.1 "How we get there"):** keep it, and tighten it:
  - Always call `setPreferredFramesPerSecond`. The default is 120 fps on ProMotion and costs about 11–13 % CPU.
  - Active (listening/speaking): **30 fps**, about 4 % CPU.
  - Idle-visible: **10 fps**, about 2 % CPU. That alone uses the whole idle CPU budget, so a better idle policy is to **pause Rive when idle and show a static last frame, or wake it for short occasional "breath" animations**. That gives 0 % CPU and 25 MB footprint.
  - Pause when hidden, covered, muted or on another Space, as planned.
- **Memory budget (§2.1 "App memory, idle ≤ 80 MB"):** clarify which metric it means. With RSS, an animating Rive app fits (about 52 MB before audio/ONNX). With physical footprint (what Activity Monitor shows as "Memory"), an animating Rive panel alone is about 126 MB. A paused Rive panel is 25 MB. **Pausing at idle is what makes the 80 MB footprint budget reachable.**
- **Character spec (§7):** the inputs `state`, `audioLevel`, `hover`, `muted`, `needsInput`, `quiet` map onto state machine inputs, which work. However:
  1. Rive 6.30 deprecates state machine inputs in favour of **Data Binding** (view-model properties). The spec should allow either, or target Data Binding for a new character (not tested here).
  2. The character's artboard must have **no background fill**, or it renders as an opaque square.
  3. `audioLevel` driven every 120 ms worked at 30 fps (the "mouth talk" runs).
- **Drag:** dragging by `isMovableByWindowBackground` over a `RiveView` is unverified. Plan on an explicit overlay with `performDrag(with:)`, or on handling drag in the host view. The app then sets `hover` itself, since Rive's own pointer events are blocked.

## How to re-run
```sh
cd feasibility/spikes/f06-rive
swift build -c release                      # first run downloads RiveRuntime 6.30.1 (~145 MB)
B=.build/release

# list state machines and inputs of any .riv
$B/RiveSpike --list assets/lip-sync_test.riv

# show the panel for 30 s, drive an input at t=2 s (logs SET and STATE lines; drag it and look for MOVED)
$B/RiveSpike --riv assets/lip-sync_test.riv --artboard Mouth --sm "State Machine 1" \
  --set numViseme=3 --set-at 2 [--fps 30] [--paused] [--drag-overlay] [--cycle numViseme:12:120]

# measurement matrix (35 s per run; appends to results/summary.txt)
./measure.sh mouth-talk-fps30 $B/RiveSpike --riv assets/lip-sync_test.riv --artboard Mouth \
  --sm "State Machine 1" --cycle numViseme:12:120 --fps 30
./measure.sh marty-fps10 $B/RiveSpike --riv assets/marty_v2.riv --sm "State Machine 1" --fps 10
./measure.sh baseline-timer-30 $B/BaselineSpike --timer 30

# transparency check of a capture
swift tools/pngstat.swift shot.png shot-on-checker.png
```
Every process closes its panel and exits after `--duration` seconds (default 30). Raw logs are in `results/`.
