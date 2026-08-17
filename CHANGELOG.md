# Changelog

All notable Breeze changes are recorded here. Breeze follows semantic versioning for source releases, while build numbers identify local app artifacts.

## [Unreleased]

### Added

- Privacy-bounded hardware diagnostic JSON export and a matching GitHub Apple Silicon model-feedback template.
- Apple Silicon-only macOS 12 Monterey compatibility, matching the factory OS generation of the 2021 M1 Pro MacBook Pro.
- AppKit status-item and window compatibility paths for Monterey, including the existing fan controls and a native draggable curve editor without Swift Charts.
- A fixed administrator-authorized Monterey Helper installer and remover with root ownership, launchd bootstrap, and the existing watchdog/XPC safety boundary.
- Pre-Ventura XPC client signature validation using Security.framework process validation.
- Opt-in CPU/GPU automatic fan curve with fixed preset stages and hysteresis.
- English and Simplified Chinese interface using an Xcode String Catalog.
- Fan Curve settings with current stage, control temperature, thresholds, and safety behavior.
- A native macOS application icon with a cool-blue five-blade fan mark.
- An on-demand Breeze dashboard window with Overview, Cooling, Curves, and Providers sections.
- A bounded Quiet curve stage at 20% of each detected fan range.
- A persistent 2–6 point custom curve editor with safe interpolated insertion, stable deletion, selectable CPU/GPU source, decrease hysteresis, and delay.
- Direct chart-point dragging with safe temperature spacing, monotonic fan targets, and 5% quantization.
- Persistent CPU/GPU temperature and per-fan RPM history charts retaining the latest 300 samples, with an explicit clear-history action.

### Safety

- While enabled, the curve keeps Quiet, Balanced, Cool, and Max under one continuous Helper watchdog lease instead of handing low temperatures back to Apple.
- Curve disable, app quit, sleep, missing temperature data, Helper failure, and watchdog loss still restore Apple Automatic.
- Custom targets are restricted to 20%–100% in 5% steps; the Helper independently converts them to verified per-fan RPM ranges as one transaction.

### Fixed

- Prevented the curve editor from crashing when an inserted point creates a temporarily fixed, zero-width slider range.
- Curve point controls now resolve their current position by stable identity after points are inserted or removed.

### Planned

- Developer ID signing, notarization, and clean-Mac installation testing when the required Apple account is available.

## [0.8.0] — 2026-08-13

### Added

- CPU, GPU, memory, battery, and fan monitoring in a native menu bar interface.
- Apple Automatic, Balanced, Cool, Max, and independently bounded Manual fan controls on the verified `MacBookPro18,3`.
- Privileged Helper with a narrow XPC protocol, peer validation, automatic startup recovery, and a fixed safety lease.
- Automatic recovery on GUI loss, Helper restart, sleep, wake, reboot, failed control, and verified in-app quit.
- Launch at Login, four menu bar display modes, tabbed Settings, hardware support details, and About information.
- Numeric transitions for temperature and RPM readings and reliable Settings-window activation.

### Safety boundary

- Fan writes remain disabled on every model except the explicitly verified two-fan `MacBookPro18,3`.
- A public fan-control binary is not provided without Developer ID signing and notarization.

[Unreleased]: https://github.com/jinghancai36-stack/Breeze/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/jinghancai36-stack/Breeze/releases/tag/v0.8.0
