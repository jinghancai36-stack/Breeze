import AppKit
import Combine
import Foundation
import OSLog

#if canImport(BreezeHardware)
  import BreezeHardware
#endif
#if canImport(BreezeIPC)
  import BreezeIPC
#endif

enum ActiveFanControlMode: String, Equatable, Sendable {
  case automatic
  case curve
  case manual
  case balanced
  case cool
  case max
}

@MainActor
final class AppState: ObservableObject {
  @Published private(set) var snapshot: HardwareSnapshot?
  @Published private(set) var errorMessage: String?
  @Published private(set) var isLoading = true
  @Published private(set) var lastSuccessfulUpdate: Date?
  @Published private(set) var isSleeping = false
  @Published private(set) var isPopoverVisible = false
  @Published private(set) var helperStatus: HelperRegistrationStatus = .notRegistered
  @Published private(set) var helperVersion: String?
  @Published private(set) var helperErrorMessage: String?
  @Published private(set) var isCheckingHelper = false
  @Published private(set) var automaticControlStatus: AutomaticControlStatus?
  @Published private(set) var isRestoringAutomaticControl = false
  @Published private(set) var fanControlStatuses: [Int: FanControlStatus] = [:]
  @Published private(set) var fansApplyingControl: Set<Int> = []
  @Published private(set) var controlLeaseStatus: ControlLeaseStatus?
  @Published private(set) var presetControlStatus: PresetControlStatus?
  @Published private(set) var activeControlMode: ActiveFanControlMode = .automatic
  @Published private(set) var isApplyingPreset = false
  @Published private(set) var isFanCurveEnabled = false
  @Published private(set) var fanCurveStage: FanCurveStage = .automatic
  @Published private(set) var fanCurveTemperature: Double?
  @Published private(set) var fanCurveTargetPercent: Int?
  @Published private(set) var fanCurveMode: FanCurveMode
  @Published private(set) var automaticallyResumeFullAutomatic: Bool
  @Published private(set) var fanCurveConfiguration: FanCurveConfiguration
  @Published private(set) var thermalHistory: [ThermalHistorySample] = []

  private let logger = Logger(
    subsystem: "com.breeze.monitor", category: "Hardware")
  private let monitor: (any HardwareMonitoring)?
  private let helperInstaller: any HelperInstalling
  private let helperClient: any HelperCommunicating
  private let curveConfigurationStore: CurveConfigurationStore
  private let curveModeStore: CurveModeStore
  private let automaticResumeStore: AutomaticResumeStore
  private let thermalHistoryStore: ThermalHistoryStore
  private let terminateApp: @MainActor () -> Void
  private var pollingTask: Task<Void, Never>?
  private var leaseHeartbeatTask: Task<Void, Never>?
  private var controlRequestGeneration = 0
  private var fanCurveDecisionState = FanCurveDecisionState()
  private var pendingFullAutomaticResume = false
  private var historySamplesSinceSave = 0
  private var workspaceObservers: [NSObjectProtocol] = []

  init(
    monitor: (any HardwareMonitoring)? = nil,
    helperInstaller: any HelperInstalling = SystemHelperInstaller(),
    helperClient: any HelperCommunicating = HelperClient(),
    curveConfigurationStore: CurveConfigurationStore = CurveConfigurationStore(),
    curveModeStore: CurveModeStore = CurveModeStore(),
    automaticResumeStore: AutomaticResumeStore = AutomaticResumeStore(),
    thermalHistoryStore: ThermalHistoryStore = ThermalHistoryStore(),
    terminateApp: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
  ) {
    self.helperInstaller = helperInstaller
    self.helperClient = helperClient
    self.curveConfigurationStore = curveConfigurationStore
    self.curveModeStore = curveModeStore
    self.automaticResumeStore = automaticResumeStore
    self.thermalHistoryStore = thermalHistoryStore
    fanCurveMode = curveModeStore.load()
    automaticallyResumeFullAutomatic = automaticResumeStore.load()
    fanCurveConfiguration = curveConfigurationStore.load()
    thermalHistory = thermalHistoryStore.load()
    self.terminateApp = terminateApp
    helperStatus = helperInstaller.status
    if let monitor {
      self.monitor = monitor
      return
    }
    do {
      self.monitor = try HardwareMonitor()
    } catch {
      self.monitor = nil
      errorMessage = error.localizedDescription
      isLoading = false
    }
  }

