# Security Policy

Breeze includes a privileged Helper and writes undocumented AppleSMC fan controls. Security reports involving the Helper, XPC validation, code signing, RPM bounds, automatic restoration, or watchdog behavior are treated as safety-critical.

## Supported versions

Only the latest source revision is supported before the first public release. Published support information will be updated here when versioned binaries exist.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could enable privilege escalation, arbitrary Helper access, unsafe SMC writes, or failure to restore Apple Automatic control.

After the repository is published, use GitHub's private security-advisory flow. Before publication, report the issue privately to the project owner through the channel where you received the source. Include:

- Breeze version, build, and commit;
- Mac model identifier and macOS version;
- whether the Helper was installed and active;
- exact reproduction steps and expected behavior;
- logs or diagnostics with passwords, certificates, serial numbers, and personal paths removed.

Please allow time for a safe fix and coordinated disclosure. Do not test a report by bypassing Breeze's model whitelist or RPM bounds on production hardware.

## Immediate safety response

If fan control appears unsafe, stop testing and restore Apple Automatic control. Follow [Installation and Recovery](docs/INSTALLATION_AND_RECOVERY.md). Breeze's removal path intentionally refuses to remove the Helper until Automatic has been verified.

## Out of scope

- Reports that require disabling Gatekeeper, System Integrity Protection, or Breeze's signing checks.
- Requests to expose arbitrary commands, paths, SMC keys, raw mode values, or byte buffers through XPC.
- Fan-control compatibility claims without repeatable evidence from the exact hardware model.
