# Breeze Safety Design

Breeze writes undocumented AppleSMC controls, so active fan control is denied unless every required safety condition is known and verified. This document describes the safety boundary through Milestone 8.

Balanced, Cool, and Max remain inside the same boundary. The Helper derives every target from that fan's validated min/max range, preflights both fans before writing, and restores all fans if either application fails.

## Bounds, capability, and write safety

- **Minimum and maximum RPM protection:** the root Helper re-reads each selected fan's hardware minimum and maximum for every request. It rejects missing, non-finite, reversed, or implausible bounds and clamps the requested RPM to the accepted range.
- **Conservative first-write gate:** real-hardware validation began at 1400 RPM, only 200 RPM above the detected 1200 RPM minimum. No maximum-RPM test was used for initial validation.
- **Automatic restore on operation failure:** any failure after entering manual control attempts to restore both fan modes and both target values to automatic/zero.
- **Explicit release paths:** each fan has an Automatic action, the app can restore all fans, and the in-app Quit action terminates only after the Helper read-back confirms automatic control. A failed verification cancels Quit and leaves the app available for recovery.
- **Unknown hardware protection:** manual controls are enabled only for exact model `MacBookPro18,3` with exactly two detected fans and the verified direct-mode firmware strategy. All other configurations are Monitor Only.
- **Privileged Helper isolation:** AppleSMC writes occur only in the signed root Helper. XPC validates the signed peer and exposes fixed operations using only fan ID 0/1 and integer RPM values.
- **SMC write whitelist:** GUI/XPC callers cannot supply SMC keys, raw mode bytes, raw target bytes, executable paths, shell commands, or arbitrary payloads.
- **Write verification:** Breeze reads back manual mode and stored target, then requires actual RPM to converge within a bounded tolerance and time. Automatic operations also read back and verify the resulting mode.
- **Preset transactions:** Balanced uses 35% of each detected range, Cool uses 60%, and Max uses the independently detected maximum. Callers cannot provide preset fractions or targets.
- **No active-mode persistence:** relaunch and wake always begin in Apple Automatic; a previous Manual or preset mode is never resumed automatically.

## Helper-owned lease and crash recovery

- A successful Manual request arms a fixed 15-second lease inside the root Helper.
- The GUI renews the lease every 5 seconds. Callers cannot configure, lengthen, or disable the timeout through XPC.
- Missing heartbeat causes an all-fan Automatic restore. Failure remains armed and retries every 2 seconds until read-back verifies Automatic.
- Heartbeat cannot create a lease after Automatic, preventing a stale GUI from reviving control.
- The Helper restores Automatic unconditionally at startup. Its launchd job uses `RunAtLoad` and `KeepAlive`, so a replacement process recovers state after helper crash and the daemon performs the same recovery after reboot.
- GUI and Helper both observe sleep. Sleep requests Automatic; wake reasserts Automatic and never restores a previous Manual target.

The narrow XPC boundary exposes only fixed preset, heartbeat, lease-status, automatic, and bounded Manual operations. It exposes no arbitrary SMC key, raw bytes, timeout, command, path, or executable input.

## Distribution safety

- The root Helper must be signed consistently with the containing App; both sides enforce code-signing requirements.
- The Helper accepts only the Breeze executable beside it in the same app bundle.
- Local Apple Development builds are for development and hardware validation, not public binary distribution.
- Public binaries require Developer ID signing and Apple notarization. Breeze does not recommend disabling Gatekeeper globally or installing an unsigned root daemon.

## Verified hardware

Write support is currently limited to `MacBookPro18,3`, Apple M1 Pro, with exactly two fans and the verified direct-mode firmware behavior. See [SUPPORTED_MACS.md](SUPPORTED_MACS.md) and the real-hardware records in `docs/VALIDATION_M4.md` through `docs/VALIDATION_M7.md`.