  init(previewSnapshot: HardwareSnapshot) {
    helperInstaller = PreviewHelperInstaller()
    helperClient = PreviewHelperClient()
    curveConfigurationStore = CurveConfigurationStore()
    curveModeStore = CurveModeStore()
    automaticResumeStore = AutomaticResumeStore()
    thermalHistoryStore = ThermalHistoryStore()
    fanCurveMode = .automatic
    automaticallyResumeFullAutomatic = false
    fanCurveConfiguration = .default
    terminateApp = {}
    helperStatus = .enabled
    helperVersion = BreezeHelperConstants.helperVersion
    monitor = nil
    snapshot = previewSnapshot
    lastSuccessfulUpdate = previewSnapshot.capturedAt
    isLoading = false
  }

  func start() {
    guard pollingTask == nil else { return }
    pendingFullAutomaticResume = automaticallyResumeFullAutomatic && fanCurveMode == .automatic
    installWorkspaceObservers()
    refreshHelperStatus()
    if helperStatus == .enabled { pingHelper() }
    pollingTask = Task { [weak self] in
      await self?.runPolling()
    }
  }

  func stop() {
    pollingTask?.cancel()
    pollingTask = nil
    stopLeaseHeartbeat()
    persistThermalHistory()
    let center = NSWorkspace.shared.notificationCenter
    workspaceObservers.forEach(center.removeObserver)
    workspaceObservers.removeAll()
  }

  func setPopoverVisible(_ visible: Bool) {
    isPopoverVisible = visible
    if visible {
      Task { [weak self] in
        await self?.refresh()
      }
    }
  }

  func refreshNow() {
    Task { [weak self] in
      await self?.refresh()
    }
  }

  func refreshHelperStatus() {
    helperStatus = helperInstaller.status
    if helperStatus != .enabled {
      helperVersion = nil
    }
  }

  func installHelper() {
    helperErrorMessage = nil
    do {
      try helperInstaller.register()
    } catch {
      logger.error("Helper registration failed: \(error.localizedDescription, privacy: .public)")
      helperErrorMessage = L10n.text(
        "error.helperApproval", fallback: "Breeze Helper needs approval in System Settings.")
    }
    refreshHelperStatus()
  }

