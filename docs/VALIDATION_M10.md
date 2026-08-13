# Milestone 10 Validation

Date: 2026-08-13

## Scope

- Opt-in automatic fan curve driven by the higher CPU/GPU temperature.
- Fixed Balanced, Cool, and Max stages with hysteresis.
- English and Simplified Chinese interface localization.
- A dedicated Fan Curve settings tab with live status and safety documentation.

## Automated validation

- `swift test` passes 66 tests across six suites.
- Curve policy tests cover entry thresholds, descending hysteresis, CPU/GPU peak selection, safe enable/disable, and loss of the controlling temperature source.
- An isolated Release build succeeds with Xcode Beta.
- Xcode compiles `Localizable.xcstrings` into `zh-Hans.lproj/Localizable.strings`.
- The installed local app passes strict deep code-signing verification.

## Hardware validation

Verified on the supported `MacBookPro18,3` development Mac:

- Helper v0.8.0 connected after the signed app and Helper were reloaded.
- Apple automatic control was verified before testing: fan modes `[0, 0]`, with `Ftst` unavailable on this firmware.
- The user enabled the automatic curve, observed normal temperature/stage behavior, disabled it, and confirmed restoration to Apple Automatic.
- The curve remained opt-in and disabled after application relaunch.

## Safety result

The curve reuses only the previously verified fixed preset calls. Enabling first establishes Apple Automatic as a known-safe baseline. Sleep, launch, missing CPU/GPU temperature data, preset failure, Helper failure, or watchdog loss disables the curve and returns control to Apple or leaves recovery to the Helper-owned fixed lease.
