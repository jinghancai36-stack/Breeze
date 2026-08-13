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
          state.refreshNow()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
        .help("Refresh now")
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
            message: "Showing the last good reading. \(error)",
            systemImage: "exclamationmark.triangle.fill",
            color: .orange
          ) {
            Button("Retry") { state.refreshNow() }
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
        "Hardware unavailable",
        systemImage: "exclamationmark.triangle",
        description: Text(state.errorMessage ?? "Unable to read AppleSMC.")
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
        Text("Enable the privileged helper in Settings first.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else if state.helperVersion != BreezeHelperConstants.helperVersion {
        Text(
          "Active control requires matching Helper v\(BreezeHelperConstants.helperVersion). "
            + "Update or approve the Helper in Settings.")
          .font(.caption)
          .foregroundStyle(.orange)
      } else if !snapshot.hardware.isControlVerified {
        Text("This Mac is in Monitor Only mode because manual control is not verified.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        presetControls
        Divider()
        HStack {
          Text("Manual Control")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Spacer()
          Text("Per fan")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        ForEach(snapshot.fans) { fan in
          FanControlRow(fan: fan, state: state)
        }
        Button {
          state.restoreAutomaticControl()
        } label: {
          Text("Restore All to Apple Automatic")
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
            "\(state.activeControlMode.rawValue.capitalized) targets: \(preset.targetRPMs.map { "\($0)" }.joined(separator: " / ")) RPM"
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
          "Safety watchdog active · \(lease.remainingSeconds)s lease",
          systemImage: "heart.text.square.fill")
          .font(.caption)
          .foregroundStyle(.green)
      }
      if let error = state.helperErrorMessage {
        StatusMessage(
          message: error,
          systemImage: "exclamationmark.triangle.fill",
          color: .red
        ) {
          Button("Check Safety") { state.checkAutomaticControl() }
            .controlSize(.small)
            .disabled(state.isRestoringAutomaticControl)
        }
      }
    }
  }

  private var presetControls: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Presets")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        if state.isApplyingPreset { ProgressView().controlSize(.small) }
      }
      HStack(spacing: 8) {
        presetButton("Balanced", systemImage: "scale.3d", mode: .balanced) {
          state.applyBalancedPreset()
        }
        presetButton("Cool", systemImage: "snowflake", mode: .cool) {
          state.applyCoolPreset()
        }
        presetButton("Max", systemImage: "fan.fill", mode: .max) {
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
        metricRow("MEMORY", temperature(sensor))
      }
      if let sensor = snapshot.batteryTemperature {
        metricRow("BATTERY", temperature(sensor))
      }
      if snapshot.sensors.isEmpty {
        Text("No supported thermal sensors detected.")
          .foregroundStyle(.secondary)
      }
    }
  }

  private func fans(_ fans: [FanState]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if fans.isEmpty {
        Text("No controllable fans detected.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(fans) { fan in
          metricRow("Fan \(fan.id + 1)", "\(Int(fan.currentRPM.rounded()).formatted()) RPM")
        }
      }
    }
  }

  private var footer: some View {
    VStack(spacing: 10) {
      HStack {
        Label(
          activeModeLabel,
          systemImage: "lock.shield")
          .foregroundStyle(.secondary)
        Spacer()
        if let updated = state.lastSuccessfulUpdate {
          Text("Updated \(updated, style: .relative)")
            .foregroundStyle(.tertiary)
        }
      }
      .font(.caption)

      HStack {
        Button {
          showSettings()
        } label: {
          Label("Settings", systemImage: "gear")
        }
        .buttonStyle(.plain)
        Spacer()
        Button("Quit Breeze") {
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

  private var activeModeLabel: String {
    switch state.activeControlMode {
    case .automatic: "Apple automatic"
    case .manual: "Manual control active"
    case .balanced: "Balanced active"
    case .cool: "Cool active"
    case .max: "Max active"
    }
  }

  private var activeControlTitle: String {
    switch state.activeControlMode {
    case .automatic: "Apple Automatic"
    case .manual: "Manual Control"
    case .balanced: "Balanced"
    case .cool: "Cool"
    case .max: "Max"
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
          Text("Fan \(fan.id + 1)").fontWeight(.medium)
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
          .accessibilityLabel("Fan \(fan.id + 1) target speed")
          .accessibilityValue("\(Int(targetRPM.rounded())) RPM")
        HStack {
          Text("\(Int(minimum.rounded()))")
          Spacer()
          Text("Target \(Int(targetRPM.rounded())) RPM")
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
            Text("Apply Manual")
              .frame(maxWidth: .infinity)
          }
          Button {
            state.setFanAutomatic(fanID: fan.id)
          } label: {
            Text("Automatic")
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
