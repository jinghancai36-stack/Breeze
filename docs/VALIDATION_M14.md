# Milestone 14 Validation — Apple Silicon Monterey Baseline

Validation target: Apple Silicon only, with `MacBookPro18,3` as the sole write-enabled model and macOS 12.0 as the deployment baseline.

## Automated evidence

- Swift Package Debug build targets `arm64-apple-macos12.0`.
- All 86 hardware, diagnostic-export, curve, watchdog, Helper, XPC, and app-state tests pass.
- The Xcode app and embedded Helper both build with deployment target 12.0.
- `LC_BUILD_VERSION` reports `minos 12.0` for both executables.
- `LSMinimumSystemVersion` is 12.0.
- Both executables are arm64-only.
- The legacy privileged worker refuses execution without root.

## Monterey compatibility paths

- AppKit `NSStatusItem`, `NSPopover`, and explicit `NSWindow` management replace newer SwiftUI scene APIs.
- `ObservableObject` and `@Published` replace macOS 14 Observation.
- A SwiftUI `Path`/gesture curve editor replaces Swift Charts on macOS 12 and 13.
- The Monterey Helper flow uses a fixed administrator-authorized worker, root-owned fixed destinations, and launchd bootstrap.
- The Helper validates pre-macOS 13 clients by executable location and Security.framework signing requirement when a Team ID is present.

## Manual validation still required

This development Mac is not running Monterey. Before calling Monterey runtime support fully verified, test a signed build on a clean macOS 12 installation and record:

1. first launch, status item, popover, dashboard, settings, and localization;
2. Helper install, connection, version match, and removal;
3. Automatic, curve, Manual, Balanced, Cool, and Max control on `MacBookPro18,3`;
4. watchdog recovery, app force-quit, sleep/wake, Helper restart, and reboot;
5. final Apple Automatic state (`[0,0]`) after every failure and removal case.

No Intel compatibility is included or claimed.
