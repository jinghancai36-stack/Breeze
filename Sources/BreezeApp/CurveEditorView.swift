import Charts
import SwiftUI

struct CurveEditorView: View {
  let state: AppState
  @State private var draft: FanCurveConfiguration
  @State private var savedMessage: String?

  init(state: AppState) {
    self.state = state
    _draft = State(initialValue: state.fanCurveConfiguration)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(L10n.text("curve.editorTitle", fallback: "Custom Curve"))
            .font(.headline)
          Text(
            L10n.text(
              "curve.editorSubtitle",
              fallback: "Targets are interpolated and rounded to safe 5% steps."))
          .font(.callout)
          .foregroundStyle(.secondary)
        }
        Spacer()
        if state.isFanCurveEnabled {
          Label(
            L10n.text("curve.disableToEdit", fallback: "Disable the curve to edit"),
            systemImage: "lock.fill")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }

      curveChart

      Picker(
        L10n.text("curve.sensor", fallback: "Control sensor"),
        selection: $draft.sensorSource
      ) {
        ForEach(CurveSensorSource.allCases) { source in
          Text(sensorTitle(source)).tag(source)
        }
      }
      .pickerStyle(.segmented)
      .disabled(state.isFanCurveEnabled)

      VStack(spacing: 12) {
        HStack {
          Text(
            L10n.format(
              "curve.pointCount", fallback: "%d curve points", draft.points.count))
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
          Spacer()
          Button {
            if draft.addInterpolatedPoint() { savedMessage = nil }
          } label: {
            Label(L10n.text("action.addPoint", fallback: "Add Point"), systemImage: "plus")
          }
          .disabled(state.isFanCurveEnabled || !canAddPoint)
        }

        ForEach(Array(draft.points.enumerated()), id: \.element.id) { index, point in
          curvePointRow(index: index, pointID: point.id)
        }
      }

      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
        GridRow {
          Text(L10n.text("curve.hysteresisLabel", fallback: "Decrease hysteresis"))
          Slider(value: hysteresisBinding, in: 0...10, step: 1)
          Text("\(Int(draft.hysteresis)) °C")
            .monospacedDigit()
            .frame(width: 46, alignment: .trailing)
        }
        GridRow {
          Text(L10n.text("curve.delayLabel", fallback: "Decrease delay"))
          Slider(value: delayBinding, in: 0...30, step: 1)
          Text("\(Int(draft.decreaseDelaySeconds)) s")
            .monospacedDigit()
            .frame(width: 46, alignment: .trailing)
        }
      }
      .disabled(state.isFanCurveEnabled)

      HStack {
        Button(L10n.text("action.saveCurve", fallback: "Save Curve")) {
          savedMessage = state.saveFanCurveConfiguration(draft)
            ? L10n.text("curve.saved", fallback: "Curve saved")
            : L10n.text("curve.invalid", fallback: "Curve settings are invalid")
        }
        .buttonStyle(.borderedProminent)
        .disabled(state.isFanCurveEnabled || !draft.isValid || draft == state.fanCurveConfiguration)

        Button(L10n.text("action.resetCurve", fallback: "Reset to Default")) {
          draft = .default
          savedMessage = nil
        }
        .disabled(state.isFanCurveEnabled || draft == .default)

        Spacer()
        if let savedMessage {
          Label(savedMessage, systemImage: draft.isValid ? "checkmark.circle" : "xmark.circle")
            .font(.callout)
            .foregroundStyle(draft.isValid ? .green : .red)
        } else if !draft.isValid {
          Label(
            L10n.text("curve.invalid", fallback: "Curve settings are invalid"),
            systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
        }
      }
    }
    .onChange(of: state.fanCurveConfiguration) { _, configuration in
      draft = configuration
    }
  }

  private var curveChart: some View {
    Chart {
      ForEach(draft.points) { point in
        LineMark(
          x: .value("Temperature", point.temperature),
          y: .value("Fan", point.fanPercent))
          .interpolationMethod(.linear)
        PointMark(
          x: .value("Temperature", point.temperature),
          y: .value("Fan", point.fanPercent))
          .symbolSize(70)
      }
      if let temperature = state.fanCurveTemperature {
        RuleMark(x: .value("Current", temperature))
          .foregroundStyle(.orange)
          .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
          .annotation(position: .top, alignment: .leading) {
            Text("\(temperature.formatted(.number.precision(.fractionLength(1)))) °C")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
      }
    }
    .chartXScale(domain: FanCurveConfiguration.minimumTemperature...FanCurveConfiguration.maximumTemperature)
    .chartYScale(domain: FanCurveConfiguration.minimumFanPercent...FanCurveConfiguration.maximumFanPercent)
    .chartXAxisLabel(L10n.text("curve.temperatureAxis", fallback: "Temperature (°C)"))
    .chartYAxisLabel(L10n.text("curve.fanAxis", fallback: "Fan (%)"))
    .frame(height: 230)
    .padding(.vertical, 4)
  }

  private func curvePointRow(index: Int, pointID: FanCurvePoint.ID) -> some View {
    let point = draft.points[index]
    return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
      GridRow {
        Text(
          L10n.format("curve.pointNumber", fallback: "Point %d", index + 1))
          .fontWeight(.medium)
          .frame(width: 58, alignment: .leading)
        Slider(
          value: temperatureBinding(index),
          in: temperatureRange(index), step: 1)
        Text("\(point.temperature) °C")
          .monospacedDigit()
          .frame(width: 48, alignment: .trailing)
        Slider(
          value: percentBinding(index),
          in: percentRange(index),
          step: Double(FanCurveConfiguration.percentageStep))
        Text("\(point.fanPercent)%")
          .monospacedDigit()
          .frame(width: 42, alignment: .trailing)
        Button {
          if draft.removePoint(id: pointID) { savedMessage = nil }
        } label: {
          Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .help(L10n.text("action.removePoint", fallback: "Remove Point"))
        .disabled(draft.points.count <= FanCurveConfiguration.minimumPointCount)
      }
    }
    .disabled(state.isFanCurveEnabled)
  }

  private var canAddPoint: Bool {
    var candidate = draft
    return candidate.addInterpolatedPoint()
  }

  private func temperatureBinding(_ index: Int) -> Binding<Double> {
    Binding(
      get: { Double(draft.points[index].temperature) },
      set: {
        draft.points[index].temperature = Int($0.rounded())
        savedMessage = nil
      })
  }

  private func percentBinding(_ index: Int) -> Binding<Double> {
    Binding(
      get: { Double(draft.points[index].fanPercent) },
      set: {
        draft.points[index].fanPercent = Int($0.rounded())
        savedMessage = nil
      })
  }

  private var hysteresisBinding: Binding<Double> {
    Binding(
      get: { draft.hysteresis },
      set: { draft.hysteresis = $0; savedMessage = nil })
  }

  private var delayBinding: Binding<Double> {
    Binding(
      get: { draft.decreaseDelaySeconds },
      set: { draft.decreaseDelaySeconds = $0; savedMessage = nil })
  }

  private func temperatureRange(_ index: Int) -> ClosedRange<Double> {
    let minimum = index == 0
      ? FanCurveConfiguration.minimumTemperature
      : draft.points[index - 1].temperature + FanCurveConfiguration.minimumPointSpacing
    let maximum = index == draft.points.count - 1
      ? FanCurveConfiguration.maximumTemperature
      : draft.points[index + 1].temperature - FanCurveConfiguration.minimumPointSpacing
    return Double(minimum)...Double(maximum)
  }

  private func percentRange(_ index: Int) -> ClosedRange<Double> {
    let minimum = index == 0
      ? FanCurveConfiguration.minimumFanPercent
      : draft.points[index - 1].fanPercent
    let maximum = index == draft.points.count - 1
      ? FanCurveConfiguration.maximumFanPercent
      : draft.points[index + 1].fanPercent
    return Double(minimum)...Double(maximum)
  }

  private func sensorTitle(_ source: CurveSensorSource) -> String {
    switch source {
    case .cpuGPUPeak:
      L10n.text("curve.sensorPeak", fallback: "CPU/GPU Peak")
    case .cpu:
      L10n.text("temperature.cpu", fallback: "CPU")
    case .gpu:
      L10n.text("temperature.gpu", fallback: "GPU")
    }
  }
}

