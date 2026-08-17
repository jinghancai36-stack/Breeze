import AppKit
import SwiftUI

#if canImport(BreezeHardware)
  import BreezeHardware
#endif

@available(macOS 14.0, *)
struct SettingsView: View {
  @ObservedObject var state: AppState
  @AppStorage(PreferenceKey.menuBarDisplay)
  private var menuBarDisplay = MenuBarDisplay.temperatureAndRPM.rawValue
  @StateObject private var loginItem = LaunchAtLoginController()

  var body: some View {
    TabView {
      general
        .tabItem { Label(L10n.text("tab.general", fallback: "General"), systemImage: "gear") }
      curve
        .tabItem {
          Label(L10n.text("tab.curve", fallback: "Fan Curve"), systemImage: "chart.xyaxis.line")
        }
      hardware
        .tabItem { Label(L10n.text("tab.hardware", fallback: "Hardware"), systemImage: "cpu") }
      helper
        .tabItem { Label(L10n.text("tab.helper", fallback: "Helper"), systemImage: "lock.shield") }
      about
        .tabItem { Label(L10n.text("tab.about", fallback: "About"), systemImage: "info.circle") }
    }
    .frame(width: 500, height: 420)
    .onAppear {
      loginItem.refresh()
      state.refreshHelperStatus()
    }
  }

