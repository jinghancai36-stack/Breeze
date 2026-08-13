# Milestone 3 Validation

Validated on 2026-08-12 on `MacBookPro18,3` running Apple Silicon macOS.

## Build and tests

- Swift Testing: 18 tests passed (9 hardware, 6 app-state, 3 XPC).
- XPC integration test completed 25 consecutive ping/version connections.
- Unavailable transport timed out within the configured bound.
- An executable outside the expected app bundle was rejected.
- Xcode Debug and Release application builds succeeded.

## Bundle and signing

```text
Breeze.app/Contents/MacOS/Breeze
Breeze.app/Contents/MacOS/BreezeHelper
Breeze.app/Contents/Library/LaunchDaemons/com.cai.Breeze.Helper.plist
```

- App identifier: `com.cai.Breeze`.
- Helper identifier / Mach service: `com.cai.Breeze.Helper`.
- App and Helper are arm64 and have Hardened Runtime enabled.
- Both are signed by the same Apple Development Team for local testing.
- `codesign --verify --deep --strict` passed for the complete app bundle.

## Real ServiceManagement and XPC check

```text
Helper registration: enabled
Helper connected: v0.3.0
REGISTER_EXIT:0
PING_EXIT:0
```

`launchctl` reported the service running with PID 54299, and `ps` confirmed that
the Helper process owner was `root`. It had never exited during the final check.

## Privilege-boundary audit

- The exported protocol contains exactly `ping` and `getHelperVersion`.
- The Helper target links no `IOKit.framework`, imports no IOKit APIs, and has no
  dependency on `BreezeHardware`; its explicit system dependencies are Foundation
  and Security.
- There is no SMC command, arbitrary payload, filesystem operation, shell command,
  RPM parameter, fan method, or hardware write in the Helper target.
- Both peers require the expected signing identifier, Apple trust anchor, and same
  Team ID; the Helper also validates the GUI executable's exact bundled path.

Milestone 3 is therefore a working privilege-separated transport, not a fan
controller. Automatic restoration remains the required first write for Phase 4.
