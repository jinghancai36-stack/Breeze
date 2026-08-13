# Milestone 7 — Presets

Phase 7 adds `Balanced`, `Cool`, and `Max` in that order. Balanced and Cool are validated; Max remains the final gated slice.

## Balanced policy

For each fan independently:

```text
target = minRPM + (maxRPM - minRPM) × 0.35
target = rounded to the nearest 50 RPM
```

Cool uses the identical calculation and transaction with a `0.60` range fraction.

No absolute RPM is hard-coded. The root Helper reads and validates both fan ranges before the first write.

## Safety invariants

- [x] Fixed, argument-free `applyBalancedPreset` XPC operation.
- [x] Verified `MacBookPro18,3`, two fans, M1 direct-mode firmware only.
- [x] Per-fan bounds must stay within the existing 1000–7000 RPM trust envelope.
- [x] Both fans are preflighted before any write.
- [x] A failure on either fan restores all fans to Apple Automatic.
- [x] Successful Balanced control arms the 15-second Helper lease.
- [x] GUI renews the lease every 5 seconds while Balanced is active.
- [x] Quit, sleep, wake, Helper restart, and reboot retain Milestone 6 behavior.
- [x] Active preset mode is never persisted or resumed after wake/relaunch.

## Balanced validation

Balanced passed on the verified Mac. Dynamic targets `[2800,2950]`, converged GUI readings around `[2793–2814,2951]`, repeated heartbeat renewal, timeout fallback, and the transition back to `[0,0]` are recorded in `VALIDATION_M7.md`.

## Cool validation

Cool passed on the verified Mac. Dynamic targets `[3950,4200]`, converged GUI readings around `[3967,4221]`, repeated heartbeat renewal, watchdog timeout fallback, and explicit restoration to Apple Automatic are recorded in `VALIDATION_M7.md`.
