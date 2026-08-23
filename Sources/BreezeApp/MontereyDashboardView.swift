import SwiftUI

struct MontereyDashboardView: View {
  @ObservedObject var state: AppState

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ScrollView {
        MenuBarView(state: state)
          .padding(.vertical, 8)
      }
      .frame(width: 420)

      Divider()

      ScrollView {
        MontereyCurveEditor(state: state)
          .padding(24)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 820, minHeight: 560)
  }
}

private struct MontereyCurveEditor: View {
  @ObservedObject var state: AppState
  @State private var draft: FanCurveConfiguration
  @State private var message: String?

  init(state: AppState) {
    self.state = state
    _draft = State(initialValue: state.fanCurveConfiguration)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 3) {
        Text(
          state.fanCurveMode == .automatic
            ? L10n.text("curve.profileAutomatic", fallback: "Automatic 45–90°C")
            : L10n.text("dashboard.curveEditor", fallback: "Custom Curve Editor")
        )
        .font(.title2.bold())
        Text(
          state.fanCurveMode == .automatic
            ? L10n.text(
              "curve.automaticShort",
              fallback: "Fan speed follows temperature automatically; no points need editing.")
            : L10n.text(
              "curve.dragHint",
              fallback: "Drag a chart point to adjust temperature and fan speed.")
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Picker(
        L10n.text("curve.profile", fallback: "Control profile"),
        selection: Binding(
          get: { state.fanCurveMode },
          set: { state.setFanCurveMode($0) })
      ) {
        Text(L10n.text("curve.profileAutomatic", fallback: "Automatic 45–90°C"))
          .tag(FanCurveMode.automatic)
        Text(L10n.text("curve.profileCustom", fallback: "Advanced Custom"))
          .tag(FanCurveMode.custom)
      }
      .pickerStyle(.segmented)
      .disabled(state.isFanCurveEnabled)

      MontereyCurveGraph(
        configuration: displayConfiguration,
        currentTemperature: state.fanCurveTemperature,
        isEditingDisabled: state.isFanCurveEnabled || state.fanCurveMode == .automatic,
        didEdit: { message = nil }
      )
      .frame(height: 270)

      if state.fanCurveMode == .automatic {
        Text(
          L10n.text(
            "curve.automaticDescription",
            fallback:
              "Breeze continuously maps the hotter CPU/GPU temperature from 45°C at 20% to 90°C at 100%, in safe 5% steps. Rising temperatures apply immediately; decreases use a 2°C hysteresis and 3-second delay."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      } else {
        ForEach(Array(draft.points.enumerated()), id: \.element.id) { index, point in
          HStack {
            Text(L10n.format("curve.pointNumber", fallback: "Point %d", index + 1))
            Spacer()
            Text("\(point.temperature) °C").monospacedDigit()
            Text("\(point.fanPercent)%")
              .monospacedDigit()
              .frame(width: 48, alignment: .trailing)
            Button {
              if draft.removePoint(id: point.id) { message = nil }
            } label: {
              Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(
              state.isFanCurveEnabled
                || draft.points.count <= FanCurveConfiguration.minimumPointCount)
          }
        }

        HStack {
          Button(L10n.text("action.addPoint", fallback: "Add Point")) {
            if draft.addInterpolatedPoint() { message = nil }
          }
          .disabled(state.isFanCurveEnabled || !canAddPoint)

          Button(L10n.text("action.saveCurve", fallback: "Save Curve")) {
            message =
              state.saveFanCurveConfiguration(draft)
              ? L10n.text("curve.saved", fallback: "Curve saved")
              : L10n.text("curve.invalid", fallback: "Curve settings are invalid")
          }
          .disabled(
            state.isFanCurveEnabled || !draft.isValid || draft == state.fanCurveConfiguration)

          Button(L10n.text("action.resetCurve", fallback: "Reset to Default")) {
            draft = .default
            message = nil
          }
          .disabled(state.isFanCurveEnabled || draft == .default)
        }
      }

      if state.isFanCurveEnabled {
        Label(
          L10n.text(
            "curve.disableToEdit",
            fallback: "Disable the automatic curve before editing its points."),
          systemImage: "lock.fill"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } else if let message {
        Text(message)
          .font(.caption)
          .foregroundStyle(draft.isValid ? .green : .red)
      }
    }
    .onReceive(state.$fanCurveConfiguration) { configuration in
      if configuration != draft { draft = configuration }
    }
  }

  private var canAddPoint: Bool {
    var candidate = draft
    return candidate.addInterpolatedPoint()
  }

  private var displayConfiguration: Binding<FanCurveConfiguration> {
    Binding(
      get: { state.fanCurveMode == .automatic ? .automatic : draft },
      set: { configuration in
        guard state.fanCurveMode == .custom else { return }
        draft = configuration
      })
  }
}

private struct MontereyCurveGraph: View {
  @Binding var configuration: FanCurveConfiguration
  let currentTemperature: Double?
  let isEditingDisabled: Bool
  let didEdit: () -> Void

  var body: some View {
    GeometryReader { geometry in
      let rect = CGRect(
        x: 28, y: 12, width: geometry.size.width - 40, height: geometry.size.height - 40)
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 10)
          .fill(Color.secondary.opacity(0.08))

        Path { path in
          for step in 0...4 {
            let x = rect.minX + rect.width * CGFloat(step) / 4
            let y = rect.minY + rect.height * CGFloat(step) / 4
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
          }
        }
        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)

        Path { path in
          for (index, point) in configuration.points.enumerated() {
            let position = position(for: point, in: rect)
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
          }
        }
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineJoin: .round))

        if let currentTemperature {
          let x = xPosition(for: currentTemperature, in: rect)
          Path { path in
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
          }
          .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
        }

        ForEach(configuration.points) { point in
          Circle()
            .fill(isEditingDisabled ? Color.secondary : Color.accentColor)
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 3))
            .frame(width: 16, height: 16)
            .position(position(for: point, in: rect))
            .gesture(
              DragGesture(minimumDistance: 0, coordinateSpace: .named("curvePlot"))
                .onChanged { value in
                  guard !isEditingDisabled else { return }
                  let temperature = temperature(at: value.location.x, in: rect)
                  let percent = fanPercent(at: value.location.y, in: rect)
                  if configuration.movePoint(
                    id: point.id, temperature: temperature, fanPercent: percent)
                  {
                    didEdit()
                  }
                })
        }

