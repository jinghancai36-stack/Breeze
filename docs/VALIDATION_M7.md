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

## Max automated evidence

- Debug and optimized Release suites each pass 9 hardware tests and 63 App/Helper tests.
- Policy tests prove Max resolves to each fan's independently verified maximum: `[5779,6241]` on the validation fixture.
- Controller and XPC tests prove the two-fan transaction and Helper lease activation.
- App-state tests prove Max publishes the verified targets, enters the Max mode, and starts the safety heartbeat.
- Xcode Release static analysis, plist validation, and deep code-signing verification pass for v0.7.2 build 10.

## Max real hardware evidence — 2026-08-13

- Installed Helper v0.7.2; startup recovery verified `[0,0]` with no active lease.
- Fixed diagnostic requested `[5779,6241]`; stable read-only observation reached approximately `[5786,6278]` RPM.
- With no continuing client heartbeat, the 15-second lease expired, restored `[0,0]`, and RPM returned to approximately `[2331,2486]`.
- GUI Max produced repeated readings around Fan 1 `5787–5812` RPM and Fan 2 `6222–6279` RPM.
- Two observations six seconds apart showed freshly renewed leases with 13–14 seconds remaining, proving GUI heartbeat continuity.
- **Apple Automatic** disarmed the lease, verified `[0,0]`, and RPM returned to approximately `[2344,2517]`.

Balanced, Cool, and Max are fully validated. Milestone 7 is complete on `MacBookPro18,3`.
