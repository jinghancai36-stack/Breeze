import SwiftUI

struct MontereySettingsView: View {
  @ObservedObject var state: AppState
  @AppStorage(PreferenceKey.menuBarDisplay)
  private var menuBarDisplay = MenuBarDisplay.temperatureAndRPM.rawValue

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(L10n.text("action.settings", fallback: "Settings"))
          .font(.title.bold())

        GroupBox(label: Text(L10n.text("settings.menuBar", fallback: "Menu Bar"))) {
          Picker(L10n.text("settings.display", fallback: "Display"), selection: $menuBarDisplay) {
            ForEach(MenuBarDisplay.allCases) { mode in
              Text(mode.title).tag(mode.rawValue)
            }
          }
          .pickerStyle(.radioGroup)
          .padding(8)
        }

        GroupBox(label: Text(L10n.text("curve.title", fallback: "Automatic Curve"))) {
          VStack(alignment: .leading, spacing: 10) {
            Toggle(
              L10n.text("curve.enableSetting", fallback: "Enable Automatic Fan Curve"),
              isOn: Binding(
                get: { state.isFanCurveEnabled },
                set: { enabled in
                  if enabled { state.enableFanCurve() } else { state.disableFanCurve() }
                }))
            Text(
              L10n.text(
                "curve.safetyBody",
                fallback: "Every curve target remains protected by the Breeze watchdog."))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(8)
        }

        GroupBox(label: Text(L10n.text("helper.privileged", fallback: "Privileged Helper"))) {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text(L10n.text("helper.registration", fallback: "Registration"))
              Spacer()
              Text(helperStatusText).foregroundStyle(.secondary)
            }
            HStack {
              Button(L10n.text("action.installHelper", fallback: "Install Helper")) {
                state.installHelper()
              }
              Button(L10n.text("action.testConnection", fallback: "Test Connection")) {
                state.pingHelper()
              }
              .disabled(state.helperStatus != .enabled)
              Button(L10n.text("action.restoreAutomatic", fallback: "Restore Apple Automatic")) {
                state.restoreAutomaticControl()
              }
              .disabled(state.helperStatus != .enabled || state.isRestoringAutomaticControl)
            }
            if let error = state.helperErrorMessage {
              Text(error).font(.caption).foregroundStyle(.red)
            }
          }
          .padding(8)
        }

        Text("Breeze \(appVersion) · macOS 12.0+ · Apple Silicon")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(24)
    }
  }

  private var helperStatusText: String {
    switch state.helperStatus {
    case .notRegistered: return L10n.text("helper.notInstalled", fallback: "Not installed")
    case .enabled: return L10n.text("helper.enabled", fallback: "Enabled")
    case .requiresApproval: return L10n.text("helper.approvalRequired", fallback: "Approval required")
    case .notFound: return L10n.text("helper.missing", fallback: "Helper missing from app bundle")
    }
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
  }
}
