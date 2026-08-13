# Milestone 4 Validation

Validated on 2026-08-12 on `MacBookPro18,3` with Apple M1 Pro and two fans.

## Automated validation

- Swift Testing: 27 tests passed (9 hardware and 18 App/Helper/XPC).
- Restore tests cover automatic state, manual restore order, partial write failure, absent `Ftst`, unknown model, wrong fan count, and unknown mode.
- A real anonymous XPC transport carried status and restore replies across the exact production protocol.
- Xcode Debug and Release builds succeeded.
- `codesign --verify --deep --strict` passed.
- App and Helper are Apple Development-signed with Team ID `576G9DGV27` and Hardened Runtime.

## Real root Helper and SMC validation

```text
Helper registration: enabled
Helper connected: v0.4.0
Helper process owner: root
thermalmonitord process owner: root

Before: Apple automatic control is active. modes=[0,0] Ftst=n/a
Restore: Apple automatic control restored and verified. modes=[0,0] Ftst=n/a
After:  Apple automatic control is active. modes=[0,0] Ftst=n/a
```

The first restore plus 20 consecutive repeats all succeeded. Fan observations remained dynamic:

```text
Before: Fan 0 2382 RPM; Fan 1 2555 RPM
After:  Fan 0 2398 RPM; Fan 1 2559 RPM
```

This verifies the IOKit write result, the resulting SMC mode state, and continued Apple thermal-daemon ownership rather than relying on a command return code alone.

## Security audit

- Exported XPC operations are exactly `ping`, `getHelperVersion`, `getAutomaticControlStatus`, and `restoreAutomaticControl`.
- Automatic-control operations accept no arguments.
- The GUI cannot provide an SMC key, byte value, mode, fan index, RPM, command, path, or shell input.
- The Helper write method accepts an internal enum and always writes a zero byte.
- Unsupported models, non-root execution, unexpected fan count, and unknown modes fail before writes.
- No `F%dTg`, target-RPM, or manual-control code exists in the Helper.