  func uninstallHelper() {
    guard !isRestoringAutomaticControl else { return }
    helperErrorMessage = nil
    guard helperStatus == .enabled else {
      unregisterHelperAfterAutomaticRestore()
      return
    }
    controlRequestGeneration &+= 1
    isApplyingPreset = false
    deactivateFanCurve()
    stopLeaseHeartbeat()
    isRestoringAutomaticControl = true
    helperClient.restoreAutomaticControl { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        self.isRestoringAutomaticControl = false
        switch result {
        case .success(let status) where status.isAutomatic:
          self.automaticControlStatus = status
          self.stopLeaseHeartbeat()
          self.unregisterHelperAfterAutomaticRestore()
        case .success(let status):
          self.automaticControlStatus = status
          self.helperErrorMessage = L10n.format(
            "error.helperRemovalNotAutomatic",
            fallback:
              "Helper removal was cancelled because Apple automatic control was not verified: %@",
            status.message)
        case .failure(let error):
          self.helperErrorMessage = L10n.format(
            "error.helperRemovalVerification",
            fallback:
              "Helper removal was cancelled because Apple automatic control could not be verified: %@",
            error.localizedDescription)
        }
      }
    }
  }

  private func unregisterHelperAfterAutomaticRestore() {
    do {
      try helperInstaller.unregister()
    } catch {
      logger.error("Helper removal failed: \(error.localizedDescription, privacy: .public)")
      helperErrorMessage = L10n.text(
        "error.helperRemoval", fallback: "Unable to remove Breeze Helper.")
    }
    refreshHelperStatus()
  }

  func openHelperApprovalSettings() {
    helperInstaller.openSystemSettings()
  }

  func pingHelper() {
    guard !isCheckingHelper else { return }
    isCheckingHelper = true
    helperErrorMessage = nil
    helperClient.probe { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        self.isCheckingHelper = false
        switch result {
        case .success(let version):
          self.helperVersion = version
          self.helperErrorMessage = nil
          self.attemptPendingFullAutomaticResume()
        case .failure(let error):
          self.helperVersion = nil
          self.helperErrorMessage = error.localizedDescription
        }
        self.refreshHelperStatus()
      }
    }
  }

  func checkAutomaticControl() {
    guard helperStatus == .enabled, !isRestoringAutomaticControl else { return }
    helperErrorMessage = nil
    helperClient.automaticControlStatus { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        switch result {
        case .success(let status):
          self.automaticControlStatus = status
          if status.isAutomatic {
            self.deactivateFanCurve()
            self.fanControlStatuses.removeAll()
            self.presetControlStatus = nil
            self.activeControlMode = .automatic
            self.stopLeaseHeartbeat()
          }
          self.helperErrorMessage = status.isAutomatic ? nil : status.message
        case .failure(let error):
          self.automaticControlStatus = nil
          self.helperErrorMessage = error.localizedDescription
        }
      }
    }
  }

  func setFanRPM(fanID: Int, rpm: Int) {
    guard canControlFan(fanID), !fansApplyingControl.contains(fanID) else { return }
    deactivateFanCurve()
    fansApplyingControl.insert(fanID)
    helperErrorMessage = nil
    helperClient.setFanRPM(fanID: fanID, rpm: rpm) { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        self.fansApplyingControl.remove(fanID)
        switch result {
        case .success(let status):
          self.fanControlStatuses[fanID] = status
          self.automaticControlStatus = nil
          self.helperErrorMessage = status.success ? nil : status.message
          if status.success && status.isManual {
            self.presetControlStatus = nil
            self.activeControlMode = .manual
            self.startLeaseHeartbeat()
          }
        case .failure(let error):
          self.helperErrorMessage = error.localizedDescription
        }
        await self.refresh()
      }
    }
  }

  func setFanAutomatic(fanID: Int) {
    if isFanCurveEnabled || [.balanced, .cool, .max].contains(activeControlMode) {
      restoreAutomaticControl()
      return
    }
    guard canControlFan(fanID), !fansApplyingControl.contains(fanID) else { return }
    fansApplyingControl.insert(fanID)
    helperErrorMessage = nil
    helperClient.setFanAutomatic(fanID: fanID) { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        self.fansApplyingControl.remove(fanID)
        switch result {
        case .success(let status):
          self.fanControlStatuses[fanID] = status
          self.helperErrorMessage = status.success ? nil : status.message
          if !self.fanControlStatuses.values.contains(where: { $0.isManual }) {
            self.activeControlMode = .automatic
            self.stopLeaseHeartbeat()
          }
        case .failure(let error):
          self.helperErrorMessage = error.localizedDescription
        }
        await self.refresh()
      }
    }
  }

  func applyBalancedPreset() {
    deactivateFanCurve()
    applyPreset(mode: .balanced) { [helperClient] completion in
      helperClient.applyBalancedPreset(completion: completion)
    }
  }

  func applyCoolPreset() {
    deactivateFanCurve()
    applyPreset(mode: .cool) { [helperClient] completion in
      helperClient.applyCoolPreset(completion: completion)
    }
  }

  func applyMaxPreset() {
    deactivateFanCurve()
    applyPreset(mode: .max) { [helperClient] completion in
      helperClient.applyMaxPreset(completion: completion)
    }
  }

  private func applyPreset(
    mode: ActiveFanControlMode,
    curveStage: FanCurveStage? = nil,
    curveTargetPercent: Int? = nil,
    request: (@escaping @Sendable (Result<PresetControlStatus, Error>) -> Void) -> Void
  ) {
    guard let snapshot,
      snapshot.fans.count == 2,
      snapshot.fans.allSatisfy({ canControlFan($0.id) }),
      !isApplyingPreset,
      !isRestoringAutomaticControl,
      fansApplyingControl.isEmpty
    else { return }
    controlRequestGeneration &+= 1
    let requestGeneration = controlRequestGeneration
    isApplyingPreset = true
    helperErrorMessage = nil
    request { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        guard requestGeneration == self.controlRequestGeneration else { return }
        self.isApplyingPreset = false
        switch result {
        case .success(let status):
          self.presetControlStatus = status
          self.helperErrorMessage = status.success ? nil : status.message
          if status.success {
            self.fanControlStatuses.removeAll()
            self.automaticControlStatus = nil
            self.activeControlMode = mode
            if let curveStage { self.fanCurveStage = curveStage }
            if let curveTargetPercent { self.fanCurveTargetPercent = curveTargetPercent }
            self.startLeaseHeartbeat()
          } else {
            if mode == .curve {
              self.fanCurveDecisionState.reset()
              self.deactivateFanCurve()
            }
            self.activeControlMode = .automatic
            self.stopLeaseHeartbeat()
          }
        case .failure(let error):
          if mode == .curve {
            self.fanCurveDecisionState.reset()
            self.deactivateFanCurve()
            self.activeControlMode = .automatic
            self.stopLeaseHeartbeat()
          }
          self.presetControlStatus = nil
          self.helperErrorMessage = L10n.format(
            "error.presetFailed",
            fallback:
              "Preset failed; the Helper safety lease will restore Automatic: %@",
            error.localizedDescription)
        }
        await self.refresh()
      }
    }
  }

  func canControlFan(_ fanID: Int) -> Bool {
    guard helperStatus == .enabled,
      helperVersion == BreezeHelperConstants.helperVersion,
      let snapshot,
      snapshot.hardware.isControlVerified,
      snapshot.hardware.modelIdentifier == "MacBookPro18,3",
      let fan = snapshot.fans.first(where: { $0.id == fanID }),
      let minimum = fan.minimumRPM,
      let maximum = fan.maximumRPM
    else { return false }
    return minimum >= 1_000 && maximum <= 7_000 && minimum < maximum
  }

  func restoreAutomaticControl(completion: (@MainActor @Sendable () -> Void)? = nil) {
    deactivateFanCurve()
    restoreAutomaticControl(preservingCurve: false, completion: completion)
  }

  private func restoreAutomaticControl(
    preservingCurve: Bool,
    completion: (@MainActor @Sendable () -> Void)? = nil
  ) {
    guard helperStatus == .enabled, !isRestoringAutomaticControl else { return }
    controlRequestGeneration &+= 1
    isApplyingPreset = false
    stopLeaseHeartbeat()
    isRestoringAutomaticControl = true
    helperErrorMessage = nil
    helperClient.restoreAutomaticControl { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        self.isRestoringAutomaticControl = false
        switch result {
        case .success(let status):
          self.automaticControlStatus = status
          if status.isAutomatic {
            self.fanControlStatuses.removeAll()
            self.presetControlStatus = nil
            self.activeControlMode = .automatic
            self.fanCurveStage = .automatic
            if !preservingCurve { self.isFanCurveEnabled = false }
          } else if preservingCurve {
            self.deactivateFanCurve()
          }
          self.helperErrorMessage = status.isAutomatic ? nil : status.message
          if status.isAutomatic { self.stopLeaseHeartbeat() }
        case .failure(let error):
          if preservingCurve { self.deactivateFanCurve() }
          self.automaticControlStatus = nil
          self.helperErrorMessage = error.localizedDescription
        }
        completion?()
        self.attemptPendingFullAutomaticResume()
      }
    }
  }

  func quitBreeze() {
    deactivateFanCurve()
    guard helperStatus == .enabled else {
      terminateApp()
      return
    }
    controlRequestGeneration &+= 1
    isApplyingPreset = false
    stopLeaseHeartbeat()
    isRestoringAutomaticControl = true
    helperErrorMessage = nil
    helperClient.restoreAutomaticControl { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        self.isRestoringAutomaticControl = false
        switch result {
        case .success(let status):
          self.automaticControlStatus = status
          guard status.isAutomatic else {
            self.helperErrorMessage = status.message
            return
          }
          self.stopLeaseHeartbeat()
          self.terminateApp()
        case .failure(let error):
          self.automaticControlStatus = nil
          self.helperErrorMessage = L10n.format(
            "error.quitVerification",
            fallback:
              "Quit was cancelled because Apple automatic control could not be verified: %@",
            error.localizedDescription)
        }
      }
    }
  }

  private func runPolling() async {
    while !Task.isCancelled {
      if !isSleeping {
        await refresh()
      }
      do {
        // Active automatic control stays on the one-second cadence even when
        // every Breeze window is closed, so load changes are not delayed by
        // the quieter background-monitoring interval.
        let seconds =
          isFanCurveEnabled
          ? MonitoringPolicy.visibleRefreshInterval
          : MonitoringPolicy.refreshInterval(isPopoverVisible: isPopoverVisible)
        try await TaskSleepCompatibility.sleep(for: seconds)
      } catch {
        return
      }
    }
  }

  private func startLeaseHeartbeat() {
    guard leaseHeartbeatTask == nil else { return }
    leaseHeartbeatTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        guard self.activeControlMode != .automatic else {
          self.leaseHeartbeatTask = nil
          return
        }

        let result = await withCheckedContinuation { continuation in
          self.helperClient.renewControlLease { result in
            continuation.resume(returning: result)
          }
        }
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let lease):
          self.controlLeaseStatus = lease
          let heartbeatPrefix = L10n.text(
            "error.heartbeatPrefix", fallback: "Safety heartbeat failed")
          if self.helperErrorMessage?.hasPrefix(heartbeatPrefix) == true {
            self.helperErrorMessage = nil
          }
          if !lease.isActive {
            self.deactivateFanCurve()
            self.helperErrorMessage = lease.message
            self.fanControlStatuses.removeAll()
            self.presetControlStatus = nil
            self.activeControlMode = .automatic
            self.leaseHeartbeatTask = nil
            self.checkAutomaticControl()
            return
          }
        case .failure(let error):
          self.controlLeaseStatus = nil
          self.helperErrorMessage = L10n.format(
            "error.heartbeat",
            fallback:
              "Safety heartbeat failed; the Helper will restore Automatic within 15 seconds: %@",
            error.localizedDescription)
        }

        do {
          try await TaskSleepCompatibility.sleep(
            for: TimeInterval(ControlLeaseTiming.heartbeatSeconds))
        } catch {
          return
        }
      }
    }
  }

  private func stopLeaseHeartbeat() {
    leaseHeartbeatTask?.cancel()
    leaseHeartbeatTask = nil
    controlLeaseStatus = nil
  }

  private func refresh() async {
    guard !isSleeping, let monitor else { return }
    do {
      let updated = try await Task.detached(priority: .utility) {
        try monitor.snapshot()
      }.value
      snapshot = updated
      lastSuccessfulUpdate = updated.capturedAt
      errorMessage = nil
      isLoading = false
      appendHistory(from: updated)
      evaluateFanCurve(using: updated)
      attemptPendingFullAutomaticResume()
      logger.debug(
        "Updated read-only snapshot: fans=\(updated.fans.count, privacy: .public) sensors=\(updated.sensors.count, privacy: .public)"
      )
    } catch is CancellationError {
      return
    } catch {
      logger.error("Read failed: \(error.localizedDescription, privacy: .public)")
      // Keep the last good snapshot visible while clearly marking it stale.
      errorMessage = error.localizedDescription
      isLoading = false
    }
  }

  func refreshForTesting() async {
    await refresh()
  }

  private func installWorkspaceObservers() {
    guard workspaceObservers.isEmpty else { return }
    let center = NSWorkspace.shared.notificationCenter
    workspaceObservers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in
        Task { @MainActor in
          self?.isSleeping = true
          self?.pendingFullAutomaticResume =
            self?.automaticallyResumeFullAutomatic == true && self?.fanCurveMode == .automatic
          self?.deactivateFanCurve()
          self?.logger.info("System will sleep; pausing read-only polling")
          self?.restoreAutomaticControl()
        }
      }
    )
    workspaceObservers.append(
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          self.isSleeping = false
          self.logger.info("System woke; refreshing hardware state")
          await self.refresh()
          if self.pendingFullAutomaticResume {
            self.attemptPendingFullAutomaticResume()
          } else {
            self.checkAutomaticControl()
          }
        }
      }
    )
  }

  func enableFanCurve() {
    let configuration = effectiveFanCurveConfiguration
    guard let snapshot,
      snapshot.fans.count == 2,
      snapshot.fans.allSatisfy({ canControlFan($0.id) }),
      CustomFanCurvePolicy.controlTemperature(
        for: snapshot, source: configuration.sensorSource) != nil,
      !isRestoringAutomaticControl,
      !isApplyingPreset,
      fansApplyingControl.isEmpty
    else { return }
    isFanCurveEnabled = true
    fanCurveStage = .automatic
    fanCurveTargetPercent = nil
    fanCurveDecisionState.reset()
    presetControlStatus = nil
    // The first curve stage atomically replaces any prior fixed/manual target.
    // The Helper preflights both fans and rolls back to Apple on failure, so the
    // curve never creates an unleased Apple-Automatic gap while it is enabled.
    evaluateFanCurve(using: snapshot)
  }

  func disableFanCurve() {
    guard isFanCurveEnabled else { return }
    deactivateFanCurve()
    restoreAutomaticControl(preservingCurve: false)
  }

  private func deactivateFanCurve() {
    isFanCurveEnabled = false
    fanCurveStage = .automatic
    fanCurveTemperature = nil
    fanCurveTargetPercent = nil
    fanCurveDecisionState.reset()
  }

  private func evaluateFanCurve(using snapshot: HardwareSnapshot) {
    guard isFanCurveEnabled,
      !isSleeping,
      !isApplyingPreset,
      !isRestoringAutomaticControl,
      fansApplyingControl.isEmpty
    else { return }

    let configuration = effectiveFanCurveConfiguration
    guard
      let temperature = CustomFanCurvePolicy.controlTemperature(
        for: snapshot, source: configuration.sensorSource)
    else {
      deactivateFanCurve()
      restoreAutomaticControl(preservingCurve: false)
      return
    }

    fanCurveTemperature = temperature
    guard
      let targetPercent = CustomFanCurvePolicy.nextTarget(
        temperature: temperature,
        configuration: configuration,
        state: &fanCurveDecisionState,
        now: Date(),
        riseLeadSeconds: fanCurveMode == .automatic ? 3 : 0)
    else { return }

    applyPreset(
      mode: .curve,
      curveStage: fanCurveMode == .automatic ? .dynamic : curveStage(for: targetPercent),
      curveTargetPercent: targetPercent
    ) { [helperClient] completion in
      helperClient.applyCurveTarget(percent: targetPercent, completion: completion)
    }
  }

  func saveFanCurveConfiguration(_ configuration: FanCurveConfiguration) -> Bool {
    guard !isFanCurveEnabled, configuration.isValid,
      curveConfigurationStore.save(configuration)
    else { return false }
    fanCurveConfiguration = configuration
    fanCurveDecisionState.reset()
    return true
  }

  func setFanCurveMode(_ mode: FanCurveMode) {
    guard !isFanCurveEnabled, fanCurveMode != mode else { return }
    fanCurveMode = mode
    curveModeStore.save(mode)
    if mode != .automatic, automaticallyResumeFullAutomatic {
      setAutomaticallyResumeFullAutomatic(false)
    }
    fanCurveDecisionState.reset()
    fanCurveTemperature = nil
    fanCurveTargetPercent = nil
  }

  func setAutomaticallyResumeFullAutomatic(_ enabled: Bool) {
    guard !enabled || fanCurveMode == .automatic else { return }
    automaticallyResumeFullAutomatic = enabled
    automaticResumeStore.save(enabled)
    if !enabled { pendingFullAutomaticResume = false }
  }

  private func attemptPendingFullAutomaticResume() {
    guard pendingFullAutomaticResume,
      automaticallyResumeFullAutomatic,
      fanCurveMode == .automatic,
      !isSleeping
    else { return }
    enableFanCurve()
    if isFanCurveEnabled { pendingFullAutomaticResume = false }
  }

  var effectiveFanCurveConfiguration: FanCurveConfiguration {
    fanCurveMode == .automatic ? .automatic : fanCurveConfiguration
  }

  func resetFanCurveConfiguration() {
    guard !isFanCurveEnabled else { return }
    _ = saveFanCurveConfiguration(.default)
  }

  func clearThermalHistory() {
    thermalHistory.removeAll()
    historySamplesSinceSave = 0
    thermalHistoryStore.clear()
  }

  private func curveStage(for percent: Int) -> FanCurveStage {
    switch percent {
    case ...30: .quiet
    case ...50: .balanced
    case ...80: .cool
    default: .max
    }
  }

  private func appendHistory(from snapshot: HardwareSnapshot) {
    thermalHistory.append(
      ThermalHistorySample(
        id: snapshot.capturedAt,
        cpuTemperature: snapshot.hottestTemperature(in: .cpu)?.temperature,
        gpuTemperature: snapshot.hottestTemperature(in: .gpu)?.temperature,
        fanRPMs: snapshot.fans.map(\.currentRPM)))
    if thermalHistory.count > ThermalHistoryStore.maximumSamples {
      thermalHistory.removeFirst(thermalHistory.count - ThermalHistoryStore.maximumSamples)
    }
    historySamplesSinceSave += 1
    if historySamplesSinceSave >= 10 { persistThermalHistory() }
  }

  private func persistThermalHistory() {
    guard historySamplesSinceSave > 0 else { return }
    if thermalHistoryStore.save(thermalHistory) {
      historySamplesSinceSave = 0
    }
  }
}

