import AppKit
import Combine
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

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

@MainActor
final class BreezeAppDelegate: NSObject, NSApplicationDelegate {
  private lazy var state = AppState()
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()
  private var dashboardWindow: NSWindow?
  private var settingsWindow: NSWindow?
  private var cancellables: Set<AnyCancellable> = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    let arguments = ProcessInfo.processInfo.arguments
    guard let command = arguments.first(where: { $0.hasPrefix("--helper-") }) else {
      setUpApplication()
      return
    }

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
          Self.finish(
            "Automatic-control status failed: \(error.localizedDescription)", success: false)
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
              Self.finish(
                "Manual fan request failed: \(error.localizedDescription)", success: false)
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
    case "--helper-curve":
      guard let commandIndex = arguments.firstIndex(of: command),
        arguments.indices.contains(commandIndex + 1),
        let percent = Int(arguments[commandIndex + 1])
      else {
        finish("Usage: --helper-curve <20...100, step 5>", success: false)
        return
      }
      let client = HelperClient()
      client.probe { result in
        switch result {
        case .success(let version) where version == BreezeHelperConstants.helperVersion:
          client.applyCurveTarget(percent: percent) { result in
            switch result {
            case .success(let status):
              let targets = status.targetRPMs.map(String.init).joined(separator: ",")
              let actuals = status.actualRPMs.map(String.init).joined(separator: ",")
              Self.finish(
                "\(status.message) targets=[\(targets)] actual=[\(actuals)] restored=\(status.didRestoreAutomatic)",
                success: status.success)
            case .failure(let error):
              Self.finish("Curve target failed: \(error.localizedDescription)", success: false)
            }
          }
        case .success(let version):
          Self.finish(
            "Curve target refused: app requires Helper v\(BreezeHelperConstants.helperVersion), found v\(version).",
            success: false)
        case .failure(let error):
          Self.finish("Curve target refused: \(error.localizedDescription)", success: false)
        }
      }
    case "--helper-quiet":
      let client = HelperClient()
      client.probe { result in
        switch result {
        case .success(let version) where version == BreezeHelperConstants.helperVersion:
          client.applyQuietPreset { result in
            switch result {
            case .success(let status):
              let targets = status.targetRPMs.map(String.init).joined(separator: ",")
              let actuals = status.actualRPMs.map(String.init).joined(separator: ",")
              Self.finish(
                "\(status.message) targets=[\(targets)] actual=[\(actuals)] restored=\(status.didRestoreAutomatic)",
                success: status.success)
            case .failure(let error):
              Self.finish("Quiet preset failed: \(error.localizedDescription)", success: false)
            }
          }
        case .success(let version):
          Self.finish(
            "Quiet refused: app requires Helper v\(BreezeHelperConstants.helperVersion), found v\(version).",
            success: false)
        case .failure(let error):
          Self.finish("Quiet refused: \(error.localizedDescription)", success: false)
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
    case "--helper-max":
      let client = HelperClient()
      client.probe { result in
        switch result {
        case .success(let version) where version == BreezeHelperConstants.helperVersion:
          client.applyMaxPreset { result in
            switch result {
            case .success(let status):
              let targets = status.targetRPMs.map(String.init).joined(separator: ",")
              let actuals = status.actualRPMs.map(String.init).joined(separator: ",")
              Self.finish(
                "\(status.message) targets=[\(targets)] actual=[\(actuals)] restored=\(status.didRestoreAutomatic)",
                success: status.success)
            case .failure(let error):
              Self.finish("Max preset failed: \(error.localizedDescription)", success: false)
            }
          }
        case .success(let version):
          Self.finish(
            "Max refused: app requires Helper v\(BreezeHelperConstants.helperVersion), found v\(version).",
            success: false)
        case .failure(let error):
          Self.finish("Max refused: \(error.localizedDescription)", success: false)
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
    case "--helper-legacy-install-worker":
      let result = LegacyHelperWorker.install()
      finish(result.message, success: result.success)
    case "--helper-legacy-uninstall-worker":
      let result = LegacyHelperWorker.uninstall()
      finish(result.message, success: result.success)
    default:
      finish("Unknown helper diagnostic command: \(command)", success: false)
    }
  }

  private func setUpApplication() {
    NSApplication.shared.setActivationPolicy(.accessory)
    state.start()

    if let button = statusItem.button {
      button.target = self
      button.action = #selector(togglePopover(_:))
      button.sendAction(on: [.leftMouseUp])
      button.imagePosition = .imageLeading
    }
    popover.behavior = .transient
    popover.animates = true
    popover.contentSize = NSSize(width: 380, height: 620)
    popover.contentViewController = NSHostingController(
      rootView: MenuBarView(
        state: state,
        showDashboardAction: { [weak self] in self?.showDashboard() },
        showSettingsAction: { [weak self] in self?.showSettings() }
      ))

    state.$snapshot
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.updateStatusItem() }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.updateStatusItem() }
      .store(in: &cancellables)
    updateStatusItem()
  }