        Text("20 °C").font(.caption2).foregroundStyle(.secondary)
          .position(x: rect.minX + 16, y: rect.maxY + 14)
        Text("100 °C").font(.caption2).foregroundStyle(.secondary)
          .position(x: rect.maxX - 22, y: rect.maxY + 14)
        Text("100%").font(.caption2).foregroundStyle(.secondary)
          .position(x: rect.minX - 2, y: rect.minY)
        Text("20%").font(.caption2).foregroundStyle(.secondary)
          .position(x: rect.minX - 2, y: rect.maxY)
      }
      .coordinateSpace(name: "curvePlot")
    }
  }

  private func position(for point: FanCurvePoint, in rect: CGRect) -> CGPoint {
    CGPoint(
      x: xPosition(for: Double(point.temperature), in: rect),
      y: yPosition(for: Double(point.fanPercent), in: rect))
  }

  private func xPosition(for temperature: Double, in rect: CGRect) -> CGFloat {
    let span = Double(
      FanCurveConfiguration.maximumTemperature - FanCurveConfiguration.minimumTemperature)
    let fraction = (temperature - Double(FanCurveConfiguration.minimumTemperature)) / span
    return rect.minX + rect.width * CGFloat(min(max(fraction, 0), 1))
  }

  private func yPosition(for percent: Double, in rect: CGRect) -> CGFloat {
    let span = Double(
      FanCurveConfiguration.maximumFanPercent - FanCurveConfiguration.minimumFanPercent)
    let fraction = (percent - Double(FanCurveConfiguration.minimumFanPercent)) / span
    return rect.maxY - rect.height * CGFloat(min(max(fraction, 0), 1))
  }

  private func temperature(at x: CGFloat, in rect: CGRect) -> Double {
    let fraction = min(max((x - rect.minX) / rect.width, 0), 1)
    return Double(FanCurveConfiguration.minimumTemperature)
      + Double(fraction)
      * Double(FanCurveConfiguration.maximumTemperature - FanCurveConfiguration.minimumTemperature)
  }

  private func fanPercent(at y: CGFloat, in rect: CGRect) -> Double {
    let fraction = min(max((rect.maxY - y) / rect.height, 0), 1)
    return Double(FanCurveConfiguration.minimumFanPercent)
      + Double(fraction)
      * Double(FanCurveConfiguration.maximumFanPercent - FanCurveConfiguration.minimumFanPercent)
  }
}
