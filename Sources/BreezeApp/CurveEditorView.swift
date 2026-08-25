import Charts
import SwiftUI

@available(macOS 14.0, *)
struct CurveEditorView: View {
  @ObservedObject var state: AppState
  @State private var draft: FanCurveConfiguration
  @State private var savedMessage: String?
  @State private var draggedPointID: FanCurvePoint.ID?

  init(state: AppState) {
    self.state = state
    _draft = State(initialValue: state.fanCurveConfiguration)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(
            state.fanCurveMode == .automatic
              ? L10n.text("curve.profileAutomatic", fallback: "Breeze Full Automatic 45–90°C")
              : L10n.text("curve.editorTitle", fallback: "Custom Curve")
          )
          .font(.headline)
          Text(
            state.fanCurveMode == .automatic
              ? L10n.text(
                "curve.automaticShort",
                fallback: "Fan speed follows temperature automatically; no points need editing.")
              : L10n.text(
                "curve.editorSubtitle",
                fallback: "Targets are interpolated and rounded to safe 5% steps.")
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
        Spacer()
        if state.isFanCurveEnabled {
          Label(
            L10n.text("curve.disableToEdit", fallback: "Disable the curve to edit"),
            systemImage: "lock.fill"
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
      }

      Picker(
        L10n.text("curve.profile", fallback: "Control profile"),
        selection: Binding(
          get: { state.fanCurveMode },
          set: { state.setFanCurveMode($0) })
      ) {
        Text(L10n.text("curve.profileAutomatic", fallback: "Breeze Full Automatic 45–90°C"))
          .tag(FanCurveMode.automatic)
        Text(L10n.text("curve.profileCustom", fallback: "Advanced Custom"))
          .tag(FanCurveMode.custom)
      }
      .pickerStyle(.segmented)
      .disabled(state.isFanCurveEnabled)

      curveChart

      if state.fanCurveMode == .automatic {
        automaticPlanSummary
      } else {
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
                "curve.pointCount", fallback: "%d curve points", draft.points.count)
            )
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

          ForEach(draft.points) { point in
            curvePointRow(pointID: point.id)
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
            savedMessage =
              state.saveFanCurveConfiguration(draft)
              ? L10n.text("curve.saved", fallback: "Curve saved")
              : L10n.text("curve.invalid", fallback: "Curve settings are invalid")
          }
          .buttonStyle(.borderedProminent)
          .disabled(
            state.isFanCurveEnabled || !draft.isValid || draft == state.fanCurveConfiguration)

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
              systemImage: "exclamationmark.triangle.fill"
            )
            .font(.callout)
            .foregroundStyle(.red)
          }
        }
      }
    }
    .onChange(of: state.fanCurveConfiguration) { _, configuration in
      draft = configuration
    }
  }

  private var curveChart: some View {
    VStack(alignment: .leading, spacing: 6) {
      Chart {
        ForEach(displayConfiguration.points) { point in
          LineMark(
            x: .value("Temperature", point.temperature),
            y: .value("Fan", point.fanPercent)
          )
          .interpolationMethod(.linear)
          PointMark(
            x: .value("Temperature", point.temperature),
            y: .value("Fan", point.fanPercent)
          )
          .symbolSize(point.id == draggedPointID ? 130 : 85)
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
      .chartXScale(
        domain: FanCurveConfiguration.minimumTemperature...FanCurveConfiguration.maximumTemperature
      )
      .chartYScale(
        domain: FanCurveConfiguration.minimumFanPercent...FanCurveConfiguration.maximumFanPercent
      )
      .chartXAxisLabel(L10n.text("curve.temperatureAxis", fallback: "Temperature (°C)"))
      .chartYAxisLabel(L10n.text("curve.fanAxis", fallback: "Fan (%)"))
      .chartOverlay { proxy in
        GeometryReader { geometry in
          Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .gesture(
              DragGesture(minimumDistance: 2)
                .onChanged { value in
                  dragCurvePoint(at: value.location, proxy: proxy, geometry: geometry)
                }
                .onEnded { _ in
                  draggedPointID = nil
                }
            )
            .allowsHitTesting(state.fanCurveMode == .custom && !state.isFanCurveEnabled)
        }
      }
      .frame(height: 230)

      Label(
        state.fanCurveMode == .automatic
          ? L10n.text(
            "curve.automaticDescription",
            fallback:
              "Breeze uses a quiet low-temperature curve, accelerates cooling above 70°C, and leads rapidly rising temperatures by up to 5°C. Targets remain in safe 5% steps; decreases use a 2°C hysteresis and 3-second delay."
          )
          : L10n.text(
            "curve.dragHint",
            fallback: "Drag a chart point to adjust temperature and fan speed."),
        systemImage: state.fanCurveMode == .automatic ? "wand.and.stars" : "cursorarrow.motionlines"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }

  private var displayConfiguration: FanCurveConfiguration {
    state.fanCurveMode == .automatic ? .automatic : draft
  }

  private var automaticPlanSummary: some View {
    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
      GridRow {
        Label(L10n.text("curve.idlePoint", fallback: "Idle"), systemImage: "leaf")
        Text("45 °C")
        Text("20%")
      }
      GridRow {
        Label(L10n.text("curve.maximumPoint", fallback: "Maximum"), systemImage: "flame")
        Text("90 °C")
        Text("100%")
      }
      GridRow {
        Label(L10n.text("curve.response", fallback: "Response"), systemImage: "waveform.path")
        Text(L10n.text("curve.responseValue", fallback: "Continuous · 5% steps"))
          .gridCellColumns(2)
      }
    }
    .monospacedDigit()
    .padding(.vertical, 4)
  }

  private func dragCurvePoint(
    at location: CGPoint,
    proxy: ChartProxy,
    geometry: GeometryProxy
  ) {
    guard let plotFrameAnchor = proxy.plotFrame else { return }
    let plotFrame = geometry[plotFrameAnchor]
    let plotLocation = CGPoint(
      x: min(max(location.x, plotFrame.minX), plotFrame.maxX) - plotFrame.minX,
      y: min(max(location.y, plotFrame.minY), plotFrame.maxY) - plotFrame.minY)

    if draggedPointID == nil {
      draggedPointID = nearestPointID(to: plotLocation, proxy: proxy)
    }
    guard let draggedPointID,
      let values = proxy.value(at: plotLocation, as: (Double, Double).self),
      draft.movePoint(id: draggedPointID, temperature: values.0, fanPercent: values.1)
    else { return }
    savedMessage = nil
  }

  private func nearestPointID(to location: CGPoint, proxy: ChartProxy) -> FanCurvePoint.ID? {
    draft.points.compactMap { point -> (FanCurvePoint.ID, CGFloat)? in
      guard let position = proxy.position(for: (x: point.temperature, y: point.fanPercent))
      else { return nil }
      return (point.id, hypot(position.x - location.x, position.y - location.y))
    }
    .min { $0.1 < $1.1 }
    .flatMap { $0.1 <= 28 ? $0.0 : nil }
  }

  @ViewBuilder
  private func curvePointRow(pointID: FanCurvePoint.ID) -> some View {
    if let index = draft.points.firstIndex(where: { $0.id == pointID }),
      let temperatureRange = draft.temperatureRange(for: pointID),
      let percentRange = draft.fanPercentRange(for: pointID)
    {
      let point = draft.points[index]
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
        GridRow {
          Text(
            L10n.format("curve.pointNumber", fallback: "Point %d", index + 1)
          )
          .fontWeight(.medium)
          .frame(width: 58, alignment: .leading)
          safeSlider(
            value: temperatureBinding(pointID),
            range: temperatureRange,
            fallbackRange: FanCurveConfiguration
              .minimumTemperature...FanCurveConfiguration.maximumTemperature,
            step: 1)
          Text("\(point.temperature) °C")
            .monospacedDigit()
            .frame(width: 48, alignment: .trailing)
          safeSlider(
            value: percentBinding(pointID),
            range: percentRange,
            fallbackRange: FanCurveConfiguration
              .minimumFanPercent...FanCurveConfiguration.maximumFanPercent,
            step: FanCurveConfiguration.percentageStep)
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
  }

  private var canAddPoint: Bool {
    var candidate = draft
    return candidate.addInterpolatedPoint()
  }

  private func temperatureBinding(_ pointID: FanCurvePoint.ID) -> Binding<Double> {
    Binding(
      get: {
        Double(draft.points.first(where: { $0.id == pointID })?.temperature ?? 0)
      },
      set: {
        guard let index = draft.points.firstIndex(where: { $0.id == pointID }) else { return }
        draft.points[index].temperature = Int($0.rounded())
        savedMessage = nil
      })
  }

  private func percentBinding(_ pointID: FanCurvePoint.ID) -> Binding<Double> {
    Binding(
      get: {
        Double(draft.points.first(where: { $0.id == pointID })?.fanPercent ?? 0)
      },
      set: {
        guard let index = draft.points.firstIndex(where: { $0.id == pointID }) else { return }
        draft.points[index].fanPercent = Int($0.rounded())
        savedMessage = nil
      })
  }

  @ViewBuilder
  private func safeSlider(
    value: Binding<Double>,
    range: ClosedRange<Int>,
    fallbackRange: ClosedRange<Int>,
    step: Int
  ) -> some View {
    if range.lowerBound < range.upperBound {
      Slider(
        value: value,
        in: Double(range.lowerBound)...Double(range.upperBound),
        step: Double(step))
    } else {
      Slider(
        value: .constant(value.wrappedValue),
        in: Double(fallbackRange.lowerBound)...Double(fallbackRange.upperBound),
        step: Double(step)
      )
      .disabled(true)
      .help(
        L10n.text(
          "curve.fixedByNeighbors",
          fallback: "Adjust a neighboring point to unlock this value."))
    }
  }

  private var hysteresisBinding: Binding<Double> {
    Binding(
      get: { draft.hysteresis },
      set: {
        draft.hysteresis = $0
        savedMessage = nil
      })
  }

  private var delayBinding: Binding<Double> {
    Binding(
      get: { draft.decreaseDelaySeconds },
      set: {
        draft.decreaseDelaySeconds = $0
        savedMessage = nil
      })
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

@available(macOS 13.0, *)
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
              series: .value("Sensor", "CPU")
            )
            .foregroundStyle(by: .value("Sensor", "CPU"))
          }
          if let gpu = sample.gpuTemperature {
            LineMark(
              x: .value("Time", sample.id),
              y: .value("Temperature", gpu),
              series: .value("Sensor", "GPU")
            )
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
          series: .value("Fan", "Fan \(value.fanID + 1)")
        )
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
