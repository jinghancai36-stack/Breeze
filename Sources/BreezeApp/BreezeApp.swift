import AppKit
import SwiftUI

#if canImport(BreezeHardware)
  import BreezeHardware
#endif
#if canImport(BreezeIPC)
  import BreezeIPC
#endif

@main
struct BreezeApp: App {
  @NSApplicationDelegateAdaptor(BreezeAppDelegate.self) private var appDelegate
  @State private var state: AppState
  @AppStorage(PreferenceKey.menuBarDisplay)
  private var menuBarDisplay = MenuBarDisplay.temperatureAndRPM.rawValue

  init() {
    NSApplication.shared.setActivationPolicy(.accessory)
    let appState = AppState()
    appState.start()
    _state = State(initialValue: appState)
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarView(state: state)
    } label: {
      MenuBarLabel(
        display: MenuBarDisplay(rawValue: menuBarDisplay) ?? .temperatureAndRPM,
        snapshot: state.snapshot
      )
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(state: state)
    }
  }
}

final class BreezeAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    let arguments = ProcessInfo.processInfo.arguments
    guard let command = arguments.first(where: { $0.hasPrefix("--helper-") }) else { return }

    let installer = SystemHelperInstaller()
    switch command {
    case "--helper-status":
      finish("Helper status: \(installer.status.diagnosticName)", success: true)
    case "--helper-register":
      do {
        try installer.register()
        finish("Helper registration: \(installer.status.diagnosticName)", success: true)
      } catch {
        finish(
          "Helper registration needs approval: \(error.localizedDescription) "
            + "(status: \(installer.status.diagnosticName))",
          success: installer.status == .requiresApproval
        )
      }
    case "--helper-unregister":
      guard installer.status == .enabled else {
        Self.unregister(installer)
        return
      }
      HelperClient().restoreAutomaticControl { result in
        switch result {
        case .success(let status) where status.isAutomatic:
          Self.unregister(installer)
        case .success(let status):
          Self.finish(
            "Helper removal refused because Automatic was not verified: \(status.message)",
            success: false)
        case .failure(let error):
          Self.finish(
            "Helper removal refused because Automatic could not be verified: \(error.localizedDescription)",
            success: false)
        }
      }
    case "--helper-open-settings":
      installer.openSystemSettings()
      return
    case "--helper-ping":
      HelperClient().probe { result in
        switch result {
        case .success(let version):
          Self.finish("Helper connected: v\(version)", success: true)
        case .failure(let error):
          Self.finish("Helper connection failed: \(error.localizedDescription)", success: false)
        }
      }
    case "--helper-auto-status":
      HelperClient().automaticControlStatus { result in
        switch result {
        case .success(let status):
          Self.finish(status.diagnosticDescription, success: status.isAutomatic)
        case .failure(let error):
          Self.finish("Automatic-control status failed: \(error.localizedDescription)", success: false)
        }
      }
    case "--helper-restore-auto":
      HelperClient().restoreAutomaticControl { result in
        switch result {
        case .success(let status):
          Self.finish(status.diagnosticDescription, success: status.isAutomatic)
        case .failure(let error):
          Self.finish("Automatic restore failed: \(error.localizedDescription)", success: false)
        }
      }
    case "--helper-set-rpm":
      guard let commandIndex = arguments.firstIndex(of: command),
        arguments.indices.contains(commandIndex + 2),
        let fanID = Int(arguments[commandIndex + 1]),
        let rpm = Int(arguments[commandIndex + 2])
      else {
        finish("Usage: --helper-set-rpm <fan 0|1> <rpm>", success: false)
        return
      }
      let client = HelperClient()
      client.probe { result in
        switch result {
        case .success(let version) where version == BreezeHelperConstants.helperVersion:
          client.setFanRPM(fanID: fanID, rpm: rpm) { result in
            switch result {
            case .success(let status):
              Self.finish(status.diagnosticDescription, success: status.success)
            case .failure(let error):
              Self.finish("Manual fan request failed: \(error.localizedDescription)", success: false)
            }
          }
        case .success(let version):
          Self.finish(
            "Manual control refused: app requires Helper v\(BreezeHelperConstants.helperVersion), found v\(version).",
            success: false)
        case .failure(let error):
          Self.finish("Manual control refused: \(error.localizedDescription)", success: false)
        }
      }
    case "--helper-set-auto":
      guard let commandIndex = arguments.firstIndex(of: command),
        arguments.indices.contains(commandIndex + 1),
        let fanID = Int(arguments[commandIndex + 1])
      else {
        finish("Usage: --helper-set-auto <fan 0|1>", success: false)
        return
      }
      HelperClient().setFanAutomatic(fanID: fanID) { result in
        switch result {
        case .success(let status):
          Self.finish(status.diagnosticDescription, success: status.success)
        case .failure(let error):
          Self.finish("Automatic fan request failed: \(error.localizedDescription)", success: false)
        }
      }
    case "--helper-balanced":
      let client = HelperClient()
      client.probe { result in
        switch result {
        case .success(let version) where version == BreezeHelperConstants.helperVersion:
          client.applyBalancedPreset { result in
            switch result {
            case .success(let status):
              let targets = status.targetRPMs.map(String.init).joined(separator: ",")
              let actuals = status.actualRPMs.map(String.init).joined(separator: ",")
              Self.finish(
                "\(status.message) targets=[\(targets)] actual=[\(actuals)] restored=\(status.didRestoreAutomatic)",
                success: status.success)
            case .failure(let error):
              Self.finish("Balanced preset failed: \(error.localizedDescription)", success: false)
            }
          }
        case .success(let version):
          Self.finish(
            "Balanced refused: app requires Helper v\(BreezeHelperConstants.helperVersion), found v\(version).",
            success: false)
        case .failure(let error):
          Self.finish("Balanced refused: \(error.localizedDescription)", success: false)
        }
      }
    case "--helper-cool":
      let client = HelperClient()
      client.probe { result in
        switch result {
        case .success(let version) where version == BreezeHelperConstants.helperVersion:
          client.applyCoolPreset { result in
            switch result {
            case .success(let status):
              let targets = status.targetRPMs.map(String.init).joined(separator: ",")
              let actuals = status.actualRPMs.map(String.init).joined(separator: ",")
              Self.finish(
                "\(status.message) targets=[\(targets)] actual=[\(actuals)] restored=\(status.didRestoreAutomatic)",
                success: status.success)
            case .failure(let error):
              Self.finish("Cool preset failed: \(error.localizedDescription)", success: false)
            }
          }
        case .success(let version):
          Self.finish(
            "Cool refused: app requires Helper v\(BreezeHelperConstants.helperVersion), found v\(version).",
            success: false)
        case .failure(let error):
          Self.finish("Cool refused: \(error.localizedDescription)", success: false)
        }
      }
    case "--helper-heartbeat":
      HelperClient().renewControlLease { result in
        switch result {
        case .success(let status):
          Self.finish(
            "Watchdog active=\(status.isActive) remaining=\(status.remainingSeconds)s \(status.message)",
            success: status.isActive)
        case .failure(let error):
          Self.finish("Watchdog heartbeat failed: \(error.localizedDescription)", success: false)
        }
      }
    case "--helper-watchdog-status":
      HelperClient().controlLeaseStatus { result in
        switch result {
        case .success(let status):
          Self.finish(
            "Watchdog active=\(status.isActive) remaining=\(status.remainingSeconds)s \(status.message)",
            success: true)
        case .failure(let error):
          Self.finish("Watchdog status failed: \(error.localizedDescription)", success: false)
        }
      }
    default:
      finish("Unknown helper diagnostic command: \(command)", success: false)
    }
  }

  private func finish(_ message: String, success: Bool) {
    Self.finish(message, success: success)
  }

  private static func finish(_ message: String, success: Bool) {
    let handle = success ? FileHandle.standardOutput : FileHandle.standardError
    handle.write(Data("\(message)\n".utf8))
    exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
  }

  private static func unregister(_ installer: SystemHelperInstaller) {
    do {
      try installer.unregister()
      finish("Helper status: \(installer.status.diagnosticName)", success: true)
    } catch {
      finish("Unable to unregister helper: \(error.localizedDescription)", success: false)
    }
  }
}

private extension HelperRegistrationStatus {
  var diagnosticName: String {
    switch self {
    case .notRegistered: "not registered"
    case .enabled: "enabled"
    case .requiresApproval: "approval required"
    case .notFound: "not found"
    }
  }
}

private struct MenuBarLabel: View {
  let display: MenuBarDisplay
  let snapshot: HardwareSnapshot?

  var body: some View {
    switch display {
    case .icon:
      Image(systemName: "fan")
        .accessibilityLabel("Breeze")
    case .temperature:
      Label(temperatureText, systemImage: "fan")
    case .rpm:
      Label(rpmText, systemImage: "fan")
    case .temperatureAndRPM:
      Label("\(temperatureText)  \(rpmText)", systemImage: "fan")
    }
  }

  private var temperatureText: String {
    guard let temperature = snapshot?.primaryTemperature?.temperature else { return "--°" }
    return "\(Int(temperature.rounded()))°"
  }

  private var rpmText: String {
    guard let rpm = snapshot?.fans.first?.currentRPM else { return "--" }
    return Int(rpm.rounded()).formatted()
  }
}
