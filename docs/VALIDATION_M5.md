# Milestone 5 Validation

Validation target: `MacBookPro18,3`, Apple M1 Pro, two fans.

## Automated evidence

- Hardware tests: 9 passing.
- App/Helper/XPC tests: 34 passing.
- Manual-controller cases cover both-bound clamping, trusted-bound rejection, fixed fan/model rejection, operation order, mode failure, target failure, target readback mismatch, RPM convergence timeout, per-fan automatic reset, and all-fan rollback.
- App-state cases prove Quit terminates only after verified automatic control and remains open when verification fails.
- A real anonymous XPC transport verifies a clamped request and per-fan automatic response across the production protocol.

## Real hardware evidence

Test host: `MacBookPro18,3`, Apple M1 Pro, macOS 27.0 beta (`26A5406e`).

- Fan 0 detected range: 1200–5779 RPM. The first write used 1400 RPM, exactly the required minimum-plus-small-increment test.
- Before the write, both mode keys read automatic: `[0,0]`; `Ftst` was absent.
- Immediate same-process mode/target writes were reclaimed. A Developer-ID-signed Stats 3.0.11 control run proved both fans and macOS 27 still accept the same keys and 1400 RPM target.
- Source and runtime comparison localized the required behavior: allow the asynchronous mode transition to settle, then issue the target from a separate short-lived process. Breeze implements that boundary with a same-signed, root-only fixed worker that accepts only fan 0/1 and an already-clamped RPM; it exposes no key, path, command, or raw bytes over XPC.
- Breeze Fan 0: requested 1400, stored target 1400, actual 1471 RPM, mode manual. Automatic rollback then verified `[0,0]`.
- Breeze Fan 1: requested 1400, stored target 1400, actual 1484 RPM, mode manual. Automatic rollback then verified `[0,0]`.
- Breeze per-fan Automatic: after Fan 0 entered manual mode, the fixed automatic operation waited for the asynchronous mode transition and verified mode `0`; final all-fan status remained `[0,0]`.
- Stats control preferences and module state were restored after comparison. No maximum-RPM test was attempted or required for the first-write safety gate.

The capability gate is enabled only for exact model `MacBookPro18,3` with exactly two detected fans. Every other configuration remains Monitor Only.
