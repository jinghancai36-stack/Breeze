# Milestone 3 — Privileged Helper Foundation

Milestone 3 implements the privilege boundary only. It does not control fans.

## Deliverables

- [x] Dedicated `BreezeHelper` command-line target.
- [x] Helper embedded in `Breeze.app/Contents/MacOS` and signed before the app.
- [x] LaunchDaemon plist embedded in `Contents/Library/LaunchDaemons`.
- [x] Modern `SMAppService.daemon(plistName:)` registration flow.
- [x] Privileged Mach service through `NSXPCConnection`.
- [x] Shared protocol containing only `ping` and `getHelperVersion`.
- [x] Client validates the helper signing identifier.
- [x] Helper validates the client signing identifier and exact bundled path.
- [x] Connection interruption, invalidation, proxy errors, and timeout are bounded.
- [x] Registration and connection state live in `AppState`.
- [x] Native Settings UI for install, approval, test, and removal.
- [x] No SMC or fan-control code in the helper.

## Approval flow

The first registration is intentionally subject to macOS administrator approval:

1. Open Breeze Settings → Helper.
2. Click **Install Helper**.
3. If shown, click **Open Login Items** and enable Breeze under background items.
4. Return to Breeze, click **Refresh**, then **Test Connection**.

The system will not bootstrap a registered LaunchDaemon until an administrator
approves it. Breeze never attempts to bypass this control.

During development, rebuilding changes the nested Helper's signature. Remove and
install the Helper again after such a rebuild so ServiceManagement records the new
bundle generation.

## Developer diagnostics

Run the built app executable directly so it retains its bundle context:

```sh
dist/Breeze.app/Contents/MacOS/Breeze --helper-status
dist/Breeze.app/Contents/MacOS/Breeze --helper-register
dist/Breeze.app/Contents/MacOS/Breeze --helper-ping
dist/Breeze.app/Contents/MacOS/Breeze --helper-unregister
```

## Security boundary

The local build script uses an available Apple Development identity and signs the
inner Helper before the outer App. This does not require a paid Developer Program
membership. Both peers derive the Team ID from their own signatures at runtime and
require the remote peer to have the expected identifier, Apple trust anchor, and
same Team ID. The Helper additionally requires the GUI's exact executable path in
its own app bundle. Developer ID and notarization are still required for normal
download distribution to other Macs.

No future phase may add arbitrary shell execution, arbitrary filesystem access,
or arbitrary SMC-key writes to this protocol.

## Verification gates

- [x] SwiftPM build and all unit/integration tests pass.
- [x] Debug and Release Xcode builds succeed.
- [x] Strict nested code-signature validation succeeds.
- [x] Bundle contains the helper and matching launchd plist at the documented paths.
- [x] Twenty-five consecutive anonymous XPC transport probes pass.
- [x] Missing-helper transport fails within its deadline.
- [x] An XPC client outside the expected app bundle is rejected.
- [x] Actual `SMAppService` status reaches `enabled` after user approval.
- [x] Actual privileged `--helper-ping` returns helper version 0.3.0.
