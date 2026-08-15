import AppKit
import SwiftUI

#if canImport(BreezeHardware)
  import BreezeHardware
#endif
#if canImport(BreezeIPC)
  import BreezeIPC
#endif

struct MenuBarView: View {
  let state: AppState
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      content
      Divider()
      footer
    }
    .padding(18)
    .frame(width: 380)
    .onAppear { state.setPopoverVisible(true) }
    .onDisappear { state.setPopoverVisible(false) }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text("Breeze")
          .font(.title2.weight(.semibold))
        Spacer()
        Button {
          showDashboard()
        } label: {
          Image(systemName: "macwindow")
        }
        .buttonStyle(.plain)
        .help(L10n.text("action.openDashboard", fallback: "Open Breeze window"))
        Button {
          state.refreshNow()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
        .help(L10n.text("action.refreshNow", fallback: "Refresh now"))
      }
      Text(state.snapshot?.hardware.modelIdentifier ?? "Apple Silicon Mac")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var content: some View {
    if state.isLoading {
      HStack {
        Spacer()
        ProgressView()
        Spacer()
      }
      .padding(.vertical, 28)
    } else if let snapshot = state.snapshot {
      VStack(alignment: .leading, spacing: 14) {
        if let error = state.errorMessage {
          StatusMessage(
            message: L10n.format(
              "error.lastReading", fallback: "Showing the last good reading. %@", error),
            systemImage: "exclamationmark.triangle.fill",
            color: .orange
          ) {
            Button(L10n.text("action.retry", fallback: "Retry")) { state.refreshNow() }
              .controlSize(.small)
          }
        }
        temperatures(snapshot)
        Divider()
        fans(snapshot.fans)
        if !snapshot.fans.isEmpty {
          Divider()
          fanControls(snapshot)
        }
      }
    } else {
      ContentUnavailableView(
        L10n.text("hardware.unavailable", fallback: "Hardware unavailable"),
        systemImage: "exclamationmark.triangle",
        description: Text(
          state.errorMessage ?? L10n.text("error.smcRead", fallback: "Unable to read AppleSMC."))
      )
    }
  }

  private func fanControls(_ snapshot: HardwareSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label(
          activeControlTitle,
          systemImage: state.activeControlMode == .automatic ? "checkmark.shield" : "fan"
        )
        Spacer()
        if state.isRestoringAutomaticControl {
          ProgressView().controlSize(.small)
        }
      }
      if state.helperStatus != .enabled {
        Text(
          L10n.text(
            "helper.enableFirst", fallback: "Enable the privileged helper in Settings first.")
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } else if state.helperVersion != BreezeHelperConstants.helperVersion {
        Text(
          L10n.format(
            "helper.versionMismatch",
            fallback:
              "Active control requires matching Helper v%@. Update or approve the Helper in Settings.",
            BreezeHelperConstants.helperVersion)
        )
        .font(.caption)
        .foregroundStyle(.orange)
      } else if !snapshot.hardware.isControlVerified {
        Text(
          L10n.text(
            "helper.monitorOnly",
            fallback: "This Mac is in Monitor Only mode because manual control is not verified.")
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } else {
        curveControl
        presetControls
        Divider()
        HStack {
          Text(L10n.text("control.manual", fallback: "Manual Control"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Spacer()
          Text(L10n.text("control.perFan", fallback: "Per fan"))
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        ForEach(snapshot.fans) { fan in
          FanControlRow(fan: fan, state: state)
        }
        Button {
          state.restoreAutomaticControl()
        } label: {
          Text(L10n.text("action.restoreAll", fallback: "Restore All to Apple Automatic"))
            .frame(maxWidth: .infinity)
        }
        .disabled(state.isRestoringAutomaticControl || !state.fansApplyingControl.isEmpty)
      }

      if let status = state.automaticControlStatus {
        if status.isAutomatic {
          Label(status.message, systemImage: "checkmark.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          StatusMessage(
            message: status.message,
            systemImage: "exclamationmark.triangle.fill",
            color: .orange)
        }
      }
      if let preset = state.presetControlStatus {
        if preset.success {
          Text(
            L10n.format(
              "status.presetTargets", fallback: "%@ targets: %@ RPM",
              state.isFanCurveEnabled ? fanCurveStageTitle : activeControlTitle,
              preset.targetRPMs.map { "\($0)" }.joined(separator: " / "))
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        } else {
          StatusMessage(
            message: preset.message,
            systemImage: "exclamationmark.triangle.fill",
            color: .red)
        }
      }
      if let lease = state.controlLeaseStatus, lease.isActive {
        Label(
          L10n.format(
            "watchdog.active", fallback: "Safety watchdog active · %ds lease",
            lease.remainingSeconds),
          systemImage: "heart.text.square.fill"
        )
        .font(.caption)
        .foregroundStyle(.green)
      }
      if let error = state.helperErrorMessage {
        StatusMessage(
          message: error,
          systemImage: "exclamationmark.triangle.fill",
          color: .red
        ) {
          Button(L10n.text("action.checkSafety", fallback: "Check Safety")) {
            state.checkAutomaticControl()
          }
          .controlSize(.small)
          .disabled(state.isRestoringAutomaticControl)
        }
      }
    }
  }

  private var curveControl: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.text("curve.title", fallback: "Automatic Curve"))
            .font(.caption.weight(.semibold))
          Text(
            L10n.format(
              "curve.summary",
              fallback: "%d saved points · interpolated in 5%% steps",
              state.fanCurveConfiguration.points.count)
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
        Spacer()
        Button(
          state.isFanCurveEnabled
            ? L10n.text("action.disable", fallback: "Disable")
            : L10n.text("action.enable", fallback: "Enable")
        ) {
          if state.isFanCurveEnabled {
            state.disableFanCurve()
          } else {
            state.enableFanCurve()
          }
        }
        .controlSize(.small)
        .disabled(
          state.isApplyingPreset || state.isRestoringAutomaticControl
            || !state.fansApplyingControl.isEmpty)
      }
      if state.isFanCurveEnabled, let temperature = state.fanCurveTemperature {
        Text(
          L10n.format(
            "curve.active", fallback: "Curve active · %@ · %@ °C", fanCurveStageTitle,
            temperature.formatted(.number.precision(.fractionLength(1))))
        )
        .font(.caption)
        .foregroundStyle(.green)
        if let percent = state.fanCurveTargetPercent {
          Text(L10n.format("curve.targetValue", fallback: "Interpolated target · %d%%", percent))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var presetControls: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(L10n.text("control.presets", fallback: "Presets"))
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        if state.isApplyingPreset { ProgressView().controlSize(.small) }
      }
      HStack(spacing: 8) {
        presetButton(
          L10n.text("mode.balanced", fallback: "Balanced"), systemImage: "scale.3d", mode: .balanced
        ) {
          state.applyBalancedPreset()
        }
        presetButton(
          L10n.text("mode.cool", fallback: "Cool"), systemImage: "snowflake", mode: .cool
        ) {
          state.applyCoolPreset()
        }
        presetButton(L10n.text("mode.max", fallback: "Max"), systemImage: "fan.fill", mode: .max) {
          state.applyMaxPreset()
        }
      }
      HStack(spacing: 8) {
        presetFraction("35%")
        presetFraction("60%")
        presetFraction("100%")
      }
    }
  }

  private func presetButton(
    _ title: String,
    systemImage: String,
    mode: ActiveFanControlMode,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(
        title,
        systemImage: state.activeControlMode == mode ? "checkmark.circle.fill" : systemImage
      )
      .frame(maxWidth: .infinity)
    }
    .disabled(
      state.isApplyingPreset || state.isRestoringAutomaticControl
        || !state.fansApplyingControl.isEmpty)
  }

  private func presetFraction(_ value: String) -> some View {
    Text(value)
      .font(.caption2)
      .foregroundStyle(.tertiary)
      .frame(maxWidth: .infinity)
  }

  private func temperatures(_ snapshot: HardwareSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if let sensor = snapshot.hottestTemperature(in: .cpu) {
        metricRow("CPU", temperature(sensor))
      }
      if let sensor = snapshot.hottestTemperature(in: .gpu) {
        metricRow("GPU", temperature(sensor))
      }
      if let sensor = snapshot.hottestTemperature(in: .memory) {
        metricRow(L10n.text("temperature.memory", fallback: "MEMORY"), temperature(sensor))
      }
      if let sensor = snapshot.batteryTemperature {
        metricRow(L10n.text("temperature.battery", fallback: "BATTERY"), temperature(sensor))
      }
      if snapshot.sensors.isEmpty {
        Text(L10n.text("temperature.none", fallback: "No supported thermal sensors detected."))
          .foregroundStyle(.secondary)
      }
    }
  }

  private func fans(_ fans: [FanState]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if fans.isEmpty {
        Text(L10n.text("fan.none", fallback: "No controllable fans detected."))
          .foregroundStyle(.secondary)
      } else {
        ForEach(fans) { fan in
          metricRow(
            L10n.format("fan.number", fallback: "Fan %d", fan.id + 1),
            "\(Int(fan.currentRPM.rounded()).formatted()) RPM")
        }
      }
    }
  }

  private var footer: some View {
    VStack(spacing: 10) {
      HStack {
        Label(
          activeModeLabel,
          systemImage: "lock.shield"
        )
        .foregroundStyle(.secondary)
        Spacer()
        if let updated = state.lastSuccessfulUpdate {
          HStack(spacing: 3) {
            Text(L10n.text("status.updated", fallback: "Updated"))
            Text(updated, style: .relative)
          }
          .foregroundStyle(.tertiary)
        }
      }
      .font(.caption)

      HStack {
        Button {
          showSettings()
        } label: {
          Label(L10n.text("action.settings", fallback: "Settings"), systemImage: "gear")
        }
        .buttonStyle(.plain)
        Spacer()
        Button(L10n.text("action.quit", fallback: "Quit Breeze")) {
          state.quitBreeze()
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func showSettings() {
    openSettings()
    NSApplication.shared.activate(ignoringOtherApps: true)

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(100))
      NSApplication.shared.activate(ignoringOtherApps: true)
      let settingsWindow = NSApplication.shared.windows
        .first { !($0 is NSPanel) && $0.canBecomeKey }
      settingsWindow?.makeKeyAndOrderFront(nil)
    }
  }

  private func showDashboard() {
    openWindow(id: DashboardWindow.sceneID, value: DashboardWindow.main)
    NSApplication.shared.activate(ignoringOtherApps: true)

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(100))
      NSApplication.shared.activate(ignoringOtherApps: true)
      NSApplication.shared.windows
        .first { $0.title == "Breeze" && !($0 is NSPanel) }?
        .makeKeyAndOrderFront(nil)
    }
  }

  private var activeModeLabel: String {
    if state.isFanCurveEnabled {
      return L10n.text("curve.activeShort", fallback: "Automatic curve active")
    }
    return switch state.activeControlMode {
    case .automatic: L10n.text("mode.appleAutomatic", fallback: "Apple automatic")
    case .curve: L10n.text("curve.activeShort", fallback: "Automatic curve active")
    case .manual: L10n.text("mode.manualActive", fallback: "Manual control active")
    case .balanced: L10n.text("mode.balancedActive", fallback: "Balanced active")
    case .cool: L10n.text("mode.coolActive", fallback: "Cool active")
    case .max: L10n.text("mode.maxActive", fallback: "Max active")
    }
  }

  private var activeControlTitle: String {
    if state.isFanCurveEnabled {
      return L10n.format("curve.titleStage", fallback: "Automatic Curve · %@", fanCurveStageTitle)
    }
    return switch state.activeControlMode {
    case .automatic: L10n.text("mode.appleAutomaticTitle", fallback: "Apple Automatic")
    case .curve: L10n.text("curve.title", fallback: "Automatic Curve")
    case .manual: L10n.text("control.manual", fallback: "Manual Control")
    case .balanced: L10n.text("mode.balanced", fallback: "Balanced")
    case .cool: L10n.text("mode.cool", fallback: "Cool")
    case .max: L10n.text("mode.max", fallback: "Max")
    }
  }

  private var fanCurveStageTitle: String {
    switch state.fanCurveStage {
    case .automatic: L10n.text("mode.appleAutomaticTitle", fallback: "Apple Automatic")
    case .quiet: L10n.text("mode.quiet", fallback: "Quiet")
    case .balanced: L10n.text("mode.balanced", fallback: "Balanced")
    case .cool: L10n.text("mode.cool", fallback: "Cool")
    case .max: L10n.text("mode.max", fallback: "Max")
    }
  }

  private func temperature(_ sensor: ThermalSensor) -> String {
    "\(sensor.temperature.formatted(.number.precision(.fractionLength(1)))) °C"
  }

  private func metricRow(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .monospacedDigit()
        .fontWeight(.medium)
        .contentTransition(.numericText())
        .animation(.easeInOut(duration: 0.2), value: value)
    }
  }
}

