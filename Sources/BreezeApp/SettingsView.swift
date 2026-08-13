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
    }
    .frame(width: 480, height: 330)
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
            value: snapshot.hardware.isControlVerified ? "Manual verified" : "Monitor only")
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
          "Breeze permits only verified fan 0/1 control and the fixed Balanced and Cool presets on MacBookPro18,3. Each preset is calculated independently from every fan's detected min/max range. A fixed Helper watchdog restores Automatic if heartbeats stop; arbitrary SMC operations and caller-controlled timeouts are not exposed."
        )
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
}

#Preview("Settings") {
  SettingsView(state: .preview)
}
