# Milestone 15 Validation — Automatic Temperature Planning

Validation target: the verified `MacBookPro18,3` two-fan control path, using the hotter CPU/GPU sensor and the existing Helper watchdog.

## Control policy

- At or below 45 °C, the target is 20% of each fan's independently detected range.
- At or above 90 °C, the target is 100%.
- Between those limits, Breeze interpolates through 60 °C/25%, 70 °C/45%, 80 °C/70%, and 85 °C/85%, quantized to 5% steps.
- A rising trend projects up to 3 seconds ahead and caps the planning lead at 5 °C.
- This produces 17 safe targets from 20% through 100%; it is not a four-stage preset policy.
- Balanced, Cool, and Max are independent manual presets and are never used to label Full Automatic decisions.
- Temperature increases apply immediately.
- Decreases require a 2 °C hysteresis and remain stable for 3 seconds.
- An active curve uses one-second monitoring even when Breeze windows are closed.
- The Helper continues to validate the model, fan count, target percentage, fan ranges, writes, and readback before reporting success.

## Automated evidence

- The automatic-planning and AppState suites pass, including nonlinear targets, bounded rise anticipation, watchdog ownership, and default-off resume persistence.
- Policy tests verify 45 °C → 20%, 55 °C → 25%, 70 °C → 45%, and 90 °C → 100%, plus the bounded rise-trend lead.
- Automatic resume is off by default and persists only after explicit user opt-in.
- Automatic is the default profile; Advanced Custom selection persists independently from saved custom points.
- Diagnostic exports record the selected profile and the effective curve rather than an inactive saved custom curve.
- The Xcode app and embedded Helper build for arm64 with minimum macOS 12.0.

## Runtime validation still required

Before treating the new policy as release-ready, run the signed app on the verified M1 Pro Mac and record:

1. Automatic profile activation at a low temperature and its initial fan targets;
2. rising target changes under a sustained CPU/GPU workload;
3. 100% targeting at the upper boundary using a controlled diagnostic test rather than intentionally overheating the Mac;
4. delayed, stable decreases after load ends;
5. watchdog recovery and final Apple Automatic state after disable, quit, sleep, and Helper interruption.
