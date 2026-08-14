# Milestone 11 Validation

Date: 2026-08-14

## Scope

- Keep the automatic curve under Breeze control at every temperature while enabled.
- Add a bounded Quiet stage at 20% of each detected fan range.
- Preserve the Helper-owned 15-second watchdog across Quiet, Balanced, Cool, and Max transitions.
- Prevent stale heartbeat replies from corrupting an explicit Apple Automatic restore.

## Automated validation

- Debug and optimized Release test runs pass 70 tests across six suites.
- Quiet policy, privileged transaction, and real XPC transport tests verify independent targets of `[2100, 2200]` RPM on the supported fan ranges.
- Curve tests cover low-temperature ownership, Balanced-to-Quiet re-entry, missing sensor recovery, disable recovery, and a delayed stale-heartbeat race.
- The full release check passes repository audit, property-list validation, static analysis, isolated arm64 Release build, version checks, and strict deep signing verification.
- The validated local artifact is Breeze 0.9.0 build 14 with Helper protocol v0.9.0.

## Hardware validation

Verified on the supported `MacBookPro18,3` development Mac:

- Helper v0.9.0 connected after the signed app and Helper were reloaded.
- Helper startup verified Apple Automatic `[0, 0]` with no active watchdog lease.
- The standalone Quiet diagnostic applied targets `[2100, 2200]` RPM and verified actual readings `[2310, 2401]` RPM.
- With no diagnostic heartbeat, the 15-second Helper timeout restored Apple Automatic `[0, 0]` and disarmed the lease.
- The user enabled the GUI automatic curve. Across two five-second heartbeat boundaries, the Helper remained in controlled modes `[1, 1]` and reported an active lease.
- At a CPU/GPU peak of approximately `57.9 °C`, the curve remained under Breeze control instead of returning to Apple. Balanced correctly remained active until the `52 °C` hysteresis boundary; fan readings were approximately `[2797, 2910]` RPM.
- After the user disabled the curve, Apple Automatic `[0, 0]` was verified, the watchdog was inactive, and fan readings returned to approximately `[2320, 2525]` RPM.

## Safety result

While the curve is enabled, stage transitions are atomic fixed-preset transactions and never create a low-temperature Apple Automatic gap. Explicit disable, quit, sleep, missing temperature data, preset failure, Helper failure, or watchdog loss still restores Apple Automatic. The root Helper continues to accept only fixed preset calls and independently validates the supported model, fan count, and detected RPM bounds.
