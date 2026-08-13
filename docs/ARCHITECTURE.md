# Architecture

```text
Breeze menu bar app ─┬─> BreezeHardware ─> read-only AppleSMC / IOKit
                     └─> BreezeIPC ─XPC─> BreezeHelper (launchd/root)
breeze-hardware CLI ───> BreezeHardware
```

## BreezeHardware

Owns hardware models, SMC protocol layout, decoding, fan discovery, sensor probing, and snapshots. Its public surface exposes domain models rather than raw keys.

## breeze-hardware

Diagnostic CLI for `info`, `fans`, `temperatures`, `watch`, and JSON `report`. It is the primary validation surface for Milestone 1.

## Breeze

SwiftUI `MenuBarExtra` using a root-owned observable `AppState`. Hardware polling is owned by the app state rather than the popover, so it survives popover dismissal. The popover only changes the polling policy between 1-second foreground and 5-second background intervals.

`SettingsView` owns presentation preferences through `@AppStorage` and delegates login-item state to a narrow `LaunchAtLoginController`. `AppState` observes `NSWorkspace` sleep/wake notifications and retains its last good snapshot across temporary read failures.

## BreezeIPC

Owns the Objective-C-compatible XPC protocol and identifiers shared by the app and helper. The Balanced slice exposes nine fixed operations: `ping`, `getHelperVersion`, `getAutomaticControlStatus`, `restoreAutomaticControl`, `setFanRPM`, `setFanAutomatic`, `applyBalancedPreset`, `renewControlLease`, and `getControlLeaseStatus`. Balanced and lease calls accept no arguments. Manual calls accept only an integer fan ID and, for setting RPM, an integer request. There is no generic payload, caller-controlled timeout, arbitrary command, path, SMC key, raw mode value, or byte buffer.

## BreezeHelper

An on-demand launch daemon embedded at `Contents/MacOS/BreezeHelper` and registered with `SMAppService.daemon`. Its launchd property list lives at `Contents/Library/LaunchDaemons/com.cai.Breeze.Helper.plist` and advertises one privileged Mach service.

Both XPC sides set code-signing requirements before resuming a connection. The helper additionally checks that the connecting PID resolves to the `Breeze` executable beside it in the same app bundle. The local app and helper are signed by the same Apple Development team; Developer ID and notarization remain required for ordinary distribution to other Macs.

The helper owns a separate `SMCRestoreConnection` that links IOKit. Despite the historical filename, it is the complete write-capable provider. Write keys are derived only from `VerifiedFan` (`fan0` or `fan1`) and fixed mode/target operations. `ManualFanController` rejects every model except `MacBookPro18,3`, requires exactly two fans and the M1 direct-control strategy, re-reads trustworthy min/max bounds, clamps every request, settles the asynchronous mode transition, and sends the target through a same-signed root-only fixed worker process. The worker independently revalidates root, model, fan count, mode, strategy, and bounds and accepts no key/path/raw payload. The parent verifies mode and target readback, waits for actual RPM convergence, and restores all fans on failure. `AutomaticControlRestorer` also clears target keys while relinquishing control.

`ControlLeaseWatchdog` is Helper-owned and independent of UI polling. Manual success arms 15 seconds; the app renews every 5 seconds. Expiry serializes through the same control-operation gate as XPC writes, restores all fans, and retries failed restores every 2 seconds. Startup recovery runs before the Mach listener accepts clients. `RunAtLoad` plus `KeepAlive` replaces a crashed helper, while `SystemPowerObserver` restores on sleep and wake. `BreezeHardware` remains read-only, and the GUI never sees SMC keys.
