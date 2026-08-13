# Breeze

A lightweight, native fan-controller foundation for Apple Silicon Macs.

Breeze discovers fans, reads current/reported min/max RPM, and presents high-value thermal summaries in a native SwiftUI menu bar app. Milestone 7 adds the first dynamically calculated preset on top of the Helper-owned safety lease for the verified `MacBookPro18,3` M1 Pro model. Other hardware remains Monitor Only.

## Requirements

- macOS 14 or newer
- Apple Silicon Mac
- Swift 6.2 / Xcode 26 or newer for development

## Open and run in Xcode

1. Open `Breeze.xcodeproj`.
2. Select the `Breeze` scheme and `My Mac` destination.
3. Press `⌘R` to run. `⌘B` only builds.
4. Find Breeze in the macOS menu bar; it intentionally has no Dock icon.

## Build a double-clickable app

```sh
./scripts/build-app.sh
open dist/Breeze.app
```

The build script uses an available Apple Development certificate for local Helper testing and enables Hardened Runtime. Local Helper registration is verified with that identity on the development Mac. A side-loaded download for other users requires an appropriate Developer ID signing/notarization or a separate user-driven installation workflow; an ad-hoc build remains read-only because macOS will not launch its root Helper through this design.

## Diagnostic CLI

```sh
swift run breeze-hardware info
swift run breeze-hardware fans
swift run breeze-hardware temperatures
swift run breeze-hardware watch
swift run breeze-hardware soak 1800
```

## Test

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

Using the full Xcode toolchain is required because the Command Line Tools-only
selection does not contain the macOS XCTest framework.

## Milestone 2 features

- Standard Xcode macOS app project and `.app` bundle
- Persistent monitoring while the popover is closed
- 1-second popover and 5-second background polling
- Highest credible CPU, GPU, and memory summaries plus explicit battery temperature
- Fan Icon, Temperature, RPM, and Temperature + RPM menu bar modes
- Native Settings window with hardware details
- Launch at Login through `SMAppService.mainApp`
- Sleep/wake polling lifecycle
- Last-good-reading retention and visible stale-state errors

## Milestone 3 helper

- Embedded `BreezeHelper` launch daemon managed by `SMAppService`
- Strict XPC surface containing only `ping` and `getHelperVersion`
- Bidirectional code-signing requirements and expected-client path validation
- Three-second connection timeout and friendly unavailable state
- Helper installation, approval, removal, and connection test in Settings
- Developer diagnostics: `--helper-status`, `--helper-register`, `--helper-ping`, and `--helper-unregister`

## Milestone 4 automatic restore

- Supports only the verified `MacBookPro18,3` two-fan configuration
- Reads `F0Md` and `F1Md`, then restores both to automatic mode (`0`)
- Treats `Ftst` as optional because it is absent on the tested M1 Pro firmware
- Re-reads the state and accepts only modes `0` (automatic) or `3` (system)
- Restores automatic control before the in-app Quit action completes
- Exposes no arbitrary key, raw-byte, mode-value, or target-RPM input over XPC
- Developer diagnostics: `--helper-auto-status` and `--helper-restore-auto`

## Milestone 5 manual control

- Independent manual sliders for Fan 1 and Fan 2
- Explicit Apply Manual action; moving a slider alone does not write hardware
- Helper re-reads min/max RPM for every request and clamps the target
- Manual mode, target readback, and actual RPM convergence are all verified
- Any write or verification failure immediately restores every fan to Apple automatic
- Per-fan Automatic action and all-fan automatic restore
- Unsupported models, missing/untrusted bounds, unknown modes, and invalid fan IDs remain Monitor Only
- Developer diagnostics: `--helper-set-rpm <fan> <rpm>` and `--helper-set-auto <fan>`; Manual diagnostics require an exact app/Helper version match

## Milestone 6 safety watchdog

- Root Helper owns a fixed 15-second manual-control lease; the app renews it every 5 seconds
- Missing heartbeat, GUI crash, Force Quit, or XPC loss restores both fans to Apple Automatic
- Failed timeout restores remain armed and retry every 2 seconds until verification succeeds
- Helper startup always restores Automatic before accepting XPC, covering helper restart and reboot
- Helper removal restores and verifies Automatic first; graceful Helper termination also performs an independent recovery
- launchd `RunAtLoad` and `KeepAlive` ensure a killed Helper is replaced
- Both the GUI and root Helper request Automatic before sleep; wake reasserts Automatic and never resumes Manual
- Developer diagnostics: `--helper-heartbeat` and `--helper-watchdog-status`

## Milestone 7 presets

- Balanced is calculated separately for each fan at 35% of its detected min-to-max range
- Targets are rounded to 50 RPM and revalidated by the root Helper before any write
- Both fan bounds are preflighted before the first write
- A failure on either fan restores every fan to Apple Automatic
- Balanced uses the same 5-second heartbeat and 15-second Helper lease as Manual
- Developer diagnostic: `--helper-balanced`
- Cool uses 60% of each independently detected fan range with the same transaction and watchdog guarantees
- Developer diagnostic: `--helper-cool`

## Safety

Breeze uses undocumented/private hardware interfaces. Availability varies between Mac models and macOS versions. The helper runs as root only after explicit macOS approval. Manual control is restricted to a per-model and per-fan whitelist and never bypasses detected RPM bounds. A Helper-owned lease restores Automatic when the controlling GUI disappears; explicit Automatic and Quit remain the preferred release paths.

See [SAFETY.md](SAFETY.md), [docs/SMC_NOTES.md](docs/SMC_NOTES.md), [docs/MILESTONE_6.md](docs/MILESTONE_6.md), [docs/VALIDATION_M6.md](docs/VALIDATION_M6.md), and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## License

MIT
