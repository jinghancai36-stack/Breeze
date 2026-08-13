# Milestone 7 Validation

Validation target: `MacBookPro18,3`, Apple M1 Pro, two fans.

## Balanced automated evidence

- Debug and optimized Release suites each pass 9 hardware tests and 57 App/Helper tests.
- Preset policy tests verify independent min/max calculation, 50 RPM rounding, and untrusted-bound rejection.
- Controller tests verify both-fan preflight, two-fan success, and all-fan rollback when Fan 2 fails.
- Real anonymous XPC proves Balanced controls both fans and arms the Helper lease.
- App-state tests prove Balanced starts heartbeats and a failed/uncertain request never renews a lease.
- Xcode Release static analysis, plist validation, and deep code-signing verification pass.

## Balanced real hardware evidence — 2026-08-12

- Installed Helper v0.7.0; startup recovery verified `[0,0]`.
- Fixed diagnostic calculated targets `[2800,2950]` from detected ranges `[1200,5779]` and `[1200,6241]`.
- Stable read-only observation reached approximately `[2820,2952]` RPM.
- With no continuing client heartbeat, the 15-second lease expired and restored `[0,0]`.
- GUI Balanced reached approximately Fan 1 `2793–2814` RPM and Fan 2 `2951` RPM.
- Two observations six seconds apart both showed a freshly renewed lease, proving GUI heartbeat continuity.
- **Restore All to Apple Automatic** disarmed the lease and verified `[0,0]`.

## Cool automated evidence

- Debug and optimized Release suites each pass 9 hardware tests and 60 App/Helper tests.
- Policy and controller tests verify the independent 60% range calculation, two-fan transaction, verification, and rollback guarantees.
- XPC tests prove the fixed argument-free operation controls both fans and arms the Helper lease.
- App-state tests prove Cool publishes its targets, enters the correct active mode, and renews the safety lease.

## Cool real hardware evidence — 2026-08-13

- Installed Helper v0.7.1; startup recovery verified `[0,0]`.
- Fixed diagnostic calculated targets `[3950,4200]` and converged to approximately `[3917,4185]` RPM.
- With no continuing client heartbeat, the 15-second lease expired and restored `[0,0]`.
- GUI Cool stabilized at `[3967,4221]` RPM.
- Two observations six seconds apart showed freshly renewed leases, proving GUI heartbeat continuity.
- **Apple Automatic** disarmed the lease; the Helper reported `Apple automatic control verified`.

Balanced and Cool are fully validated. Max remains gated behind these two lower presets.
