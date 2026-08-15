import AppKit
import SwiftUI

#if canImport(BreezeHardware)
  import BreezeHardware
#endif

enum DashboardWindow: String, Codable, Hashable {
  case main

  static let sceneID = "dashboard"
}

private enum DashboardSection: String, CaseIterable, Identifiable {
  case overview
  case cooling
  case curves
  case providers

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview: L10n.text("dashboard.overview", fallback: "Overview")
    case .cooling: L10n.text("dashboard.cooling", fallback: "Cooling")
    case .curves: L10n.text("dashboard.curves", fallback: "Curves")
    case .providers: L10n.text("dashboard.providers", fallback: "Providers")
    }
  }

  var systemImage: String {
    switch self {
    case .overview: "gauge.with.dots.needle.33percent"
    case .cooling: "fan"
    case .curves: "chart.xyaxis.line"
    case .providers: "puzzlepiece.extension"
    }
  }
}

@available(macOS 14.0, *)
struct DashboardView: View {
  @ObservedObject var state: AppState
  @State private var selection: DashboardSection? = .overview
  @State private var isConfirmingHistoryClear = false

  var body: some View {
    NavigationSplitView {
      List(DashboardSection.allCases, selection: $selection) { section in
        Label(section.title, systemImage: section.systemImage)
          .tag(section)
      }
      .navigationTitle("Breeze")
      .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
    } detail: {
      Group {
        switch selection ?? .overview {
        case .overview: overview
        case .cooling: cooling
        case .curves: curves
        case .providers: providers
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .frame(minWidth: 820, minHeight: 560)
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

  private var overview: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        dashboardHeader(
          title: L10n.text("dashboard.overview", fallback: "Overview"),
          subtitle: state.snapshot?.hardware.modelIdentifier ?? "Apple Silicon Mac")

        if let snapshot = state.snapshot {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            temperatureCard(
              L10n.text("temperature.cpu", fallback: "CPU"),
              snapshot.hottestTemperature(in: .cpu)?.temperature, icon: "cpu")
            temperatureCard(
              L10n.text("temperature.gpu", fallback: "GPU"),
              snapshot.hottestTemperature(in: .gpu)?.temperature, icon: "square.stack.3d.up")
            temperatureCard(
              L10n.text("temperature.memory", fallback: "Memory"),
              snapshot.hottestTemperature(in: .memory)?.temperature, icon: "memorychip")
            temperatureCard(
              L10n.text("temperature.battery", fallback: "Battery"),
              snapshot.batteryTemperature?.temperature, icon: "battery.75percent")
          }

          DashboardCard(
            title: L10n.text("dashboard.thermalHistory", fallback: "Thermal History"),
            systemImage: "chart.line.uptrend.xyaxis"
          ) {
            HStack {
              Text(
                L10n.format(
                  "dashboard.historySampleCount", fallback: "%d saved samples",
                  state.thermalHistory.count))
                .font(.callout)
                .foregroundStyle(.secondary)
              Spacer()
              Button(L10n.text("action.clearHistory", fallback: "Clear History")) {
                isConfirmingHistoryClear = true
              }
              .disabled(state.thermalHistory.isEmpty)
            }
            if state.thermalHistory.count >= 2 {
              ThermalHistoryChart(samples: state.thermalHistory)
            } else {
              Text(
                L10n.text(
                  "dashboard.historyCollecting",
                  fallback: "Collecting temperature history…"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 100)
            }
          }

          DashboardCard(
            title: L10n.text("hardware.fans", fallback: "Fans"), systemImage: "fan"
          ) {
            if snapshot.fans.isEmpty {
              Text(L10n.text("fan.none", fallback: "No controllable fans detected."))
                .foregroundStyle(.secondary)
            } else {
              Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                ForEach(snapshot.fans) { fan in
                  GridRow {
                    Text(L10n.format("fan.number", fallback: "Fan %d", fan.id + 1))
                      .fontWeight(.medium)
                    Text("\(Int(fan.currentRPM.rounded()).formatted()) RPM")
                      .monospacedDigit()
                      .contentTransition(.numericText())
                    Text(range(for: fan))
                      .foregroundStyle(.secondary)
                  }
                }
              }
            }
          }

          DashboardCard(
            title: L10n.text("dashboard.safetyStatus", fallback: "Safety Status"),
            systemImage: "checkmark.shield"
          ) {
            LabeledContent(
              L10n.text("hardware.controlStatus", fallback: "Control status"),
              value: controlModeTitle)
            LabeledContent(
              L10n.text("helper.connection", fallback: "Connection"),
              value: helperConnectionTitle)
            if let lease = state.controlLeaseStatus, lease.isActive {
              LabeledContent(
                L10n.text("dashboard.watchdog", fallback: "Watchdog"),
                value: L10n.format(
                  "dashboard.lease", fallback: "Active · %ds", lease.remainingSeconds))
            }
          }
        } else if state.isLoading {
          ProgressView().frame(maxWidth: .infinity).padding(.vertical, 80)
        } else {
          ContentUnavailableView(
            L10n.text("hardware.unavailable", fallback: "Hardware unavailable"),
            systemImage: "exclamationmark.triangle")
        }
      }
      .padding(28)
    }
    .navigationTitle(L10n.text("dashboard.overview", fallback: "Overview"))
    .toolbar { refreshToolbar }
  }

