import SwiftUI

struct MontereySettingsView: View {
  @ObservedObject var state: AppState
  @AppStorage(PreferenceKey.menuBarDisplay)
  private var menuBarDisplay = MenuBarDisplay.temperatureAndRPM.rawValue
  @State private var isConfirmingHistoryClear = false

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
            Toggle(
              L10n.text(
                "curve.resumeAutomatically",
                fallback: "Resume Full Automatic after login or wake"),
              isOn: Binding(
                get: { state.automaticallyResumeFullAutomatic },
                set: { state.setAutomaticallyResumeFullAutomatic($0) })
            )
            .disabled(state.fanCurveMode != .automatic)
          }
          .padding(8)
        }

        GroupBox(label: Text(L10n.text("curve.editorTitle", fallback: "Custom Curve"))) {
          MontereyCurveEditor(state: state)
            .padding(8)
        }

        GroupBox(label: Text(L10n.text("dashboard.thermalHistory", fallback: "Thermal History"))) {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text(
                L10n.format(
                  "dashboard.historySampleCount", fallback: "%d saved samples",
                  state.thermalHistory.count))
                .foregroundStyle(.secondary)
              Spacer()
              Button(L10n.text("action.clearHistory", fallback: "Clear History")) {
                isConfirmingHistoryClear = true
              }
              .disabled(state.thermalHistory.isEmpty)
            }
            if #available(macOS 13.0, *), state.thermalHistory.count >= 2 {
              ThermalHistoryChart(samples: state.thermalHistory)
            } else {
              Text(
                L10n.text(
                  "dashboard.historyCollecting", fallback: "Collecting temperature history…"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
            }
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

        GroupBox(label: Text(L10n.text("diagnostics.title", fallback: "Hardware Diagnostics"))) {
          DiagnosticReportActionsView(state: state)
            .padding(8)
        }

        Text("Breeze \(appVersion) · macOS 12.0+ · Apple Silicon")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(24)
    }
    .frame(minWidth: 820, minHeight: 600)
    .onAppear { state.refreshNow() }
    .confirmationDialog(
      L10n.text("dashboard.clearHistoryTitle", fallback: "Clear monitoring history?"),
      isPresented: $isConfirmingHistoryClear
    ) {
      Button(L10n.text("action.clearHistory", fallback: "Clear History"), role: .destructive) {
        state.clearThermalHistory()
      }
      Button(L10n.text("action.cancel", fallback: "Cancel"), role: .cancel) {}
    } message: {
      Text(
        L10n.text(
          "dashboard.clearHistoryBody",
          fallback: "Saved temperature and fan-speed samples will be permanently removed."))
    }
  }

  private var helperStatusText: String {
    switch state.helperStatus {
    case .notRegistered: return L10n.text("helper.notInstalled", fallback: "Not installed")
    case .enabled: return L10n.text("helper.enabled", fallback: "Enabled")
    case .requiresApproval:
      return L10n.text("helper.approvalRequired", fallback: "Approval required")
    case .notFound: return L10n.text("helper.missing", fallback: "Helper missing from app bundle")
    }
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
  }
}
