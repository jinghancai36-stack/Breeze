# Contributing to Breeze

Contributions are welcome, especially for documentation, tests, accessibility, localization, UI refinement, and read-only hardware compatibility.

## Development setup

1. Install the current Xcode toolchain.
2. Open `Breeze.xcodeproj`, select the `Breeze` scheme and **My Mac**, then run with `⌘R`.
3. Run the test suite before changing code:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
   ```

4. Build the local app with `./scripts/build-app.sh` when you need to test the bundled Helper.

The menu bar app has no Dock icon. Use the Breeze menu bar item or its Settings window.

## Pull requests

- Keep changes focused and explain the user-visible outcome.
- Add or update tests for behavior changes.
- Preserve Swift 6 strict-concurrency checks.
- Update README, safety, architecture, and validation documents when their claims change.
- Do not commit DerivedData, build outputs, certificates, provisioning profiles, or local signing configuration.

## Safety-sensitive changes

Changes involving SMC writes, target bounds, supported models, the privileged Helper, XPC authentication, watchdog timing, sleep/wake recovery, or Automatic restore require:

- Helper-side validation even if the GUI already validates the request
- No arbitrary key, byte buffer, command, executable, or path input
- Unit tests for refusal, rollback, and timeout behavior
- Debug and optimized Release test passes
- Real-hardware evidence beginning near the detected minimum RPM
- Verification of Automatic restore after normal Quit, GUI loss, Helper restart, sleep/wake, and reboot when applicable

Never use a first write at maximum RPM on newly supported hardware.

## Hardware compatibility

Submit read-only evidence before proposing write support for a new model. Follow [SUPPORTED_MACS.md](SUPPORTED_MACS.md) and include the model identifier, chip, fan count, bounds, macOS version, and diagnostic report.

## Signing and secrets

Local Apple Development signing is acceptable for development. Do not commit signing identities, certificates, passwords, notarization credentials, or Apple account data. Public binary releases require Developer ID signing and notarization.

## License

By contributing, you agree that your contribution is licensed under the repository's MIT License.
