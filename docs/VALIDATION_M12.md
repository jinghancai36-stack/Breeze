# Milestone 12 Validation

Date: 2026-08-14

## Scope

- Replace fixed curve stages with a persistent four-point curve.
- Interpolate bounded fan targets from CPU, GPU, or their peak temperature.
- Keep every curve target under the Helper-owned watchdog.
- Display recent CPU/GPU temperature and per-fan RPM history in the Breeze window.

## Automated validation

- Debug and optimized Release runs pass 77 tests across seven suites.
- Curve tests cover validation, interpolation, 5% quantization, sensor selection, persistence fallback, immediate increases, and delayed hysteretic decreases.
- Helper tests cover the 20%–100% boundary, invalid percentages, independent per-fan RPM conversion, atomic two-fan application, XPC transport, and recovery behavior.
- The full release check passes repository audit, property-list and String Catalog compilation, Xcode static analysis, isolated arm64 Release build, version checks, and strict deep signing verification.
- The validated local artifact is Breeze 0.10.0 build 15 with Helper protocol v0.10.0.

## Hardware validation

Verified on the supported `MacBookPro18,3` development Mac:

- Helper v0.10.0 connected and initially verified Apple Automatic `[0, 0]` with no active watchdog lease.
- The standalone 45% curve diagnostic independently calculated targets `[3250, 3450]` RPM and verified the two-fan transaction with actual readings `[2978, 3244]` RPM.
- The diagnostic armed a 15-second lease and left both fans in controlled modes `[1, 1]` while active.
- With no heartbeat, the Helper timeout restored and verified Apple Automatic `[0, 0]`, then disarmed the watchdog.

## Remaining interactive check

- Confirm the standalone window can edit and save all four points, sensor source, hysteresis, and decrease delay.
- Enable the saved curve, confirm its displayed interpolated target and history charts update, then disable it and verify Apple Automatic.

## Safety result

Custom curve targets use the same Helper-owned lease and recovery path as existing presets. The root Helper accepts only 20%–100% targets in 5% steps, calculates each fan's RPM independently from verified bounds, and applies both fans as one transaction. Explicit disable, quit, sleep, missing temperature data, request failure, Helper failure, or watchdog loss restores Apple Automatic.