  @objc private func togglePopover(_ sender: Any?) {
    if popover.isShown {
      popover.performClose(sender)
      return
    }
    guard let button = statusItem.button else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  private func updateStatusItem() {
    guard let button = statusItem.button else { return }
    button.image = NSImage(systemSymbolName: "fan", accessibilityDescription: "Breeze")
    let rawDisplay = UserDefaults.standard.string(forKey: PreferenceKey.menuBarDisplay)
      ?? MenuBarDisplay.temperatureAndRPM.rawValue
    let display = MenuBarDisplay(rawValue: rawDisplay) ?? .temperatureAndRPM
    let temperature = state.snapshot?.primaryTemperature?.temperature
    let rpm = state.snapshot?.fans.first?.currentRPM
    switch display {
    case .icon:
      button.title = ""
    case .temperature:
      button.title = temperature.map { " \(Int($0.rounded()))°" } ?? " --°"
    case .rpm:
      button.title = rpm.map { " \(Int($0.rounded()).formatted())" } ?? " --"
    case .temperatureAndRPM:
      let temperatureText = temperature.map { "\(Int($0.rounded()))°" } ?? "--°"
      let rpmText = rpm.map { Int($0.rounded()).formatted() } ?? "--"
      button.title = " \(temperatureText)  \(rpmText)"
    }
    button.toolTip = "Breeze"
  }

  private func showDashboard() {
    if let dashboardWindow {
      present(dashboardWindow)
      return
    }
    let rootView: AnyView
    if #available(macOS 14.0, *) {
      rootView = AnyView(DashboardView(state: state))
    } else {
      rootView = AnyView(MontereyDashboardView(state: state))
    }
    let window = makeWindow(
      title: "Breeze", size: NSSize(width: 900, height: 620), rootView: rootView)
    dashboardWindow = window
    present(window)
  }

  private func showSettings() {
    if let settingsWindow {
      present(settingsWindow)
      return
    }
    let rootView: AnyView
    if #available(macOS 14.0, *) {
      rootView = AnyView(SettingsView(state: state))
    } else {
      rootView = AnyView(MontereySettingsView(state: state))
    }
    let window = makeWindow(
      title: L10n.text("action.settings", fallback: "Settings"),
      size: NSSize(width: 500, height: 420),
      rootView: rootView)
    settingsWindow = window
    present(window)
  }

  private func makeWindow(title: String, size: NSSize, rootView: AnyView) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = title
    window.contentViewController = NSHostingController(rootView: rootView)
    window.setContentSize(size)
    window.center()
    window.isReleasedWhenClosed = false
    return window
  }

  private func present(_ window: NSWindow) {
    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  private func finish(_ message: String, success: Bool) {
    Self.finish(message, success: success)
  }

  nonisolated private static func finish(_ message: String, success: Bool) {
    let handle = success ? FileHandle.standardOutput : FileHandle.standardError
    handle.write(Data("\(message)\n".utf8))
    exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
  }

  nonisolated private static func unregister(_ installer: SystemHelperInstaller) {
    do {
      try installer.unregister()
      finish("Helper status: \(installer.status.diagnosticName)", success: true)
    } catch {
      finish("Unable to unregister helper: \(error.localizedDescription)", success: false)
    }
  }
}

extension HelperRegistrationStatus {
  fileprivate var diagnosticName: String {
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
    HStack(spacing: 4) {
      Image(systemName: "fan")
      if let displayText {
        Text(displayText)
          .monospacedDigit()
      }
    }
    .accessibilityLabel(displayText.map { "Breeze, \($0)" } ?? "Breeze")
  }

  private var displayText: String? {
    switch display {
    case .icon: nil
    case .temperature: temperatureText
    case .rpm: rpmText
    case .temperatureAndRPM: "\(temperatureText)  \(rpmText)"
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