private struct StatusMessage<Actions: View>: View {
  let message: String
  let systemImage: String
  let color: Color
  @ViewBuilder let actions: () -> Actions

  init(
    message: String,
    systemImage: String,
    color: Color,
    @ViewBuilder actions: @escaping () -> Actions
  ) {
    self.message = message
    self.systemImage = systemImage
    self.color = color
    self.actions = actions
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: systemImage)
        .foregroundStyle(color)
        .padding(.top, 1)
      VStack(alignment: .leading, spacing: 6) {
        Text(message)
          .font(.caption)
          .fixedSize(horizontal: false, vertical: true)
        actions()
      }
      Spacer(minLength: 0)
    }
    .padding(8)
    .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
  }
}

extension StatusMessage where Actions == EmptyView {
  init(message: String, systemImage: String, color: Color) {
    self.init(message: message, systemImage: systemImage, color: color) { EmptyView() }
  }
}

private struct FanControlRow: View {
  let fan: FanState
  let state: AppState
  @State private var targetRPM: Double

  init(fan: FanState, state: AppState) {
    self.fan = fan
    self.state = state
    let minimum = fan.minimumRPM ?? fan.currentRPM
    let maximum = fan.maximumRPM ?? fan.currentRPM
    _targetRPM = State(initialValue: min(max(fan.currentRPM, minimum), maximum))
  }

