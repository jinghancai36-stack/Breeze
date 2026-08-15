# Supported Macs

Breeze separates read-only monitoring from write-capable fan control. A model can expose readable sensors without being approved for control.

| Mac | Model identifier | Chip | Fans | Minimum macOS | Read | Control | Status |
| --- | --- | --- | ---: | --- | --- | --- | --- |
| MacBook Pro 14-inch (2021) | `MacBookPro18,3` | Apple M1 Pro | 2 | Monterey 12.0 | Yes | Yes | Tested hardware |

## Status definitions

- **Tested:** monitoring, Manual, Balanced, Cool, Max, Automatic restore, watchdog, sleep/wake, Helper restart, and reboot recovery have real-hardware evidence.
- **Experimental:** read behavior is credible, but the complete control and recovery checklist has not passed.
- **Monitor Only:** Breeze can read available sensors but refuses every fan write.
- **Unknown:** the model has not yet produced a compatibility report.

## Default policy

Every model not listed as Tested is Monitor Only. Matching a marketing name or chip family is not enough to enable writes; Breeze requires the exact hardware identifier, fan count, trustworthy bounds, expected firmware control strategy, and real recovery tests.

Only Apple Silicon Macs are in scope. Breeze is built as an arm64-only app and does not include Intel SMC decoding, UI compatibility, or fan-write paths.

The macOS 12.0 deployment target and Monterey compatibility paths pass automated build validation. Runtime validation on a clean Monterey installation is still required before that OS is marked fully tested.

## Compatibility reports

Reports should include:

- macOS version
- Model identifier and chip name
- Fan count
- Reported minimum, maximum, and idle RPM for each fan
- Whether temperature and fan monitoring remain stable for at least 30 minutes
- Output from `swift run breeze-hardware report`

Do not experiment with SMC writes on an unlisted model. Open an issue with read-only evidence first.
