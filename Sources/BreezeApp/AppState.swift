import AppKit
import Foundation
import OSLog
import Observation

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
@Observable
final class AppState {
  private(set) var snapshot: HardwareSnapshot?
  private(set) var errorMessage: String?
  private(set) var isLoading = true
  private(set) var lastSuccessfulUpdate: Date?
  private(set) var isSleeping = false
  private(set) var isPopoverVisible = false
  private(set) var helperStatus: HelperRegistrationStatus = .notRegistered
  private(set) var helperVersion: String?
  private(set) var helperErrorMessage: String?
  private(set) var isCheckingHelper = false
  private(set) var automaticControlStatus: AutomaticControlStatus?
  private(set) var isRestoringAutomaticControl = false
  private(set) var fanControlStatuses: [Int: FanControlStatus] = [:]
  private(set) var fansApplyingControl: Set<Int> = []
  private(set) var controlLeaseStatus: ControlLeaseStatus?
  private(set) var presetControlStatus: PresetControlStatus?
  private(set) var activeControlMode: ActiveFanControlMode = .automatic
  private(set) var isApplyingPreset = false
  private(set) var isFanCurveEnabled = false
  private(set) var fanCurveStage: FanCurveStage = .automatic
  private(set) var fanCurveTemperature: Double?

  @ObservationIgnored private let logger = Logger(
    subsystem: "com.breeze.monitor", category: "Hardware")
  @ObservationIgnored private let monitor: (any HardwareMonitoring)?
  @ObservationIgnored private let helperInstaller: any HelperInstalling
  @ObservationIgnored private let helperClient: any HelperCommunicating
  @ObservationIgnored private let terminateApp: @MainActor () -> Void
  @ObservationIgnored private var pollingTask: Task<Void, Never>?
  @ObservationIgnored private var leaseHeartbeatTask: Task<Void, Never>?
  @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []

  init(
    monitor: (any HardwareMonitoring)? = nil,
    helperInstaller: any HelperInstalling = SystemHelperInstaller(),
    helperClient: any HelperCommunicating = HelperClient(),
    terminateApp: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
  ) {
    self.helperInstaller = helperInstaller
    self.helperClient = helperClient
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
    terminateApp = {}
    helperStatus = .enabled
    helperVersion = "0.8.0"
    monitor = nil
    snapshot = previewSnapshot
    lastSuccessfulUpdate = previewSnapshot.capturedAt
    isLoading = false
  }

  func start() {
    guard pollingTask == nil else { return }
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
    request: (@escaping @Sendable (Result<PresetControlStatus, Error>) -> Void) -> Void
  ) {
    guard let snapshot,
      snapshot.fans.count == 2,
      snapshot.fans.allSatisfy({ canControlFan($0.id) }),
      !isApplyingPreset,
      !isRestoringAutomaticControl,
      fansApplyingControl.isEmpty
    else { return }
    isApplyingPreset = true
    helperErrorMessage = nil
    request { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
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
            self.startLeaseHeartbeat()
          } else if status.didRestoreAutomatic {
            if mode == .curve { self.deactivateFanCurve() }
            self.activeControlMode = .automatic
            self.stopLeaseHeartbeat()
          }
        case .failure(let error):
          if mode == .curve {
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
      }
    }
  }

  func quitBreeze() {
    deactivateFanCurve()
    guard helperStatus == .enabled else {
      terminateApp()
      return
    }
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
        let seconds = MonitoringPolicy.refreshInterval(isPopoverVisible: isPopoverVisible)
        try await Task.sleep(for: .seconds(seconds))
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
          try await Task.sleep(for: .seconds(ControlLeaseTiming.heartbeatSeconds))
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
      evaluateFanCurve(using: updated)
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
          self.checkAutomaticControl()
        }
      }
    )
  }

  func enableFanCurve() {
    guard let snapshot,
      snapshot.fans.count == 2,
      snapshot.fans.allSatisfy({ canControlFan($0.id) }),
      FanCurvePolicy.controlTemperature(for: snapshot) != nil,
      !isRestoringAutomaticControl,
      !isApplyingPreset,
      fansApplyingControl.isEmpty
    else { return }
    isFanCurveEnabled = true
    fanCurveStage = .automatic
    presetControlStatus = nil
    // Establish a known-safe baseline before the curve takes ownership. This
    // prevents enabling the curve while a prior manual or preset mode is active.
    restoreAutomaticControl(preservingCurve: true) { [weak self] in
      guard let self, self.isFanCurveEnabled, let snapshot = self.snapshot else { return }
      self.evaluateFanCurve(using: snapshot)
    }
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
  }

  private func evaluateFanCurve(using snapshot: HardwareSnapshot) {
    guard isFanCurveEnabled,
      !isSleeping,
      !isApplyingPreset,
      !isRestoringAutomaticControl,
      fansApplyingControl.isEmpty
    else { return }

    guard let temperature = FanCurvePolicy.controlTemperature(for: snapshot) else {
      deactivateFanCurve()
      restoreAutomaticControl(preservingCurve: false)
      return
    }

    fanCurveTemperature = temperature
    let desiredStage = FanCurvePolicy.stage(for: temperature, previous: fanCurveStage)
    guard desiredStage != fanCurveStage else { return }

    switch desiredStage {
    case .automatic:
      restoreAutomaticControl(preservingCurve: true)
    case .balanced:
      applyPreset(mode: .curve, curveStage: .balanced) { [helperClient] completion in
        helperClient.applyBalancedPreset(completion: completion)
      }
    case .cool:
      applyPreset(mode: .curve, curveStage: .cool) { [helperClient] completion in
        helperClient.applyCoolPreset(completion: completion)
      }
    case .max:
      applyPreset(mode: .curve, curveStage: .max) { [helperClient] completion in
        helperClient.applyMaxPreset(completion: completion)
      }
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
    completion(.success("0.8.0"))
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
