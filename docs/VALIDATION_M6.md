# Milestone 6 Validation

Validation target: `MacBookPro18,3`, Apple M1 Pro, two fans.

## Automated evidence

- Hardware tests: 9 passing.
- App/Helper/XPC tests: 49 passing.
- Dedicated `Safety watchdog` tests cover heartbeat extension, timeout restore, restore-failure retry, startup recovery, replacement-helper recovery, explicit disarm, and stale-heartbeat rejection.
- Real anonymous XPC tests prove Manual arms a lease, heartbeat/status cross the production protocol, and an invalidated transport followed by heartbeat timeout restores both fans.
- App-state tests prove sleep requests Automatic, wake never resumes Manual, and a second Manual session starts a fresh heartbeat task.
- Debug and optimized Release test suites both pass with Swift 6 strict concurrency (9 hardware + 49 App/Helper/XPC tests in each configuration).
- Xcode Release static analysis completes successfully.

## Static safety evidence

- Helper version: 0.6.1.
- Manual lease timeout: 15 seconds; heartbeat: 5 seconds; retry: 2 seconds.
- launchd job contains `RunAtLoad=true` and `KeepAlive=true`.
- Startup Automatic recovery completes before the XPC listener resumes.
- Unsupported hardware is rejected once without creating a permanent recovery retry loop; transient restore failures still retry.
- Automatic recovery and new Manual sessions share one serialized operation gate, preventing an older timeout from clearing a newer lease.
- Root `SystemPowerObserver` restores on sleep and wake.
- XPC adds only argument-free `renewControlLease` and `getControlLeaseStatus` operations.
- Both GUI and diagnostic Manual entry points reject an older Helper that lacks the v0.6 watchdog.
- On the development Mac, the rebuilt v0.6 diagnostic rejected the still-installed v0.5 Helper before a Manual request (`exit 1`); a following read-only check remained Automatic at `[0,0]`.

## Real hardware fault injection

The signed v0.6.1 Helper was installed and approved with the user present. Every case started at 1400 RPM and ended with `[0,0]` verified:

- [x] Normal **Quit Breeze** restores Automatic before exit — GUI heartbeat observed, then lease disarmed and `[0,0]` verified on 2026-08-12.
- [x] Force Quit / `kill -9` GUI stops heartbeats and restores after the 15-second lease — PID 29465 was killed with no cleanup; timeout restored `[0,0]` on 2026-08-12.
- [x] XPC/GUI disappearance restores after heartbeat timeout — covered by the same real transport/process-loss test.
- [x] Killing the Helper causes launchd replacement and startup recovery — root PID 28933 was SIGKILLed; launchd started PID 29857, which reported v0.6.1 and verified `[0,0]` before accepting XPC on 2026-08-12.
- [x] Sleep restores Automatic; wake remains Automatic without resuming Manual — pre-sleep state was `[1,0]`; after wake the Helper reported `System wake recovery`, lease inactive, `[0,0]`, while the GUI remained running on 2026-08-12.
- [x] Reboot starts the Helper and does not preserve Manual state — before reboot: boot time 2026-08-11 11:34:50, Helper PID 29857, lease renewed, `[1,0]`; after reboot: boot time 2026-08-12 20:41:48, Helper PID 562, GUI absent, startup recovery verified, lease inactive, `[0,0]` on 2026-08-12.

All Milestone 6 real-hardware fault-injection cases are recorded above and passed on the verified `MacBookPro18,3`.