  private var cooling: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        dashboardHeader(
          title: L10n.text("dashboard.cooling", fallback: "Cooling"),
          subtitle: L10n.text(
            "dashboard.coolingSubtitle",
            fallback: "Current fan ownership, presets, and Helper safety"))

        DashboardCard(
          title: controlModeTitle,
          systemImage: state.activeControlMode == .automatic ? "checkmark.shield" : "fan"
        ) {
          LabeledContent(
            L10n.text("dashboard.curveState", fallback: "Automatic curve"),
            value: state.isFanCurveEnabled
              ? L10n.text("status.enabled", fallback: "Enabled")
              : L10n.text("status.disabled", fallback: "Disabled"))
          if let temperature = state.fanCurveTemperature {
            LabeledContent(
              L10n.text("curve.controlTemperature", fallback: "Control temperature"),
              value: "\(temperature.formatted(.number.precision(.fractionLength(1)))) °C")
          }
          if let percent = state.fanCurveTargetPercent {
            LabeledContent(
              L10n.text("curve.target", fallback: "Fan target"),
              value: "\(percent)%")
          }
          HStack {
            Button(
              state.isFanCurveEnabled
                ? L10n.text("action.disableCurve", fallback: "Disable Curve")
                : L10n.text("action.enableCurve", fallback: "Enable Curve")
            ) {
              if state.isFanCurveEnabled { state.disableFanCurve() } else { state.enableFanCurve() }
            }
            .disabled(
              state.isApplyingPreset || state.isRestoringAutomaticControl
                || !state.fansApplyingControl.isEmpty)

            Button(L10n.text("action.restoreAutomatic", fallback: "Restore Apple Automatic")) {
              state.restoreAutomaticControl()
            }
            .disabled(state.isRestoringAutomaticControl)
          }
        }

