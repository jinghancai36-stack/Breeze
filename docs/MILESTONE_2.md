# Milestone 2 — Daily-use Read-only App

## Deliverables

- [x] Standard `Breeze.xcodeproj` with a macOS application target.
- [x] `LSUIElement` app bundle with no Dock icon.
- [x] Reproducible `dist/Breeze.app` build script.
- [x] Root-owned monitoring state that continues while the popover is closed.
- [x] 1-second visible and 5-second background refresh policy.
- [x] Highest credible CPU/GPU/memory summaries and explicit battery temperature.
- [x] Four persistent menu bar presentation modes.
- [x] Native Settings scene with General and Hardware tabs.
- [x] Launch at Login integration using `SMAppService.mainApp`.
- [x] Sleep pause and immediate wake refresh through `NSWorkspace` notifications.
- [x] Last good snapshot is retained when a subsequent read fails.
- [x] Last-updated status, manual refresh, friendly stale-state error, and Logger diagnostics.
- [x] Menu bar and Settings previews.
- [x] No SMC write path or privileged helper.

## Build artifact

Run:

```sh
./scripts/build-app.sh
```

Output:

```text
dist/Breeze.app
```

The development artifact is ad-hoc signed and is intended for this Mac. GitHub release distribution will later require Developer ID signing and notarization.

## Verification gates

- Swift Package build succeeds.
- Swift Testing suites pass.
- Xcode Debug and Release application builds succeed.
- The built bundle is arm64, ad-hoc signed, Hardened Runtime enabled, and has `LSUIElement = true`.
- The app launches as a menu-bar-only process and remains alive during a runtime smoke test.
- Non-root live hardware reads still detect two fans and credible thermal data.
- Source audit confirms commands and APIs remain read-only.
