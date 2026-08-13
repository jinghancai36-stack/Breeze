# Milestone 1 Validation

## Primary hardware

- Model: `MacBookPro18,3`
- Chip: Apple M1 Pro
- Architecture: arm64
- Expected fans: 2

## Acceptance checks

- [x] Project builds with Swift 6.4 / Xcode 27 beta toolchain.
- [x] Unit tests cover float and fixed-point RPM decoding, signed temperature decoding, malformed data, fanless snapshots, and dual-fan snapshots.
- [x] Non-root CLI detects model, chip, architecture, and two fans.
- [x] Non-root CLI reads actual RPM and reported min/max RPM for both fans.
- [x] Non-root CLI reads CPU, GPU, memory, and battery temperature sensors.
- [x] JSON hardware report can be produced.
- [x] 30-minute read-only soak test passes without a read error on the final sensor-filtering code.
- [x] Menu bar executable starts and remains running during a smoke test.
- [x] Source audit finds no SMC write command or public write API.

The remaining boxes are updated only after the corresponding runtime checks complete.

## Initial soak result

Executed on 2026-08-12 with:

```sh
.build/debug/breeze-hardware soak 1800
```

Result:

```text
[1800/1800] fans=2 sensors=13
Soak passed: 1800 samples in 1899.2s; minimum fans=2, minimum sensors=13
```

This run identified a low, power-gated GPU reading that required a filtering correction. A final-code soak is therefore required before completion. No root privileges were used. No fan-control write path exists in this milestone.

## Final-code soak result

After adding power-gated temperature filtering, the full test was repeated:

```text
[1800/1800] fans=2 sensors=13
Soak passed: 1800 samples in 1900.3s; minimum fans=2, minimum sensors=11
```

Both fans were present in every sample. The thermal count varied between 11 and 13 because two GPU readings were correctly omitted whenever their power-gated values fell below the credibility threshold, then returned when valid readings resumed.
