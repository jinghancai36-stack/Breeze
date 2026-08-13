# Milestone 4 — Automatic Restore

Milestone 4 introduces Breeze's first and only fan write: returning control to Apple. It does not implement manual mode or target RPM.

## Deliverables

- [x] Root-only AppleSMC write layer isolated in `BreezeHelper`.
- [x] Internal whitelist contains only `F0Md`, `F1Md`, and optional `Ftst`.
- [x] Write API can encode only the value zero.
- [x] `MacBookPro18,3` and exactly two fans are required before writing.
- [x] Unknown mode values are rejected before writing.
- [x] M1 direct-mode path writes both mode keys to zero.
- [x] Optional `Ftst` path restores manual fans before clearing the latch.
- [x] Result is verified by re-reading all available control-state keys.
- [x] XPC exposes only fixed status and restore calls with no input parameters.
- [x] Menu bar and Settings UI expose automatic restore.
- [x] The in-app Quit action restores automatic control before terminating.
- [x] No target RPM or arbitrary SMC write exists.

## Developer diagnostics

```sh
dist/Breeze.app/Contents/MacOS/Breeze --helper-auto-status
dist/Breeze.app/Contents/MacOS/Breeze --helper-restore-auto
```

An automatic state is reported only when every fan mode is `0` or `3` and an available `Ftst` value is `0`. Missing `Ftst` is accepted only through the exact M1 Pro hardware implementation; other models fail the model allowlist first.

## Gate to Milestone 5

Manual fan control remains blocked until it has independent per-model minimum/maximum bounds, clamping, rollback, and live RPM verification. The restore operation is now available as that future rollback primitive.