private enum ControlLeaseTiming {
  static let heartbeatSeconds = 5
}

private struct PreviewHelperInstaller: HelperInstalling {
  var status: HelperRegistrationStatus { .enabled }
  func register() throws {}
  func unregister() throws {}
  func openSystemSettings() {}
}

private struct PreviewHelperClient: HelperCommunicating {
  func probe(completion: @escaping @Sendable (Result<String, Error>) -> Void) {
    completion(.success(BreezeHelperConstants.helperVersion))
  }

  func automaticControlStatus(
    completion: @escaping @Sendable (Result<AutomaticControlStatus, Error>) -> Void
  ) {
    completion(
      .success(
        .init(
          isAutomatic: true, fanModes: [3, 3], forceTest: 0,
          message: "Apple automatic control is active.")))
  }

  func restoreAutomaticControl(
    completion: @escaping @Sendable (Result<AutomaticControlStatus, Error>) -> Void
  ) {
    automaticControlStatus(completion: completion)
  }

  func setFanRPM(
    fanID: Int, rpm: Int,
    completion: @escaping @Sendable (Result<FanControlStatus, Error>) -> Void
  ) {
    completion(
      .success(
        .init(
          success: true, fanID: fanID, requestedRPM: rpm, appliedRPM: rpm, actualRPM: rpm,
          minimumRPM: 1_200, maximumRPM: fanID == 0 ? 5_779 : 6_241,
          isManual: true, didRestoreAutomatic: false, message: "Manual target verified.")))
  }