  var body: some View {
    if let minimum = fan.minimumRPM, let maximum = fan.maximumRPM, minimum < maximum {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(L10n.format("fan.number", fallback: "Fan %d", fan.id + 1)).fontWeight(.medium)
          Spacer()
          if state.fansApplyingControl.contains(fan.id) {
            ProgressView().controlSize(.small)
          } else {
            Text("\(Int(fan.currentRPM.rounded()).formatted()) RPM")
              .monospacedDigit()
              .contentTransition(.numericText())
              .animation(.easeInOut(duration: 0.2), value: fan.currentRPM)
          }
        }
        Slider(value: $targetRPM, in: minimum...maximum, step: 50)
          .disabled(!state.canControlFan(fan.id) || state.fansApplyingControl.contains(fan.id))
          .accessibilityLabel(
            L10n.format("fan.targetSpeed", fallback: "Fan %d target speed", fan.id + 1)
          )
          .accessibilityValue("\(Int(targetRPM.rounded())) RPM")
        HStack {
          Text("\(Int(minimum.rounded()))")
          Spacer()
          Text(L10n.format("fan.targetRPM", fallback: "Target %d RPM", Int(targetRPM.rounded())))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.2), value: targetRPM)
          Spacer()
          Text("\(Int(maximum.rounded()))")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        HStack(spacing: 8) {
          Button {
            state.setFanRPM(fanID: fan.id, rpm: Int(targetRPM.rounded()))
          } label: {
            Text(L10n.text("action.applyManual", fallback: "Apply Manual"))
              .frame(maxWidth: .infinity)
          }
          Button {
            state.setFanAutomatic(fanID: fan.id)
          } label: {
            Text(L10n.text("action.automatic", fallback: "Automatic"))
              .frame(maxWidth: .infinity)
          }
        }
        .controlSize(.small)
        .disabled(!state.canControlFan(fan.id) || state.fansApplyingControl.contains(fan.id))
        if let report = state.fanControlStatuses[fan.id] {
          Text(report.message)
            .font(.caption2)
            .foregroundStyle(report.success ? Color.secondary : Color.red)
        }
      }
      .padding(.vertical, 3)
    }
  }
}

#Preview("Menu Bar") {
  MenuBarView(state: .preview)
}
