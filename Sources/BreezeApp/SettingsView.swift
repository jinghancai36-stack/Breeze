import SwiftUI

#if canImport(BreezeHardware)
  import BreezeHardware
#endif

struct SettingsView: View {
  let state: AppState
  @AppStorage(PreferenceKey.menuBarDisplay)
  private var menuBarDisplay = MenuBarDisplay.temperatureAndRPM.rawValue
  @State private var loginItem = LaunchAtLoginController()

  var body: some View {
    TabView {
      general
        .tabItem { Label("General", systemImage: "gear") }
      hardware
        .tabItem { Label("Hardware", systemImage: "cpu") }
      helper
        .tabItem { Label("Helper", systemImage: "lock.shield") }
      about
        .tabItem { Label("About", systemImage: "info.circle") }
    }
    .frame(width: 500, height: 380)
    .onAppear {
      loginItem.refresh()
      state.refreshHelperStatus()
    }
  }

  private var general: some View {
    Form {
      Section("Startup") {
        Toggle(
          "Launch Breeze at Login",
          isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
          )
        )
        if loginItem.requiresApproval {
          LabeledContent("Approval") {
            Button("Open Login Items") { loginItem.openSystemSettings() }
          }
        }
        if let error = loginItem.errorMessage {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Section("Menu Bar") {
        Picker("Display", selection: $menuBarDisplay) {
          ForEach(MenuBarDisplay.allCases) { mode in
            Text(mode.title).tag(mode.rawValue)
          }
        }
      }

      Section("Monitoring") {
        LabeledContent("Popover refresh", value: "1 second")
        LabeledContent("Background refresh", value: "5 seconds")
      }

      Section("Safety") {
        Text("Breeze always starts in Apple Automatic mode and never resumes an active fan mode after relaunch or wake.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  private var hardware: some View {
    Form {
      if let snapshot = state.snapshot {
        Section("Mac") {
          LabeledContent("Model", value: snapshot.hardware.modelIdentifier)
          LabeledContent("Chip", value: snapshot.hardware.chipName)
          LabeledContent("Architecture", value: snapshot.hardware.architecture)
          LabeledContent("Fan count", value: snapshot.hardware.fanCount.formatted())
          LabeledContent(
            "Control status",
            value: snapshot.hardware.isControlVerified ? "Verified" : "Monitor only")
        }

        Section("Fans") {
          ForEach(snapshot.fans) { fan in
            VStack(alignment: .leading, spacing: 4) {
              Text("Fan \(fan.id + 1)")
                .fontWeight(.medium)
              Text("Reported range: \(range(for: fan))")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      } else {
        ContentUnavailableView("Hardware unavailable", systemImage: "cpu")
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  private var helper: some View {
    Form {
      Section("Privileged Helper") {
        LabeledContent("Registration", value: helperStatusText)
        LabeledContent("Connection") {
          if state.isCheckingHelper {
            ProgressView()
              .controlSize(.small)
          } else {
            Text(state.helperVersion.map { "Connected · v\($0)" } ?? "Not checked")
          }
        }

        if let error = state.helperErrorMessage {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Section("Automatic Control") {
        LabeledContent("State") {
          if state.isRestoringAutomaticControl {
            ProgressView().controlSize(.small)
          } else if let status = state.automaticControlStatus {
            Text(status.isAutomatic ? "Apple automatic" : "Not verified")
          } else {
            Text("Not checked")
          }
        }
        if let status = state.automaticControlStatus {
          LabeledContent("Fan modes", value: status.fanModes.map(String.init).joined(separator: ", "))
          LabeledContent("Ftst", value: status.forceTest.map(String.init) ?? "Unavailable")
        }
        HStack {
          Button("Check State") { state.checkAutomaticControl() }
          Button("Restore Apple Automatic") { state.restoreAutomaticControl() }
            .disabled(state.isRestoringAutomaticControl)
        }
        .disabled(state.helperStatus != .enabled)
      }

      Section {
        HStack {
          switch state.helperStatus {
          case .enabled:
            Button("Test Connection") { state.pingHelper() }
              .disabled(state.isCheckingHelper)
            Button("Remove Helper", role: .destructive) { state.uninstallHelper() }
          case .requiresApproval:
            Button("Open Login Items") { state.openHelperApprovalSettings() }
            Button("Refresh") { state.refreshHelperStatus() }
          case .notRegistered, .notFound:
            Button("Install Helper") { state.installHelper() }
          }
        }
      } footer: {
        Text(
          "Breeze permits only verified fan 0/1 control and the fixed Balanced, Cool, and Max presets on MacBookPro18,3. Each preset is calculated independently from every fan's detected min/max range. A fixed Helper watchdog restores Automatic if heartbeats stop; arbitrary SMC operations and caller-controlled timeouts are not exposed."
        )
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  private var about: some View {
    Form {
      Section {
        HStack(spacing: 12) {
          Image(systemName: "fan.fill")
            .font(.system(size: 32))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 3) {
            Text("Breeze")
              .font(.title2.weight(.semibold))
            Text("A lightweight, native fan controller for Apple Silicon Macs.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 4)
      }

      Section("Build") {
        LabeledContent("Version", value: appVersion)
        LabeledContent("Build", value: buildNumber)
        LabeledContent("Minimum macOS", value: "14.0")
        LabeledContent("License", value: "MIT")
      }

      Section("Support") {
        LabeledContent("Verified control model", value: "MacBookPro18,3")
        Text("Other Apple Silicon Macs remain Monitor Only until their fan-control behavior is independently verified.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Section("Hardware Notice") {
        Text("Breeze uses undocumented AppleSMC interfaces. Fan control availability can vary by model and macOS version.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  private var helperStatusText: String {
    switch state.helperStatus {
    case .notRegistered: "Not installed"
    case .enabled: "Enabled"
    case .requiresApproval: "Approval required"
    case .notFound: "Helper missing from app bundle"
    }
  }

  private func range(for fan: FanState) -> String {
    guard let minimum = fan.minimumRPM, let maximum = fan.maximumRPM else {
      return "Unknown"
    }
    return "\(Int(minimum.rounded()).formatted())–\(Int(maximum.rounded()).formatted()) RPM"
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
  }

  private var buildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Local"
  }
}

#Preview("Settings") {
  SettingsView(state: .preview)
}
