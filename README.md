# Breeze

A lightweight, native fan controller for Apple Silicon Macs.

Breeze is a SwiftUI menu bar app that displays high-value temperatures and fan RPM, provides independently bounded fan controls, and restores Apple Automatic control whenever an active control session ends or becomes unsafe.

> [!WARNING]
> Breeze uses undocumented AppleSMC interfaces. Fan control is enabled only on hardware that has been explicitly tested. All other Macs remain Monitor Only.

## Features

- Native macOS menu bar UI with Light and Dark Mode support
- CPU, GPU, memory, battery, and fan summaries where available
- Automatic, Quiet curve, Balanced, Cool, Max, and per-fan Manual controls
- Full Automatic temperature control with a quiet low-temperature region, stronger cooling above 70 °C, and bounded rise-trend anticipation
- Targets derived from each fan's detected minimum and maximum RPM
- Root Helper with a narrow, typed XPC boundary and strict peer validation
- Fixed 15-second safety lease renewed by the GUI every 5 seconds
- Automatic recovery after GUI crash, XPC loss, Helper restart, sleep, wake, or reboot
- Launch at Login and four menu bar display modes
- English and Simplified Chinese interface, following the macOS app language

## Supported Macs

Full fan control is currently verified only on:

| Model identifier | Chip | Fans | Monitoring | Control | Tested |
| --- | --- | ---: | --- | --- | --- |
| `MacBookPro18,3` | Apple M1 Pro | 2 | Yes | Yes | Yes |

Other Apple Silicon Macs can use monitoring when their sensors are readable, but Breeze does not enable writes on unverified models. Intel Macs are outside the project scope. See [SUPPORTED_MACS.md](SUPPORTED_MACS.md).

## Requirements

- macOS 12 Monterey or newer
- Apple Silicon Mac
- Swift 6.2 / Xcode 26 or newer for development

## Installation status

Breeze does not yet publish a general-purpose binary download. The current build uses an Apple Development identity for local testing. A normal download for other users requires Developer ID signing and Apple notarization.

- **Local development:** fully supported on the verified development Mac.
- **Build from source:** supported for contributors with Xcode and a usable local signing identity.
- **Public binary:** planned after Developer ID signing and notarization are available.
- **Ad-hoc build:** monitoring can work, but the privileged Helper is intentionally unavailable.

Do not disable Gatekeeper globally or install an unsigned root Helper.

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

The script enables Hardened Runtime and uses an available Apple Development certificate for local Helper testing. If no suitable identity exists, it creates an ad-hoc build and clearly warns that privileged control is unavailable.

After opening Breeze, use **Settings → Helper → Install Helper**. On macOS 13 or newer, approve the background item in System Settings when requested. Monterey uses a fixed, administrator-authorized launchd installer and asks for the Mac password once; Breeze never receives or stores that password.

## Interface

The menu bar panel remains intentionally compact: thermal and fan readings appear first, followed by the optional automatic curve, fixed presets, independent Manual controls, Apple Automatic restoration, and visible safety status. A separate on-demand Breeze window provides Overview, Cooling, Curves, and Providers workspaces for richer controls without expanding the menu bar panel. It opens from the small window button in the panel header and stays closed during background login launch.

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

