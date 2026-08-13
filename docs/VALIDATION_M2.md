# Milestone 2 Validation

Validated on 2026-08-12 on `MacBookPro18,3` (Apple M1 Pro, arm64), without root.

## Automated checks

- [x] Swift Testing: 14 tests passed (9 hardware, 5 application-state).
- [x] Sleep pauses polling and wake triggers an immediate refresh.
- [x] A failed read preserves the last successful snapshot.
- [x] Visible/background refresh policy and all four menu-bar modes are covered.
- [x] Xcode Debug build succeeded.
- [x] Xcode Release build succeeded and produced `dist/Breeze.app`.

## Bundle checks

- [x] Mach-O architecture: arm64.
- [x] Bundle identifier: `com.cai.Breeze`.
- [x] Version: 0.2.0; minimum macOS: 14.0.
- [x] `LSUIElement = true` (menu-bar app with no Dock icon).
- [x] Strict code-signature verification passed.
- [x] Local ad-hoc signature and Hardened Runtime are enabled.

## Live hardware and runtime checks

- [x] Non-root report detected two fans and 13 thermal sensors.
- [x] Both fans returned live current/minimum/maximum RPM.
- [x] CPU, GPU, memory, and battery readings were credible.
- [x] The menu-bar app stayed alive with the popover closed.
- [x] Background snapshots continued approximately every five seconds.

## Safety audit

- [x] SMC command enum contains only `readKeyInfo` (9) and `readBytes` (5).
- [x] No SMC write command, public write API, privileged helper, or root path exists.

The Settings UI is compile-checked and its state behavior is unit-tested. Direct
menu-bar UI automation was unavailable because the local accessibility bridge
timed out; the already working popover remains the manual visual acceptance gate.
