# Milestone 8 Validation

Validation target: `MacBookPro18,3`, Apple M1 Pro, macOS 26 development environment.

## Automated evidence — 2026-08-13

- Debug and optimized Release suites each pass 9 hardware tests and 63 App/Helper tests.
- Xcode Release static analysis succeeds.
- v0.8.0 build 13 succeeds; app and embedded Helper pass strict deep code-signing verification.
- App and launch-daemon property lists pass validation.
- Installed Helper v0.8.0 starts by restoring and verifying Apple Automatic `[0,0]`; its watchdog is inactive.
- A five-minute final-code soak passes 300/300 read-only samples in 314.9 seconds with two fans and 13 sensors in every sample.
- Apple Automatic remains verified after the soak; no active fan-control request was made during Phase 8 validation.

## Visual evidence

- [x] Menu bar panel review in the current system appearance.
- [x] Settings General, Hardware, Helper, and About tab review, including Version 0.8.0 and Build 13.
- [x] Repeated Settings click raises an already-open Settings window, and current/target RPM values animate smoothly.
- [ ] Multiline error-card and Check Safety/Retry behavior review when an error is naturally present.

Computer Use cannot acquire an accessibility state for this accessory-only `MenuBarExtra` process, so visual acceptance remains a user-observed gate rather than an automated click-through.