  func setFanAutomatic(
    fanID: Int,
    completion: @escaping @Sendable (Result<FanControlStatus, Error>) -> Void
  ) {
    completion(
      .success(
        .init(
          success: true, fanID: fanID, requestedRPM: 0, appliedRPM: 0, actualRPM: 2_400,
          minimumRPM: 1_200, maximumRPM: fanID == 0 ? 5_779 : 6_241,
          isManual: false, didRestoreAutomatic: false, message: "Apple automatic control.")))
  }

  func applyBalancedPreset(
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    completion(
      .success(
        .init(
          success: true,
          targetRPMs: [2_800, 2_950],
          actualRPMs: [2_800, 2_950],
          didRestoreAutomatic: false,
          message: "Balanced preset reached and verified on both fans."
        )))
  }

  func applyQuietPreset(
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    completion(
      .success(
        .init(
          success: true,
          targetRPMs: [2_100, 2_200],
          actualRPMs: [2_100, 2_200],
          didRestoreAutomatic: false,
          message: "Quiet preset reached and verified on both fans."
        )))
  }

  func applyCoolPreset(
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    completion(
      .success(
        .init(
          success: true,
          targetRPMs: [3_950, 4_200],
          actualRPMs: [3_950, 4_200],
          didRestoreAutomatic: false,
          message: "Cool preset reached and verified on both fans."
        )))
  }