struct ThermalHistoryChart: View {
  let samples: [ThermalHistorySample]

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(L10n.text("dashboard.temperatureHistory", fallback: "Temperature"))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Chart {
        ForEach(samples) { sample in
          if let cpu = sample.cpuTemperature {
            LineMark(
              x: .value("Time", sample.id),
              y: .value("Temperature", cpu),
              series: .value("Sensor", "CPU"))
              .foregroundStyle(by: .value("Sensor", "CPU"))
          }
          if let gpu = sample.gpuTemperature {
            LineMark(
              x: .value("Time", sample.id),
              y: .value("Temperature", gpu),
              series: .value("Sensor", "GPU"))
              .foregroundStyle(by: .value("Sensor", "GPU"))
          }
        }
      }
      .chartYScale(domain: 20...105)
      .chartYAxisLabel("°C")
      .frame(height: 150)

      Text(L10n.text("dashboard.fanHistory", fallback: "Fan Speed"))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Chart(fanValues) { value in
        LineMark(
          x: .value("Time", value.date),
          y: .value("RPM", value.rpm),
          series: .value("Fan", "Fan \(value.fanID + 1)"))
          .foregroundStyle(by: .value("Fan", "Fan \(value.fanID + 1)"))
      }
      .chartYScale(domain: 0...7_000)
      .chartYAxisLabel("RPM")
      .frame(height: 150)
    }
  }

  private var fanValues: [FanHistoryValue] {
    samples.flatMap { sample in
      sample.fanRPMs.enumerated().map { fanID, rpm in
        FanHistoryValue(date: sample.id, fanID: fanID, rpm: rpm)
      }
    }
  }
}

private struct FanHistoryValue: Identifiable {
  let date: Date
  let fanID: Int
  let rpm: Double

  var id: String { "\(date.timeIntervalSinceReferenceDate)-\(fanID)" }
}
