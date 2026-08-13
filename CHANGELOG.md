# Changelog

All notable Breeze changes are recorded here. Breeze follows semantic versioning for source releases, while build numbers identify local app artifacts.

## [Unreleased]

### Added

- Opt-in CPU/GPU automatic fan curve with fixed preset stages and hysteresis.
- English and Simplified Chinese interface using an Xcode String Catalog.
- Fan Curve settings with current stage, control temperature, thresholds, and safety behavior.

### Safety

- The curve first restores Apple Automatic, starts disabled after launch and wake, and cancels itself after Helper or watchdog failure.

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
