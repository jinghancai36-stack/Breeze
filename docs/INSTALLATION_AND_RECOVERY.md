# Installation, Recovery, and Removal

## Distribution status

Breeze v0.8.0 is ready for source publication, not general binary distribution. The local Apple Development build is intended for its development Mac. A normal downloadable fan-control build requires Developer ID signing, Apple notarization, and installation tests on a clean Mac.

Do not disable Gatekeeper globally and do not manually install an unsigned executable as a root daemon.

## Local source build

Requirements:

- Apple Silicon Mac running macOS 12 Monterey or newer;
- Xcode 26 or newer;
- a local Apple Development signing identity for privileged Helper testing.

Build and open the app:

```sh
./scripts/build-app.sh
open dist/Breeze.app
```

Then open **Breeze → Settings → Helper** and choose **Install Helper**. On macOS 13 or newer, approve Breeze in **System Settings → General → Login Items & Extensions** when macOS asks. On Monterey, Breeze invokes a fixed installer through the standard administrator dialog; the system handles the password and Breeze never receives or stores it. The Helper must report the same version as the app before fan controls are enabled.

The Monterey path copies only the bundled `BreezeHelper` to `/Library/PrivilegedHelperTools`, writes one fixed `com.cai.Breeze.Helper` LaunchDaemon property list, and starts that service. It refuses to run from an ad-hoc unsigned build. Removal first verifies Apple Automatic, then uses the same administrator flow to stop and remove those two fixed files.

Without a usable Apple Development identity, the script creates an ad-hoc signed app. Monitoring may work, but Breeze intentionally does not claim that its privileged fan controls will work.

## Normal removal

Use this order so hardware safety is verified before files are removed:

1. In Breeze, choose **Restore All to Apple Automatic**.
2. Confirm the footer reports **Apple automatic**.
3. Open **Settings → Helper** and choose **Remove Helper**.
4. Quit Breeze using **Quit Breeze**.
5. Remove `Breeze.app` only after the Helper reports that it is no longer registered.

The app and Helper removal paths refuse to continue when Apple Automatic cannot be verified.

## Recovery when the interface is unavailable

Use the executable inside the exact Breeze app bundle that installed the Helper. Replace `/path/to` with that bundle's real location:

```sh
/path/to/Breeze.app/Contents/MacOS/Breeze --helper-auto-status
/path/to/Breeze.app/Contents/MacOS/Breeze --helper-restore-auto
/path/to/Breeze.app/Contents/MacOS/Breeze --helper-auto-status
```

A safe result reports modes `[0,0]` on the currently verified `MacBookPro18,3`. After Automatic is verified, request normal Helper removal:

```sh
/path/to/Breeze.app/Contents/MacOS/Breeze --helper-unregister
```

If macOS requires approval or the Helper cannot be reached, stop changing app files and use Breeze's Helper settings. On macOS 13 or newer, also check **System Settings → General → Login Items & Extensions**. Do not replace the embedded Helper while a manual or preset mode is active.

## What to include in a support report

- Breeze version, build, and Git commit;
- Mac model identifier and macOS version;
- Helper status and Helper version;
- output from `--helper-auto-status` and `--helper-watchdog-status`;
- whether the issue followed sleep, wake, reboot, a crash, or an app update.

Remove passwords, certificates, serial numbers, usernames, and unrelated personal paths before posting logs.
