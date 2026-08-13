## Summary

Describe the user-visible or architectural change.

## Validation

- [ ] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`
- [ ] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test -c release`
- [ ] `./scripts/release-check.sh` when the change is release-sensitive

## Safety impact

- [ ] This change does not modify SMC writes, Helper/XPC security, RPM bounds, supported hardware, automatic restoration, or watchdog behavior.
- [ ] If it does, I documented the exact hardware evidence, failure-path tests, and verified Apple Automatic recovery.

## Privacy

- [ ] Logs and screenshots contain no passwords, certificates, serial numbers, or unrelated personal paths.
