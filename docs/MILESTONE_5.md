# Milestone 5 — Manual Fan Control

Milestone 5 adds bounded, independently selectable manual fan targets to the single verified hardware model. It does not add presets or the Phase 6 watchdog.

## Deliverables

- [x] Fixed `VerifiedFan` whitelist contains only fan 0 and fan 1.
- [x] Root Helper independently reads minimum and maximum RPM on every request.
- [x] Requests below minimum or above maximum are clamped before encoding.
- [x] Missing, non-finite, zero/low, reversed, or implausibly high bounds disable manual mode.
- [x] Only the verified `MacBookPro18,3` two-fan M1 direct strategy is accepted.
- [x] Manual mode is verified after a bounded settle; target is written by a fixed root worker, then both values are read back.
- [x] Target RPM is encoded as an Apple Silicon native-endian float and read back.
- [x] Actual RPM must converge within 12% or 150 RPM within 15 seconds.
- [x] Mode, target, readback, or convergence failure immediately invokes all-fan automatic restore.
- [x] Per-fan automatic mode clears its target; all-fan restore clears both targets.
- [x] Quit terminates only after automatic mode is read back as verified; a failed restore keeps the app open.
- [x] XPC accepts only fixed fan/RPM operations and primitive values.
- [x] Full-range per-fan sliders require an explicit Apply Manual click.
- [x] Successful all-fan restore clears stale Manual UI state; Helper/restore failures remain visible in the popover.
- [x] Unsupported hardware remains Monitor Only.
- [x] First real write uses only detected minimum plus a small increment.
- [x] Requested, stored target, and current RPM relationship is verified on hardware.
- [x] Both fans return to Apple automatic mode after the test.

On macOS 27.0 beta build `26A5406e`, immediate same-process writes were
reclaimed. Runtime comparison with Stats established the required asynchronous
mode-settle and separate-process target transaction. With that bounded worker,
Breeze verified Fan 0 at 1471 RPM and Fan 1 at 1484 RPM for a stored 1400 RPM
target, then restored and verified modes `[0,0]`; see `VALIDATION_M5.md`.

## Developer diagnostics

```sh
dist/Breeze.app/Contents/MacOS/Breeze --helper-set-rpm 0 1400
dist/Breeze.app/Contents/MacOS/Breeze --helper-set-auto 0
dist/Breeze.app/Contents/MacOS/Breeze --helper-restore-auto
```

The diagnostic reports requested RPM, applied/clamped RPM, observed RPM, detected range, resulting mode, and whether a failure triggered rollback.

## Follow-up delivered in Milestone 6

Milestone 5 itself relied on explicit Automatic/Restore/Quit actions. The Helper lease, heartbeat timeout, helper-startup recovery, and sleep/wake safety work are implemented and tracked in `MILESTONE_6.md`.