        DashboardCard(
          title: L10n.text("dashboard.guardrails", fallback: "Guardrails"),
          systemImage: "heart.text.square"
        ) {
          Text(
            L10n.text(
              "dashboard.guardrailsBody",
              fallback:
                "Active control is bounded by verified fan ranges and a Helper-owned 15-second lease. If heartbeats stop, Breeze returns control to Apple."
            )
          )
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(28)
    }
    .navigationTitle(L10n.text("dashboard.cooling", fallback: "Cooling"))
    .toolbar { refreshToolbar }
  }

  private var curves: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        dashboardHeader(
          title: L10n.text("dashboard.curves", fallback: "Curves"),
          subtitle: L10n.text(
            "dashboard.curvesSubtitle", fallback: "Custom points and response behavior"))

        DashboardCard(
          title: L10n.text("dashboard.curveEditor", fallback: "Custom Curve Editor"),
          systemImage: "slider.horizontal.3"
        ) {
          CurveEditorView(state: state)
        }
      }
      .padding(28)
    }
    .navigationTitle(L10n.text("dashboard.curves", fallback: "Curves"))
  }

  private var providers: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        dashboardHeader(
          title: L10n.text("dashboard.providers", fallback: "Providers"),
          subtitle: L10n.text(
            "dashboard.providersSubtitle",
            fallback: "Hardware adapters and future third-party integrations"))

        DashboardCard(title: "AppleSMC", systemImage: "apple.logo") {
          LabeledContent(
            L10n.text("dashboard.providerType", fallback: "Type"),
            value: L10n.text("dashboard.builtinProvider", fallback: "Built-in provider"))
          LabeledContent(
            L10n.text("dashboard.providerAccess", fallback: "Access"),
            value: state.snapshot?.hardware.isControlVerified == true
              ? L10n.text("status.verified", fallback: "Verified")
              : L10n.text("status.monitorOnly", fallback: "Monitor only"))
          Text(
            L10n.text(
              "dashboard.appleSMCBody",
              fallback:
                "AppleSMC remains inside Breeze's signed Helper. External providers will never receive arbitrary root or SMC access."
            )
          )
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }

        DashboardCard(
          title: L10n.text("dashboard.thirdPartyProviders", fallback: "Third-party Providers"),
          systemImage: "puzzlepiece.extension"
        ) {
          Label(
            L10n.text(
              "dashboard.providerSDKPlanned",
              fallback: "Provider SDK and isolated plugin hosting are planned"),
            systemImage: "lock.shield"
          )
          .foregroundStyle(.secondary)
          Text(
            L10n.text(
              "dashboard.providerSafetyBody",
              fallback:
                "Providers will run without root privileges and communicate through a narrow capability API. The Breeze Helper will continue to enforce model, fan-range, and watchdog checks."
            )
          )
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(28)
    }
    .navigationTitle(L10n.text("dashboard.providers", fallback: "Providers"))
  }

  @ToolbarContentBuilder
  private var refreshToolbar: some ToolbarContent {
    ToolbarItem {
      Button {
        state.refreshNow()
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .help(L10n.text("action.refreshNow", fallback: "Refresh now"))
    }
  }

  private func dashboardHeader(title: String, subtitle: String) -> some View {
    HStack(spacing: 14) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .scaledToFit()
        .frame(width: 54, height: 54)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.largeTitle.bold())
        Text(subtitle).foregroundStyle(.secondary)
      }
    }
  }

  private func temperatureCard(_ title: String, _ value: Double?, icon: String) -> some View {
    DashboardCard(title: title, systemImage: icon) {
      Text(value.map { "\($0.formatted(.number.precision(.fractionLength(1)))) °C" } ?? "—")
        .font(.title2.weight(.semibold))
        .monospacedDigit()
        .contentTransition(.numericText())
    }
  }

  private func curveRow(_ threshold: String, mode: String) -> some View {
    LabeledContent(mode, value: threshold)
  }

  private func range(for fan: FanState) -> String {
    guard let minimum = fan.minimumRPM, let maximum = fan.maximumRPM else { return "—" }
    return "\(Int(minimum.rounded()).formatted())–\(Int(maximum.rounded()).formatted()) RPM"
  }

  private var helperConnectionTitle: String {
    guard state.helperStatus == .enabled else {
      return L10n.text("helper.notInstalled", fallback: "Not installed")
    }
    guard let version = state.helperVersion else {
      return L10n.text("status.notChecked", fallback: "Not checked")
    }
    return L10n.format("helper.connected", fallback: "Connected · v%@", version)
  }

  private var controlModeTitle: String {
    if state.isFanCurveEnabled {
      return L10n.text("curve.activeShort", fallback: "Automatic curve active")
    }
    switch state.activeControlMode {
    case .automatic: return L10n.text("mode.appleAutomaticTitle", fallback: "Apple Automatic")
    case .curve: return L10n.text("curve.title", fallback: "Automatic Curve")
    case .manual: return L10n.text("control.manual", fallback: "Manual Control")
    case .balanced: return L10n.text("mode.balanced", fallback: "Balanced")
    case .cool: return L10n.text("mode.cool", fallback: "Cool")
    case .max: return L10n.text("mode.max", fallback: "Max")
    }
  }
}

private struct DashboardCard<Content: View>: View {
  let title: String
  let systemImage: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: systemImage)
        .font(.headline)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(.background, in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(.separator.opacity(0.45))
    }
  }
}

@available(macOS 14.0, *)
private struct DashboardPreview: View {
  var body: some View {
    DashboardView(state: .preview)
      .frame(width: 900, height: 620)
  }
}