Run the optimized suite before a release candidate:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test -c release
```

## Implementation milestones

### Milestone 2 — Read-only menu bar app

- Standard Xcode macOS app project and `.app` bundle
- Persistent monitoring while the popover is closed
- 1-second popover and 5-second background polling
- Highest credible CPU, GPU, and memory summaries plus explicit battery temperature
- Fan Icon, Temperature, RPM, and Temperature + RPM menu bar modes
- Native Settings window with hardware details
- Launch at Login through `SMAppService.mainApp`
- Sleep/wake polling lifecycle
- Last-good-reading retention and visible stale-state errors

### Milestone 3 — Privileged Helper

- Embedded `BreezeHelper` launch daemon managed by `SMAppService`
- Strict XPC surface containing only `ping` and `getHelperVersion`
- Bidirectional code-signing requirements and expected-client path validation
- Three-second connection timeout and friendly unavailable state
- Helper installation, approval, removal, and connection test in Settings
- Developer diagnostics: `--helper-status`, `--helper-register`, `--helper-ping`, and `--helper-unregister`

### Milestone 4 — Automatic restore

- Supports only the verified `MacBookPro18,3` two-fan configuration
- Reads `F0Md` and `F1Md`, then restores both to automatic mode (`0`)
- Treats `Ftst` as optional because it is absent on the tested M1 Pro firmware
- Re-reads the state and accepts only modes `0` (automatic) or `3` (system)
- Restores automatic control before the in-app Quit action completes
- Exposes no arbitrary key, raw-byte, mode-value, or target-RPM input over XPC
- Developer diagnostics: `--helper-auto-status` and `--helper-restore-auto`

### Milestone 5 — Manual control

- Independent manual sliders for Fan 1 and Fan 2
- Explicit Apply Manual action; moving a slider alone does not write hardware
- Helper re-reads min/max RPM for every request and clamps the target
- Manual mode, target readback, and actual RPM convergence are all verified
- Any write or verification failure immediately restores every fan to Apple automatic
- Per-fan Automatic action and all-fan automatic restore
- Unsupported models, missing/untrusted bounds, unknown modes, and invalid fan IDs remain Monitor Only
- Developer diagnostics: `--helper-set-rpm <fan> <rpm>` and `--helper-set-auto <fan>`; Manual diagnostics require an exact app/Helper version match

### Milestone 6 — Safety watchdog

- Root Helper owns a fixed 15-second manual-control lease; the app renews it every 5 seconds
- Missing heartbeat, GUI crash, Force Quit, or XPC loss restores both fans to Apple Automatic
- Failed timeout restores remain armed and retry every 2 seconds until verification succeeds
- Helper startup always restores Automatic before accepting XPC, covering helper restart and reboot
- Helper removal restores and verifies Automatic first; graceful Helper termination also performs an independent recovery
- launchd `RunAtLoad` and `KeepAlive` ensure a killed Helper is replaced
- Both the GUI and root Helper request Automatic before sleep; wake reasserts Automatic and never resumes Manual
- Developer diagnostics: `--helper-heartbeat` and `--helper-watchdog-status`

### Milestone 7 — Presets

- Balanced is calculated separately for each fan at 35% of its detected min-to-max range
- Targets are rounded to 50 RPM and revalidated by the root Helper before any write
- Both fan bounds are preflighted before the first write
- A failure on either fan restores every fan to Apple Automatic
- Balanced uses the same 5-second heartbeat and 15-second Helper lease as Manual
- Developer diagnostic: `--helper-balanced`
- Cool uses 60% of each independently detected fan range with the same transaction and watchdog guarantees
- Developer diagnostic: `--helper-cool`
- Max uses each fan's independently detected and verified maximum RPM
- Developer diagnostic: `--helper-max`

### Milestone 10 — Automatic curve and localization

- Opt-in automatic curve using the higher of the CPU and GPU temperature
- Fixed stages: Quiet below 60 °C, Balanced at 60 °C, Cool at 75 °C, and Max at 88 °C
- Quiet uses 20% of each fan's independently detected range and remains under the Helper watchdog
- Hysteresis releases Max below 82 °C, Cool below 68 °C, and Balanced back to Quiet at 52 °C
- Stage changes are atomic preset transactions and never hand low-temperature control back to Apple while the curve is enabled
- The curve starts disabled after launch and wake unless the user opts into Full Automatic resume; Helper or watchdog failure still disables it
- English source interface and a Simplified Chinese String Catalog
- The interface follows the language selected for Breeze in macOS
- Developer diagnostic: `--helper-quiet`

### Milestone 11 — Continuous watchdog curve

- Quiet, Balanced, Cool, and Max remain under one continuous Helper watchdog lease while the curve is enabled
- Quiet is calculated independently at 20% of each detected fan range
- Low temperatures no longer hand control back to Apple, preventing the curve from becoming inactive before a later temperature rise
- Explicit disable and every safety exit still restore Apple Automatic
- Automated and supported-hardware results are recorded in [Milestone 11 Validation](docs/VALIDATION_M11.md)

### Milestone 12 — Custom curves and history

- Persistent four-point temperature-to-fan curve edited in the standalone Breeze window
- CPU/GPU Peak, CPU-only, and GPU-only control sources
- Linear interpolation quantized to bounded 5% targets, with immediate increases and configurable decrease hysteresis/delay
- The Helper accepts only 20%–100% curve targets and independently converts them to each fan's verified RPM range as one atomic transaction
- In-memory CPU/GPU temperature and per-fan RPM charts retain the latest 300 monitoring samples
- Developer diagnostic: `--helper-curve <20...100, step 5>`
- Automated and supported-hardware results are recorded in [Milestone 12 Validation](docs/VALIDATION_M12.md)

### Milestone 13 — Dynamic points and persistent history

- Curves support 2–6 points with stable identities and safe add/remove controls
- New points are inserted into the largest available temperature span and inherit the existing interpolated 5% target
- The latest 300 CPU/GPU and per-fan RPM samples persist across app restarts
- History is validated on restore, saved in batches to limit disk writes, and can be explicitly cleared from the Overview page

### Milestone 15 — Automatic temperature planning

- Breeze Full Automatic is the default curve profile; no point editing is required
- The hotter CPU/GPU reading follows a quiet-to-aggressive plan: 45/20%, 60/25%, 70/45%, 80/70%, 85/85%, and 90/100%
- Output has 17 safe targets (20%, 25%, …, 100%) instead of four temperature stages or one fixed preset RPM
- Balanced, Cool, and Max remain separate controls that run only when the user explicitly selects those fixed presets
- A rapid temperature rise can lead the planning temperature by at most 5 °C for earlier cooling without exceeding the same bounded curve
- Rising temperatures apply immediately; decreases use a 2 °C hysteresis and 3-second delay
- Active temperature control keeps one-second hardware polling even with Breeze windows closed
- Optional Full Automatic resume is off by default and can be enabled for login and wake
- Existing custom points remain available under **Advanced Custom** and are not deleted by migration
- Automated results are recorded in [Milestone 15 Validation](docs/VALIDATION_M15.md)

### Hardware model feedback

Open **Settings → Hardware → Export Diagnostic Report…** to save a structured JSON report, then choose **Open Model Feedback** to attach it to the matching GitHub issue form. The exporter includes Breeze/macOS versions, model and chip details, fan readings and ranges, temperature sensors, Helper state, and curve configuration. It deliberately excludes serial numbers, hostnames, usernames, filesystem paths, logs, credentials, certificates, and signing identities.

Diagnostic reports are read-only evidence. They do not enable fan writes or bypass the verified-model whitelist.

## Safety

Breeze uses undocumented/private hardware interfaces. Availability varies between Mac models and macOS versions. The helper runs as root only after explicit macOS approval. Manual control is restricted to a per-model and per-fan whitelist and never bypasses detected RPM bounds. A Helper-owned lease restores Automatic when the controlling GUI disappears; explicit Automatic and Quit remain the preferred release paths.

See [SAFETY.md](SAFETY.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/SMC_NOTES.md](docs/SMC_NOTES.md), and the milestone validation records under [docs](docs).

## Source release and recovery

The local release gate validates the repository, Debug and optimized tests, property lists, static analysis, an isolated Release build, version consistency, arm64 architecture, and local code signing:

```sh
./scripts/release-check.sh
```

From a clean commit, create a source-only archive and SHA-256 checksum with:

```sh
./scripts/package-source.sh
```

Read [Installation and Recovery](docs/INSTALLATION_AND_RECOVERY.md) before installing or removing the Helper. See [CHANGELOG.md](CHANGELOG.md), [SECURITY.md](SECURITY.md), and the [v0.12.0 release notes](docs/releases/v0.12.0.md) for publication details.

## Contributing

Compatibility reports, documentation, UI improvements, and tests are welcome. Changes to SMC writes, Helper security, fan bounds, or recovery behavior require additional safety evidence. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

MIT