  func applyMaxPreset(
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    completion(
      .success(
        .init(
          success: true,
          targetRPMs: [5_779, 6_241],
          actualRPMs: [5_779, 6_241],
          didRestoreAutomatic: false,
          message: "Max preset reached and verified on both fans."
        )))
  }

  func applyCurveTarget(
    percent: Int,
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    let fan0 = 1_200 + Int((5_779 - 1_200) * percent / 100)
    let fan1 = 1_200 + Int((6_241 - 1_200) * percent / 100)
    completion(
      .success(
        .init(
          success: true,
          targetRPMs: [fan0, fan1],
          actualRPMs: [fan0, fan1],
          didRestoreAutomatic: false,
          message: "Curve target verified on both fans."
        )))
  }

  func renewControlLease(
    completion: @escaping @Sendable (Result<ControlLeaseStatus, Error>) -> Void
  ) {
    completion(
      .success(
        .init(
          isActive: true, remainingSeconds: 15, message: "Manual-control lease renewed.")))
  }

  func controlLeaseStatus(
    completion: @escaping @Sendable (Result<ControlLeaseStatus, Error>) -> Void
  ) {
    completion(
      .success(
        .init(
          isActive: false, remainingSeconds: 0, message: "No manual-control lease is active.")))
  }
}

extension AppState {
  static var preview: AppState {
    AppState(
      previewSnapshot: HardwareSnapshot(
        hardware: MacHardware(
          modelIdentifier: "MacBookPro18,3",
          chipName: "Apple M1 Pro",
          architecture: "arm64",
          fanCount: 2,
          isControlVerified: true
        ),
        fans: [
          FanState(id: 0, currentRPM: 2_321, minimumRPM: 1_200, maximumRPM: 5_779),
          FanState(id: 1, currentRPM: 2_472, minimumRPM: 1_200, maximumRPM: 6_241),
        ],
        sensors: [
          ThermalSensor(id: "cpu", name: "CPU", temperature: 70.6, category: .cpu),
          ThermalSensor(id: "gpu", name: "GPU", temperature: 70.9, category: .gpu),
          ThermalSensor(id: "memory", name: "Memory", temperature: 60.1, category: .memory),
          ThermalSensor(id: "TB1T", name: "Battery", temperature: 35.9, category: .system),
        ]
      )
    )
  }
}
