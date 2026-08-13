# Breeze SMC Notes — Milestones 1–5

## Scope

`BreezeHardware` remains intentionally read-only: it opens `AppleSMC` as the current user and implements only commands 9 (`readKeyInfo`) and 5 (`readBytes`). Milestones 4–5 add command 6 only inside the root Helper, behind typed automatic-restore and two-fan control whitelists.

Primary validation hardware:

| Model | Chip | Fans | Read | Control |
|---|---|---:|---|---|
| MacBookPro18,3 | Apple M1 Pro | 2 | Verified | Manual and automatic verified |

Unknown Macs may be probed read-only. They are never marked control-capable.

## Selected implementation

Breeze uses a small native Swift wrapper over the AppleSMC IOKit user client:

1. Match the `AppleSMC` service.
2. Open connection type `0` with `IOServiceOpen`.
3. Use selector `2` with an 80-byte `SMCParamStruct`.
4. Fetch key metadata before every value read.
5. Decode Apple Silicon RPM and temperature values as native-endian IEEE-754 floats where the SMC type/size indicates that representation.

This is based on independently published behavior and comparisons with mature open-source implementations, particularly Stats, SMCKit, and macos-smc-fan. The low-level implementation is kept isolated in `BreezeHardware`; SwiftUI never sees SMC keys.

## Fan discovery and readings

| Purpose | Key | Expected Apple Silicon type |
|---|---|---|
| Fan count | `FNum` | `ui8` |
| Actual RPM | `F%dAc` | `flt ` |
| Reported minimum | `F%dMn` | `flt ` |
| Reported maximum | `F%dMx` | `flt ` |

`FNum == 0` is valid and results in an empty fan collection. Missing min/max keys do not invalidate current-RPM monitoring; those individual values become unknown.

Reported minimum and maximum values are observations, not proven physical safety limits. Future write-capable code must not assume that firmware clamps targets to this range.

## Temperature sensors

Apple Silicon sensor names vary by generation and model. For the M1 family, Breeze probes a small catalog of `Tp..` CPU, `Tg..` GPU, and `Tm..` memory keys, then falls back to common keys. It filters non-finite and implausible values outside 10–125 °C. Testing found that an idle/power-gated M1 Pro GPU can expose values around 9.2 °C; Breeze treats those readings as unavailable instead of displaying a misleading temperature.

The UI displays at most one representative reading per category. The CLI exposes every successfully read catalog entry so sensor selection can be validated empirically.

## Manual mode and RPM writes

Milestone 5 implements the M1 direct-control strategy only for `MacBookPro18,3`:

1. Re-read `FNum`, `F#Mn`, `F#Mx`, `F#Md`, and confirm `Ftst` is absent.
2. Reject untrusted bounds; otherwise clamp the integer request to detected min/max.
3. Write mode `1` to the selected fixed `F0Md` or `F1Md` key and allow 350 ms for the asynchronous transition.
4. Encode and write the clamped RPM to fixed `F0Tg` or `F1Tg` from a separate same-signed, root-only fixed worker process. Up to three bounded target attempts tolerate scheduler jitter while mode remains verified.
5. Read both mode and target back, then poll actual RPM until it is within 12% or 150 RPM.
6. On any failure after touching control state, restore both modes and both targets to zero.

On macOS 27.0 beta (`26A5406e`), immediate same-process writes were reclaimed.
A Stats comparison showed that mode and target transactions need separate
process identities on this M1 Pro. Breeze's fixed worker reproduced that
boundary: Fan 0 reached 1471 RPM and Fan 1 reached 1484 RPM with requested and
stored targets of 1400 RPM. Both tests ended with verified automatic modes
`[0,0]`.

The GUI cannot choose keys or mode bytes. Other models, `Ftst`-based strategies, invalid fan IDs, and missing or implausible bounds are rejected before manual writes.

## Automatic control restoration

Implemented in Milestone 4 only for `MacBookPro18,3`. On the tested M1 Pro firmware:

- `F0Md` and `F1Md` are readable one-byte mode keys.
- `Ftst` is absent and returns firmware code 132 during key lookup.
- Writing zero to both mode keys succeeds from the root Helper.
- Re-reading both keys returns mode `0`; mode `3` would also be accepted as Apple system control.
- Twenty-one consecutive restore operations succeeded, while RPM continued to vary under `thermalmonitord`.

On future verified firmware that exposes `Ftst`, Breeze first clears any mode `1` fan and then clears `Ftst`. That branch is unit-tested but is not yet enabled on any additional hardware model.

## Known generational differences

- M1: published tests report direct mode writes on some machines.
- M2: insufficiently verified for Breeze.
- M3/M4: some machines report system mode and require an `Ftst` transition before manual control.
- M5: published tests show lowercase `F%dmd` and no `Ftst` on at least one model.

These observations are research inputs, not Breeze compatibility claims.

## Safety issues to resolve before writes

- [Resolved for MacBookPro18,3] Require detected min/max plus a conservative 1000–7000 RPM sanity envelope.
- [Resolved for MacBookPro18,3] Prove Apple automatic control restoration using state and RPM observations, not only an IOKit success code.
- [Resolved] Use a privileged helper with a narrow XPC protocol and client code-signing validation.
- [Implemented in M6; hardware fault injection pending] Helper-owned 15-second lease, 5-second heartbeat, failed-restore retry, startup recovery, launchd KeepAlive, and root sleep/wake recovery.
- Signed v0.6.1 passed GUI crash/XPC loss, Helper crash/relaunch, sleep/wake, and reboot recovery on real hardware; see `VALIDATION_M6.md`.
- Ensure partial dual-fan operations revert every fan to automatic.

## References

- Apple Service Management documentation: <https://developer.apple.com/documentation/servicemanagement>
- Stats: <https://github.com/exelban/stats>
- macos-smc-fan: <https://github.com/agoodkind/macos-smc-fan>
- iSMC: <https://github.com/dkorunic/iSMC>
