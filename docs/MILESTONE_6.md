# Milestone 6 — Safety Watchdog

Milestone 6 makes manual control a time-limited Helper-owned lease. It does not add the Phase 7 presets.

## Deliverables

- [x] Successful Manual control arms a fixed 15-second Helper lease.
- [x] The GUI sends a heartbeat immediately and every 5 seconds while Manual is active.
- [x] XPC callers cannot set or disable timeout values.
- [x] Heartbeat timeout restores both fan modes and target values to Apple Automatic.
- [x] Failed timeout restore remains armed and retries every 2 seconds.
- [x] Heartbeat cannot create a lease after it has been disarmed.
- [x] Explicit Automatic and successful Quit disarm the lease.
- [x] GUI/XPC disappearance is covered by the missing-heartbeat timeout.
- [x] Helper startup performs unconditional Automatic recovery before accepting XPC.
- [x] Helper removal requires verified Automatic, and graceful termination performs a final Helper-side recovery.
- [x] launchd plist uses `RunAtLoad` and `KeepAlive` for helper crash/restart and boot recovery.
- [x] App requests Automatic on sleep and checks Automatic after wake.
- [x] Root Helper independently restores on system sleep and wake.
- [x] Wake never resumes a prior Manual target.
- [x] Watchdog state and heartbeat are visible through fixed, argument-free diagnostics.
- [x] Menu bar UI displays an active safety lease.
- [x] Dedicated tests cover timeout, renewal, failed-restore retry, XPC disconnect, helper replacement, sleep/wake, and repeated Manual sessions.

## Fixed timing

```text
App heartbeat: 5 seconds
Helper timeout: 15 seconds
Failed restore retry: 2 seconds
```

These values are internal safety constants. The GUI and XPC protocol cannot change them.

## Hardware validation

The signed v0.6.1 Helper passed the complete real fault-injection suite on the verified Mac. Evidence for normal Quit, GUI SIGKILL/XPC loss, Helper SIGKILL/relaunch, sleep/wake, and reboot recovery is recorded in `VALIDATION_M6.md`.
