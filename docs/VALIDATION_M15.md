# Milestone 15 Validation — Automatic Temperature Planning

Validation target: the verified `MacBookPro18,3` two-fan control path, using the hotter CPU/GPU sensor and the existing Helper watchdog.

## Control policy

- At or below 45 °C, the target is 20% of each fan's independently detected range.
- At or above 90 °C, the target is 100%.
- Between those limits, Breeze uses linear interpolation quantized to 5% steps.
- Temperature increases apply immediately.
- Decreases require a 2 °C hysteresis and remain stable for 3 seconds.
- An active curve uses one-second monitoring even when Breeze windows are closed.
- The Helper continues to validate the model, fan count, target percentage, fan ranges, writes, and readback before reporting success.

## Automated evidence

- All 88 hardware, automatic-planning, custom-curve, diagnostic-export, watchdog, Helper, XPC, and app-state tests pass.
- Boundary tests verify 45 °C → 20%, 55 °C → 40%, 70 °C → 65%, and 90 °C → 100%.
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
