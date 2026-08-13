import SwiftUI

#if canImport(BreezeHardware)
  import BreezeHardware
#endif
#if canImport(BreezeIPC)
  import BreezeIPC
#endif

struct MenuBarView: View {
  let state: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      content
      Divider()
      footer
    }
    .padding(18)
    .frame(width: 360)
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
          Label("Showing last reading — \(error)", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
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
          state.automaticControlStatus?.isAutomatic == true ? "Apple Automatic" : "Cooling Control",
          systemImage: state.automaticControlStatus?.isAutomatic == true
            ? "checkmark.shield" : "fan"
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
        HStack {
          Button {
            state.applyBalancedPreset()
          } label: {
            Label(
              state.activeControlMode == .balanced ? "Balanced Active" : "Balanced",
              systemImage: "scale.3d")
          }
          .disabled(
            state.isApplyingPreset || state.isRestoringAutomaticControl
              || !state.fansApplyingControl.isEmpty)
          Button {
            state.applyCoolPreset()
          } label: {
            Label(
              state.activeControlMode == .cool ? "Cool Active" : "Cool",
              systemImage: "snowflake")
          }
          .disabled(
            state.isApplyingPreset || state.isRestoringAutomaticControl
              || !state.fansApplyingControl.isEmpty)
          if state.isApplyingPreset { ProgressView().controlSize(.small) }
          Spacer()
          Text("35% / 60%")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        ForEach(snapshot.fans) { fan in
          FanControlRow(fan: fan, state: state)
        }
        Button("Restore All to Apple Automatic") {
          state.restoreAutomaticControl()
        }
        .disabled(state.isRestoringAutomaticControl || !state.fansApplyingControl.isEmpty)
      }

      if let status = state.automaticControlStatus {
        Text(status.message)
          .font(.caption)
          .foregroundStyle(status.isAutomatic ? Color.secondary : Color.orange)
      }
      if let preset = state.presetControlStatus {
        Text(
          preset.success
            ? "\(state.activeControlMode.rawValue.capitalized) targets: \(preset.targetRPMs.map { "\($0)" }.joined(separator: " / ")) RPM"
            : preset.message
        )
        .font(.caption)
        .foregroundStyle(preset.success ? Color.secondary : Color.red)
      }
      if let lease = state.controlLeaseStatus, lease.isActive {
        Label(
          "Safety watchdog active · \(lease.remainingSeconds)s lease",
          systemImage: "heart.text.square.fill")
          .font(.caption)
          .foregroundStyle(.green)
      }
      if let error = state.helperErrorMessage {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
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
        SettingsLink {
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

  private var activeModeLabel: String {
    switch state.activeControlMode {
    case .automatic: "Apple automatic"
    case .manual: "Manual control active"
    case .balanced: "Balanced active"
    case .cool: "Cool active"
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
    }
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
          }
        }
        Slider(value: $targetRPM, in: minimum...maximum, step: 50)
          .disabled(!state.canControlFan(fan.id) || state.fansApplyingControl.contains(fan.id))
        HStack {
          Text("\(Int(minimum.rounded()))")
          Spacer()
          Text("Target \(Int(targetRPM.rounded())) RPM").monospacedDigit()
          Spacer()
          Text("\(Int(maximum.rounded()))")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        HStack {
          Button("Apply Manual") {
            state.setFanRPM(fanID: fan.id, rpm: Int(targetRPM.rounded()))
          }
          Button("Automatic") { state.setFanAutomatic(fanID: fan.id) }
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