  private var curve: some View {
    Form {
      Section(L10n.text("curve.title", fallback: "Automatic Curve")) {
        Toggle(
          L10n.text("curve.enableSetting", fallback: "Enable Automatic Fan Curve"),
          isOn: Binding(
            get: { state.isFanCurveEnabled },
            set: { enabled in
              if enabled { state.enableFanCurve() } else { state.disableFanCurve() }
            }
          )
        )
        .disabled(
          state.isApplyingPreset || state.isRestoringAutomaticControl
            || !state.fansApplyingControl.isEmpty)

        LabeledContent(L10n.text("curve.sensor", fallback: "Control sensor")) {
          Text(curveSensorTitle)
        }
        LabeledContent(L10n.text("curve.currentStage", fallback: "Current stage")) {
          Text(curveStageTitle)
        }
        if let temperature = state.fanCurveTemperature {
          LabeledContent(L10n.text("curve.controlTemperature", fallback: "Control temperature")) {
            Text("\(temperature.formatted(.number.precision(.fractionLength(1)))) °C")
              .monospacedDigit()
          }
        }
        if let percent = state.fanCurveTargetPercent {
          LabeledContent(L10n.text("curve.target", fallback: "Fan target")) {
            Text("\(percent)%").monospacedDigit()
          }
        }
      }

      Section {
        ForEach(Array(state.fanCurveConfiguration.points.enumerated()), id: \.element.id) {
          index, point in
          curveThresholdRow(
            stage: L10n.format("curve.pointNumber", fallback: "Point %d", index + 1),
            range: "\(point.temperature) °C · \(point.fanPercent)%")
        }
      } header: {
        Text(L10n.text("curve.thresholds", fallback: "Saved Curve Points"))
      } footer: {
        Text(
          L10n.text(
            "curve.hysteresis",
            fallback:
              "Rising targets apply immediately. Decreases use the saved hysteresis and delay to prevent rapid switching. Edit the curve in the Breeze window."
          ))
      }

      Section(L10n.text("settings.safety", fallback: "Safety")) {
        Text(
          L10n.text(
            "curve.safetyBody",
            fallback:
              "While enabled, every interpolated curve target remains under Breeze's watchdog. The curve starts disabled after every launch and wake, and any Helper or watchdog failure returns control to Apple."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  private func curveThresholdRow(stage: String, range: String) -> some View {
    LabeledContent(stage, value: range)
  }

  private var curveStageTitle: String {
    switch state.fanCurveStage {
    case .automatic: L10n.text("mode.appleAutomaticTitle", fallback: "Apple Automatic")
    case .quiet: L10n.text("mode.quiet", fallback: "Quiet")
    case .balanced: L10n.text("mode.balanced", fallback: "Balanced")
    case .cool: L10n.text("mode.cool", fallback: "Cool")
    case .max: L10n.text("mode.max", fallback: "Max")
    }
  }

  private var curveSensorTitle: String {
    switch state.fanCurveConfiguration.sensorSource {
    case .cpuGPUPeak: L10n.text("curve.sensorPeak", fallback: "CPU/GPU Peak")
    case .cpu: L10n.text("temperature.cpu", fallback: "CPU")
    case .gpu: L10n.text("temperature.gpu", fallback: "GPU")
    }
  }

  private var general: some View {
    Form {
      Section(L10n.text("settings.startup", fallback: "Startup")) {
        Toggle(
          L10n.text("settings.launchAtLogin", fallback: "Launch Breeze at Login"),
          isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
          )
        )
        if loginItem.requiresApproval {
          LabeledContent(L10n.text("settings.approval", fallback: "Approval")) {
            Button(L10n.text("action.openLoginItems", fallback: "Open Login Items")) {
              loginItem.openSystemSettings()
            }
          }
        }
        if let error = loginItem.errorMessage {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Section(L10n.text("settings.menuBar", fallback: "Menu Bar")) {
        Picker(L10n.text("settings.display", fallback: "Display"), selection: $menuBarDisplay) {
          ForEach(MenuBarDisplay.allCases) { mode in
            Text(mode.title).tag(mode.rawValue)
          }
        }
      }

      Section(L10n.text("settings.monitoring", fallback: "Monitoring")) {
        LabeledContent(
          L10n.text("settings.popoverRefresh", fallback: "Popover refresh"),
          value: L10n.text("duration.oneSecond", fallback: "1 second"))
        LabeledContent(
          L10n.text("settings.backgroundRefresh", fallback: "Background refresh"),
          value: L10n.text("duration.fiveSeconds", fallback: "5 seconds"))
      }

      Section(L10n.text("settings.safety", fallback: "Safety")) {
        Text(
          L10n.text(
            "settings.safetyBody",
            fallback:
              "Breeze always starts in Apple Automatic mode and never resumes an active fan mode after relaunch or wake."
          )
        )
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
        Section(L10n.text("hardware.mac", fallback: "Mac")) {
          LabeledContent(
            L10n.text("hardware.model", fallback: "Model"), value: snapshot.hardware.modelIdentifier
          )
          LabeledContent(
            L10n.text("hardware.chip", fallback: "Chip"), value: snapshot.hardware.chipName)
          LabeledContent(
            L10n.text("hardware.architecture", fallback: "Architecture"),
            value: snapshot.hardware.architecture)
          LabeledContent(
            L10n.text("hardware.fanCount", fallback: "Fan count"),
            value: snapshot.hardware.fanCount.formatted())
          LabeledContent(
            L10n.text("hardware.controlStatus", fallback: "Control status"),
            value: snapshot.hardware.isControlVerified
              ? L10n.text("status.verified", fallback: "Verified")
              : L10n.text("status.monitorOnly", fallback: "Monitor only"))
        }

        Section(L10n.text("hardware.fans", fallback: "Fans")) {
          ForEach(snapshot.fans) { fan in
            VStack(alignment: .leading, spacing: 4) {
              Text(L10n.format("fan.number", fallback: "Fan %d", fan.id + 1))
                .fontWeight(.medium)
              Text(
                L10n.format("fan.reportedRange", fallback: "Reported range: %@", range(for: fan))
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
        }
      } else {
        ContentUnavailableView(
          L10n.text("hardware.unavailable", fallback: "Hardware unavailable"), systemImage: "cpu")
      }

      Section(L10n.text("diagnostics.title", fallback: "Hardware Diagnostics")) {
        DiagnosticReportActionsView(state: state)
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  private var helper: some View {
    Form {
      Section(L10n.text("helper.privileged", fallback: "Privileged Helper")) {
        LabeledContent(
          L10n.text("helper.registration", fallback: "Registration"), value: helperStatusText)
        LabeledContent(L10n.text("helper.connection", fallback: "Connection")) {
          if state.isCheckingHelper {
            ProgressView()
              .controlSize(.small)
          } else {
            Text(
              state.helperVersion.map {
                L10n.format("helper.connected", fallback: "Connected · v%@", $0)
              } ?? L10n.text("status.notChecked", fallback: "Not checked"))
          }
        }

        if let error = state.helperErrorMessage {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Section(L10n.text("helper.automaticControl", fallback: "Automatic Control")) {
        LabeledContent(L10n.text("helper.state", fallback: "State")) {
          if state.isRestoringAutomaticControl {
            ProgressView().controlSize(.small)
          } else if let status = state.automaticControlStatus {
            Text(
              status.isAutomatic
                ? L10n.text("mode.appleAutomatic", fallback: "Apple automatic")
                : L10n.text("status.notVerified", fallback: "Not verified"))
          } else {
            Text(L10n.text("status.notChecked", fallback: "Not checked"))
          }
        }
        if let status = state.automaticControlStatus {
          LabeledContent(
            L10n.text("helper.fanModes", fallback: "Fan modes"),
            value: status.fanModes.map(String.init).joined(separator: ", "))
          LabeledContent(
            "Ftst",
            value: status.forceTest.map(String.init)
              ?? L10n.text("status.unavailable", fallback: "Unavailable"))
        }
        HStack {
          Button(L10n.text("action.checkState", fallback: "Check State")) {
            state.checkAutomaticControl()
          }
          Button(L10n.text("action.restoreAutomatic", fallback: "Restore Apple Automatic")) {
            state.restoreAutomaticControl()
          }
          .disabled(state.isRestoringAutomaticControl)
        }
        .disabled(state.helperStatus != .enabled)
      }

      Section {
        HStack {
          switch state.helperStatus {
          case .enabled:
            Button(L10n.text("action.testConnection", fallback: "Test Connection")) {
              state.pingHelper()
            }
            .disabled(state.isCheckingHelper)
            Button(L10n.text("action.removeHelper", fallback: "Remove Helper"), role: .destructive)
            { state.uninstallHelper() }
          case .requiresApproval:
            Button(L10n.text("action.openLoginItems", fallback: "Open Login Items")) {
              state.openHelperApprovalSettings()
            }
            Button(L10n.text("action.refresh", fallback: "Refresh")) { state.refreshHelperStatus() }
          case .notRegistered, .notFound:
            Button(L10n.text("action.installHelper", fallback: "Install Helper")) {
              state.installHelper()
            }
          }
        }
      } footer: {
        Text(
          L10n.text(
            "helper.safetyFooter",
            fallback:
              "Breeze permits only verified fan 0/1 control, fixed presets, and curve targets from 20% to 100% in 5% steps on MacBookPro18,3. Every target is calculated independently from each fan's detected min/max range. A fixed Helper watchdog restores Automatic if heartbeats stop; arbitrary SMC operations and caller-controlled timeouts are not exposed."
          )
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
          Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .scaledToFit()
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 3) {
            Text("Breeze")
              .font(.title2.weight(.semibold))
            Text(
              L10n.text(
                "about.tagline",
                fallback: "A lightweight, native fan controller for Apple Silicon Macs.")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 4)
      }

      Section(L10n.text("about.build", fallback: "Build")) {
        LabeledContent(L10n.text("about.version", fallback: "Version"), value: appVersion)
        LabeledContent(L10n.text("about.buildNumber", fallback: "Build"), value: buildNumber)
        LabeledContent(L10n.text("about.minimumMacOS", fallback: "Minimum macOS"), value: "12.0")
        LabeledContent(L10n.text("about.license", fallback: "License"), value: "MIT")
      }

      Section(L10n.text("about.support", fallback: "Support")) {
        LabeledContent(
          L10n.text("about.verifiedModel", fallback: "Verified control model"),
          value: "MacBookPro18,3")
        Text(
          L10n.text(
            "about.monitorOnly",
            fallback:
              "Other Apple Silicon Macs remain Monitor Only until their fan-control behavior is independently verified."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      Section(L10n.text("about.hardwareNotice", fallback: "Hardware Notice")) {
        Text(
          L10n.text(
            "about.hardwareNoticeBody",
            fallback:
              "Breeze uses undocumented AppleSMC interfaces. Fan control availability can vary by model and macOS version."
          )
        )
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
    case .notRegistered: L10n.text("helper.notInstalled", fallback: "Not installed")
    case .enabled: L10n.text("helper.enabled", fallback: "Enabled")
    case .requiresApproval: L10n.text("helper.approvalRequired", fallback: "Approval required")
    case .notFound: L10n.text("helper.missing", fallback: "Helper missing from app bundle")
    }
  }

  private func range(for fan: FanState) -> String {
    guard let minimum = fan.minimumRPM, let maximum = fan.maximumRPM else {
      return L10n.text("status.unknown", fallback: "Unknown")
    }
    return "\(Int(minimum.rounded()).formatted())–\(Int(maximum.rounded()).formatted()) RPM"
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
  }

  private var buildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Local"
  }
}

@available(macOS 14.0, *)
private struct SettingsPreview: View {
  var body: some View {
    SettingsView(state: .preview)
  }
}
