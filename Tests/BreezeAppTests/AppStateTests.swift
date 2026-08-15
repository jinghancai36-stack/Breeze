import AppKit
import BreezeHardware
import BreezeIPC
import Foundation
import Testing

@testable import BreezeApp

private final class StubMonitor: HardwareMonitoring, @unchecked Sendable {
  private let lock = NSLock()
  private var reads = 0
  private var failing = false
  private let controlVerified: Bool
  private var temperature: Double?

  init(controlVerified: Bool = false, temperature: Double? = 60) {
    self.controlVerified = controlVerified
    self.temperature = temperature
  }

  var readCount: Int {
    lock.withLock { reads }
  }

  func setFailing(_ value: Bool) {
    lock.withLock { failing = value }
  }

  func setTemperature(_ value: Double?) {
    lock.withLock { temperature = value }
  }

  func detectHardware() throws -> MacHardware {
    MacHardware(
      modelIdentifier: "MacBookPro18,3",
      chipName: "Apple M1 Pro",
      architecture: "arm64",
      fanCount: 2,
      isControlVerified: controlVerified
    )
  }

  func discoverFans() throws -> [FanState] {
    [
      FanState(id: 0, currentRPM: 2_000, minimumRPM: 1_200, maximumRPM: 5_779),
      FanState(id: 1, currentRPM: 2_100, minimumRPM: 1_200, maximumRPM: 6_241),
    ]
  }

  func readTemperatures() throws -> [ThermalSensor] {
    guard let temperature = lock.withLock({ temperature }) else { return [] }
    return [ThermalSensor(id: "cpu", name: "CPU", temperature: temperature, category: .cpu)]
  }

  func snapshot() throws -> HardwareSnapshot {
    let shouldFail = lock.withLock {
      reads += 1
      return failing
    }
    if shouldFail {
      throw BreezeHardwareError.ioKit(-1)
    }
    return HardwareSnapshot(
      hardware: try detectHardware(),
      fans: try discoverFans(),
      sensors: try readTemperatures()
    )
  }
}

private final class StubHelperInstaller: HelperInstalling, @unchecked Sendable {
  var currentStatus: HelperRegistrationStatus = .notRegistered
  var registerCount = 0
  var unregisterCount = 0
  var openSettingsCount = 0

  var status: HelperRegistrationStatus { currentStatus }

  func register() throws {
    registerCount += 1
    currentStatus = .enabled
  }

  func unregister() throws {
    unregisterCount += 1
    currentStatus = .notRegistered
  }

  func openSystemSettings() {
    openSettingsCount += 1
  }
}

private final class StubHelperClient: HelperCommunicating, @unchecked Sendable {
  let result: Result<String, Error>
  var automaticResult: Result<AutomaticControlStatus, Error>
  var leaseResult: Result<ControlLeaseStatus, Error>
  var presetResult: Result<PresetControlStatus, Error>
  var quietPresetResult: Result<PresetControlStatus, Error>
  var coolPresetResult: Result<PresetControlStatus, Error>
  var maxPresetResult: Result<PresetControlStatus, Error>
  private(set) var restoreCount = 0
  private(set) var renewalCount = 0
  private(set) var presetCount = 0
  private(set) var quietPresetCount = 0
  private(set) var coolPresetCount = 0
  private(set) var maxPresetCount = 0
  private(set) var curveTargetPercents: [Int] = []
  private let deferRenewal: Bool
  private var pendingRenewal:
    (@Sendable (Result<ControlLeaseStatus, Error>) -> Void)?

  init(
    result: Result<String, Error>,
    automaticResult: Result<AutomaticControlStatus, Error> = .success(
      .init(isAutomatic: true, fanModes: [3, 3], forceTest: 0, message: "Automatic")),
    leaseResult: Result<ControlLeaseStatus, Error> = .success(
      .init(isActive: true, remainingSeconds: 15, message: "Lease renewed")),
    presetResult: Result<PresetControlStatus, Error> = .success(
      .init(
        success: true, targetRPMs: [2_800, 2_950], actualRPMs: [2_800, 2_950],
        didRestoreAutomatic: false, message: "Balanced")),
    quietPresetResult: Result<PresetControlStatus, Error> = .success(
      .init(
        success: true, targetRPMs: [2_100, 2_200], actualRPMs: [2_100, 2_200],
        didRestoreAutomatic: false, message: "Quiet")),
    coolPresetResult: Result<PresetControlStatus, Error> = .success(
      .init(
        success: true, targetRPMs: [3_950, 4_200], actualRPMs: [3_950, 4_200],
        didRestoreAutomatic: false, message: "Cool")),
    maxPresetResult: Result<PresetControlStatus, Error> = .success(
      .init(
        success: true, targetRPMs: [5_779, 6_241], actualRPMs: [5_779, 6_241],
        didRestoreAutomatic: false, message: "Max")),
    deferRenewal: Bool = false
  ) {
    self.result = result
    self.automaticResult = automaticResult
    self.leaseResult = leaseResult
    self.presetResult = presetResult
    self.quietPresetResult = quietPresetResult
    self.coolPresetResult = coolPresetResult
    self.maxPresetResult = maxPresetResult
    self.deferRenewal = deferRenewal
  }

  func probe(completion: @escaping @Sendable (Result<String, Error>) -> Void) {
    completion(result)
  }

  func automaticControlStatus(
    completion: @escaping @Sendable (Result<AutomaticControlStatus, Error>) -> Void
  ) {
    completion(automaticResult)
  }

  func restoreAutomaticControl(
    completion: @escaping @Sendable (Result<AutomaticControlStatus, Error>) -> Void
  ) {
    restoreCount += 1
    completion(automaticResult)
  }

  func setFanRPM(
    fanID: Int, rpm: Int,
    completion: @escaping @Sendable (Result<FanControlStatus, Error>) -> Void
  ) {
    completion(
      .success(
        .init(
          success: true, fanID: fanID, requestedRPM: rpm, appliedRPM: rpm, actualRPM: rpm,
          minimumRPM: 1_200, maximumRPM: 6_000, isManual: true,
          didRestoreAutomatic: false, message: "Manual")))
  }

  func setFanAutomatic(
    fanID: Int,
    completion: @escaping @Sendable (Result<FanControlStatus, Error>) -> Void
  ) {
    completion(
      .success(
        .init(
          success: true, fanID: fanID, requestedRPM: 0, appliedRPM: 0, actualRPM: 2_000,
          minimumRPM: 1_200, maximumRPM: 6_000, isManual: false,
          didRestoreAutomatic: false, message: "Automatic")))
  }

  func renewControlLease(
    completion: @escaping @Sendable (Result<ControlLeaseStatus, Error>) -> Void
  ) {
    renewalCount += 1
    if deferRenewal {
      pendingRenewal = completion
    } else {
      completion(leaseResult)
    }
  }

  func completePendingRenewal(
    with result: Result<ControlLeaseStatus, Error>
  ) {
    let completion = pendingRenewal
    pendingRenewal = nil
    completion?(result)
  }

  func controlLeaseStatus(
    completion: @escaping @Sendable (Result<ControlLeaseStatus, Error>) -> Void
  ) {
    completion(
      .success(
        .init(
          isActive: false, remainingSeconds: 0, message: "No manual-control lease is active.")))
  }

  func applyBalancedPreset(
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    presetCount += 1
    completion(presetResult)
  }

  func applyQuietPreset(
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    quietPresetCount += 1
    completion(quietPresetResult)
  }

  func applyCoolPreset(
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    coolPresetCount += 1
    completion(coolPresetResult)
  }

  func applyMaxPreset(
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    maxPresetCount += 1
    completion(maxPresetResult)
  }

  func applyCurveTarget(
    percent: Int,
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    curveTargetPercents.append(percent)
    let fan0 = 1_200 + Int(Double(5_779 - 1_200) * Double(percent) / 100)
    let fan1 = 1_200 + Int(Double(6_241 - 1_200) * Double(percent) / 100)
    completion(
      .success(
        .init(
          success: true, targetRPMs: [fan0, fan1], actualRPMs: [fan0, fan1],
          didRestoreAutomatic: false, message: "Curve \(percent)%")))
  }
}

@Suite("App state")
@MainActor
struct AppStateTests {
  @Test("A refresh publishes a complete snapshot")
  func refresh() async throws {
    let suite = "BreezeRefreshHistoryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let monitor = StubMonitor()
    let state = AppState(
      monitor: monitor,
      thermalHistoryStore: ThermalHistoryStore(defaults: defaults))

    await state.refreshForTesting()

    #expect(state.snapshot?.fans.count == 2)
    #expect(state.snapshot?.primaryTemperature?.temperature == 60)
    #expect(state.lastSuccessfulUpdate != nil)
    #expect(state.thermalHistory.count == 1)
    #expect(state.errorMessage == nil)
    #expect(monitor.readCount == 1)
  }

  @Test("Popover visibility selects foreground polling")
  func visibility() {
    let state = AppState(monitor: StubMonitor())
    state.setPopoverVisible(true)
    #expect(state.isPopoverVisible)
    state.setPopoverVisible(false)
    #expect(!state.isPopoverVisible)
  }

  @Test("History restores at launch, saves in batches, and clears")
  func historyLifecycle() async throws {
    let suite = "BreezeAppStateHistoryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ThermalHistoryStore(defaults: defaults)
    let existing = ThermalHistorySample(
      id: Date(timeIntervalSinceReferenceDate: 100),
      cpuTemperature: 55, gpuTemperature: 52, fanRPMs: [2_000, 2_100])
    #expect(store.save([existing]))

    let state = AppState(monitor: StubMonitor(), thermalHistoryStore: store)
    #expect(state.thermalHistory == [existing])

    for _ in 0..<10 { await state.refreshForTesting() }
    #expect(store.load().count == 11)

    state.clearThermalHistory()
    #expect(state.thermalHistory.isEmpty)
    #expect(store.load().isEmpty)
  }

  @Test("A temporary read failure preserves the last good snapshot")
  func staleSnapshot() async {
    let monitor = StubMonitor()
    let state = AppState(monitor: monitor)
    await state.refreshForTesting()
    let firstSnapshot = state.snapshot

    monitor.setFailing(true)
    await state.refreshForTesting()

    #expect(state.snapshot == firstSnapshot)
    #expect(state.errorMessage != nil)
    #expect(state.lastSuccessfulUpdate == firstSnapshot?.capturedAt)
  }

  @Test("All four menu bar presentation modes are available")
  func menuBarModes() {
    #expect(
      MenuBarDisplay.allCases.map(\.rawValue) == [
        "icon", "temperature", "rpm", "temperatureAndRPM",
      ])
    #expect(!MenuBarDisplay.icon.showsTemperature)
    #expect(!MenuBarDisplay.icon.showsRPM)
    #expect(MenuBarDisplay.temperature.showsTemperature)
    #expect(!MenuBarDisplay.temperature.showsRPM)
    #expect(!MenuBarDisplay.rpm.showsTemperature)
    #expect(MenuBarDisplay.rpm.showsRPM)
    #expect(MenuBarDisplay.temperatureAndRPM.showsTemperature)
    #expect(MenuBarDisplay.temperatureAndRPM.showsRPM)
  }

  @Test("Automatic curve uses CPU or GPU peak and applies hysteresis")
  func fanCurvePolicy() {
    let snapshot = HardwareSnapshot(
      hardware: MacHardware(
        modelIdentifier: "MacBookPro18,3", chipName: "Apple M1 Pro",
        architecture: "arm64", fanCount: 2, isControlVerified: true),
      fans: [],
      sensors: [
        ThermalSensor(id: "cpu", name: "CPU", temperature: 66, category: .cpu),
        ThermalSensor(id: "gpu", name: "GPU", temperature: 77, category: .gpu),
      ])

    #expect(FanCurvePolicy.controlTemperature(for: snapshot) == 77)
    #expect(
      FanCurvePolicy.controlTemperature(
        for: HardwareSnapshot(hardware: snapshot.hardware, fans: [], sensors: [])) == nil)
    #expect(FanCurvePolicy.stage(for: 59, previous: .automatic) == .quiet)
    #expect(FanCurvePolicy.stage(for: 59, previous: .quiet) == .quiet)
    #expect(FanCurvePolicy.stage(for: 60, previous: .automatic) == .balanced)
    #expect(FanCurvePolicy.stage(for: 74, previous: .balanced) == .balanced)
    #expect(FanCurvePolicy.stage(for: 75, previous: .balanced) == .cool)
    #expect(FanCurvePolicy.stage(for: 88, previous: .cool) == .max)
    #expect(FanCurvePolicy.stage(for: 83, previous: .max) == .max)
    #expect(FanCurvePolicy.stage(for: 81, previous: .max) == .cool)
    #expect(FanCurvePolicy.stage(for: 67, previous: .cool) == .balanced)
    #expect(FanCurvePolicy.stage(for: 51, previous: .balanced) == .quiet)
  }

  @Test("Automatic curve restores Apple control if its temperature source disappears")
  func fanCurveMissingTemperature() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(result: .success(BreezeHelperConstants.helperVersion))
    let monitor = StubMonitor(controlVerified: true, temperature: 76)
    let state = AppState(monitor: monitor, helperInstaller: installer, helperClient: client)

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    state.enableFanCurve()
    for _ in 0..<50 where state.fanCurveStage != .cool {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    monitor.setTemperature(nil)
    await state.refreshForTesting()
    for _ in 0..<50 where client.restoreCount < 1 || state.isRestoringAutomaticControl {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(!state.isFanCurveEnabled)
    #expect(state.fanCurveStage == .automatic)
    #expect(state.activeControlMode == .automatic)
    #expect(client.restoreCount == 1)
  }

  @Test("Automatic curve applies a bounded target and disabling restores Automatic")
  func fanCurveLifecycle() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(result: .success(BreezeHelperConstants.helperVersion))
    let state = AppState(
      monitor: StubMonitor(controlVerified: true, temperature: 76),
      helperInstaller: installer,
      helperClient: client)

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    state.enableFanCurve()
    for _ in 0..<50 where client.curveTargetPercents.isEmpty || client.renewalCount == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(state.isFanCurveEnabled)
    #expect(state.fanCurveStage == .cool)
    #expect(state.activeControlMode == .curve)
    #expect(client.curveTargetPercents == [65])
    #expect(state.fanCurveTargetPercent == 65)
    #expect(client.restoreCount == 0)
    #expect(state.controlLeaseStatus?.isActive == true)

    state.disableFanCurve()
    for _ in 0..<50 where client.restoreCount < 1 || state.isRestoringAutomaticControl {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(!state.isFanCurveEnabled)
    #expect(state.fanCurveStage == .automatic)
    #expect(state.activeControlMode == .automatic)
    #expect(state.controlLeaseStatus == nil)
    #expect(client.restoreCount == 1)
  }

  @Test("Automatic curve keeps a low-temperature custom target under the watchdog")
  func fanCurveQuietOwnership() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(result: .success(BreezeHelperConstants.helperVersion))
    let monitor = StubMonitor(controlVerified: true, temperature: 55)
    let state = AppState(
      monitor: monitor, helperInstaller: installer, helperClient: client)

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    state.enableFanCurve()
    for _ in 0..<50 where state.fanCurveStage != .quiet || client.renewalCount == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(state.isFanCurveEnabled)
    #expect(state.activeControlMode == .curve)
    #expect(client.curveTargetPercents == [30])
    #expect(client.restoreCount == 0)
    #expect(state.controlLeaseStatus?.isActive == true)

    monitor.setTemperature(61)
    await state.refreshForTesting()
    for _ in 0..<50 where state.fanCurveStage != .balanced {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(client.curveTargetPercents == [30, 35])
    #expect(client.restoreCount == 0)
    #expect(state.isFanCurveEnabled)

    state.disableFanCurve()
  }

  @Test("A stale heartbeat cannot cancel or corrupt an explicit curve restore")
  func staleHeartbeatAfterCurveDisable() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(
      result: .success(BreezeHelperConstants.helperVersion), deferRenewal: true)
    let state = AppState(
      monitor: StubMonitor(controlVerified: true, temperature: 55),
      helperInstaller: installer,
      helperClient: client)

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    state.enableFanCurve()
    for _ in 0..<50 where client.renewalCount == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    state.disableFanCurve()
    for _ in 0..<50 where state.isRestoringAutomaticControl {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    client.completePendingRenewal(
      with: .success(
        .init(isActive: false, remainingSeconds: 0, message: "Old lease is inactive.")))
    await Task.yield()

    #expect(!state.isFanCurveEnabled)
    #expect(state.fanCurveStage == .automatic)
    #expect(state.activeControlMode == .automatic)
    #expect(state.helperErrorMessage == nil)
    #expect(state.controlLeaseStatus == nil)
    #expect(client.restoreCount == 1)
  }

  @Test("Sleep pauses polling and wake performs an immediate refresh")
  func sleepAndWake() async throws {
    let suite = "BreezeSleepWakeHistoryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let monitor = StubMonitor()
    let state = AppState(
      monitor: monitor,
      thermalHistoryStore: ThermalHistoryStore(defaults: defaults))
    state.start()
    defer { state.stop() }

    NSWorkspace.shared.notificationCenter.post(
      name: NSWorkspace.willSleepNotification, object: nil)
    await Task.yield()
    #expect(state.isSleeping)

    // Let an already-scheduled initial poll settle before measuring wake behavior.
    try await Task.sleep(nanoseconds: 20_000_000)
    let readsBeforeWake = monitor.readCount
    NSWorkspace.shared.notificationCenter.post(
      name: NSWorkspace.didWakeNotification, object: nil)

    for _ in 0..<50 {
      if !state.isSleeping, monitor.readCount > readsBeforeWake { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(!state.isSleeping)
    #expect(monitor.readCount > readsBeforeWake)
  }

  @Test("Helper registration and ping state stay in AppState")
  func helperState() async throws {
    let installer = StubHelperInstaller()
    let helper = StubHelperClient(result: .success(BreezeHelperConstants.helperVersion))
    let state = AppState(
      monitor: StubMonitor(),
      helperInstaller: installer,
      helperClient: helper
    )

    #expect(state.helperStatus == .notRegistered)
    state.installHelper()
    #expect(state.helperStatus == .enabled)
    #expect(installer.registerCount == 1)

    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(state.helperVersion == BreezeHelperConstants.helperVersion)
    #expect(state.helperErrorMessage == nil)

    state.uninstallHelper()
    for _ in 0..<50 where installer.unregisterCount == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(state.helperStatus == .notRegistered)
    #expect(installer.unregisterCount == 1)
    #expect(helper.restoreCount == 1)
  }

  @Test("Helper removal is refused unless Automatic is verified")
  func helperRemovalRequiresAutomatic() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let helper = StubHelperClient(
      result: .success(BreezeHelperConstants.helperVersion),
      automaticResult: .success(
        .init(
          isAutomatic: false, fanModes: [1, 0], forceTest: nil,
          message: "Fan 0 remained manual.")))
    let state = AppState(
      monitor: StubMonitor(), helperInstaller: installer, helperClient: helper)

    state.uninstallHelper()
    for _ in 0..<50 where state.isRestoringAutomaticControl {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(helper.restoreCount == 1)
    #expect(installer.unregisterCount == 0)
    #expect(state.helperStatus == .enabled)
    #expect(state.helperErrorMessage?.contains("cancelled") == true)
  }

  @Test("Automatic restore result is published")
  func automaticRestore() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: StubHelperClient(result: .success(BreezeHelperConstants.helperVersion))
    )

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    state.setFanRPM(fanID: 0, rpm: 1_400)
    for _ in 0..<50 where state.fanControlStatuses[0] == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(state.fanControlStatuses[0]?.isManual == true)

    state.restoreAutomaticControl()
    for _ in 0..<50 where state.automaticControlStatus == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(state.automaticControlStatus?.isAutomatic == true)
    #expect(state.automaticControlStatus?.fanModes == [3, 3])
    #expect(state.automaticControlStatus?.forceTest == 0)
    #expect(state.fanControlStatuses.isEmpty)
    #expect(!state.isRestoringAutomaticControl)
  }

  @Test("Verified hardware can publish manual and automatic fan results")
  func manualFanState() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(result: .success(BreezeHelperConstants.helperVersion))
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: client
    )
    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(state.canControlFan(0))

    state.setFanRPM(fanID: 0, rpm: 1_400)
    for _ in 0..<50 where state.fanControlStatuses[0] == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(state.fanControlStatuses[0]?.isManual == true)
    #expect(state.fanControlStatuses[0]?.appliedRPM == 1_400)
    for _ in 0..<50 where client.renewalCount == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(client.renewalCount == 1)
    #expect(state.controlLeaseStatus?.isActive == true)

    state.setFanAutomatic(fanID: 0)
    for _ in 0..<50 where state.fanControlStatuses[0]?.isManual == true {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(state.fanControlStatuses[0]?.isManual == false)
    #expect(state.controlLeaseStatus == nil)

    state.setFanRPM(fanID: 0, rpm: 1_450)
    for _ in 0..<50 where client.renewalCount < 2 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(client.renewalCount == 2)
    #expect(state.controlLeaseStatus?.isActive == true)
  }

  @Test("Balanced publishes dynamic targets and uses the safety heartbeat")
  func balancedState() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(result: .success(BreezeHelperConstants.helperVersion))
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: client)

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    state.applyBalancedPreset()
    for _ in 0..<50 where client.presetCount == 0 || client.renewalCount == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(client.presetCount == 1)
    #expect(state.activeControlMode == .balanced)
    #expect(state.presetControlStatus?.targetRPMs == [2_800, 2_950])
    #expect(state.controlLeaseStatus?.isActive == true)

    state.restoreAutomaticControl()
    for _ in 0..<50 where state.activeControlMode != .automatic {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(state.presetControlStatus == nil)
    #expect(state.controlLeaseStatus == nil)
  }

  @Test("A failed Balanced request never renews an uncertain control state")
  func failedBalancedDoesNotHeartbeat() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(
      result: .success(BreezeHelperConstants.helperVersion),
      presetResult: .success(
        .init(
          success: false, targetRPMs: [2_800, 2_950], actualRPMs: [2_800, 0],
          didRestoreAutomatic: false, message: "Second fan failed.")))
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: client)

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    state.applyBalancedPreset()
    for _ in 0..<50 where state.presetControlStatus == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(state.activeControlMode == .automatic)
    #expect(client.renewalCount == 0)
    #expect(state.helperErrorMessage == "Second fan failed.")
  }

  @Test("Cool publishes its dynamic targets and uses the safety heartbeat")
  func coolState() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(result: .success(BreezeHelperConstants.helperVersion))
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: client)

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    state.applyCoolPreset()
    for _ in 0..<50 where client.coolPresetCount == 0 || client.renewalCount == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(client.coolPresetCount == 1)
    #expect(state.activeControlMode == .cool)
    #expect(state.presetControlStatus?.targetRPMs == [3_950, 4_200])
    #expect(state.controlLeaseStatus?.isActive == true)
  }

  @Test("Max publishes each verified maximum and uses the safety heartbeat")
  func maxState() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(result: .success(BreezeHelperConstants.helperVersion))
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: client)

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    state.applyMaxPreset()
    for _ in 0..<50 where client.maxPresetCount == 0 || client.renewalCount == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(client.maxPresetCount == 1)
    #expect(state.activeControlMode == .max)
    #expect(state.presetControlStatus?.targetRPMs == [5_779, 6_241])
    #expect(state.controlLeaseStatus?.isActive == true)
  }

  @Test("A mismatched Helper version keeps Manual disabled")
  func helperVersionGate() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: StubHelperClient(result: .success("0.5.0")))

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(state.helperVersion == "0.5.0")
    #expect(!state.canControlFan(0))
    state.setFanRPM(fanID: 0, rpm: 1_400)
    #expect(state.fanControlStatuses.isEmpty)
  }

  @Test("Sleep requests Automatic and wake never resumes Manual")
  func sleepSafety() async throws {
    let suite = "BreezeSleepSafetyHistoryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(result: .success(BreezeHelperConstants.helperVersion))
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: client,
      thermalHistoryStore: ThermalHistoryStore(defaults: defaults))
    state.start()
    defer { state.stop() }
    await state.refreshForTesting()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    state.setFanRPM(fanID: 0, rpm: 1_400)
    for _ in 0..<50 where state.fanControlStatuses[0]?.isManual != true {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    NSWorkspace.shared.notificationCenter.post(
      name: NSWorkspace.willSleepNotification, object: nil)
    for _ in 0..<50
    where client.restoreCount == 0 || !state.fanControlStatuses.isEmpty
      || state.isRestoringAutomaticControl
    {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(client.restoreCount == 1)
    #expect(state.fanControlStatuses.isEmpty)

    NSWorkspace.shared.notificationCenter.post(
      name: NSWorkspace.didWakeNotification, object: nil)
    try await Task.sleep(nanoseconds: 30_000_000)
    #expect(state.fanControlStatuses.isEmpty)
    #expect(state.automaticControlStatus?.isAutomatic == true)
  }

  @Test("Quit terminates only after automatic control is verified")
  func verifiedQuit() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    var didTerminate = false
    let state = AppState(
      monitor: StubMonitor(),
      helperInstaller: installer,
      helperClient: StubHelperClient(result: .success(BreezeHelperConstants.helperVersion)),
      terminateApp: { didTerminate = true }
    )

    state.quitBreeze()
    for _ in 0..<50 where !didTerminate {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(didTerminate)
    #expect(state.automaticControlStatus?.isAutomatic == true)
    #expect(state.helperErrorMessage == nil)
  }

  @Test("Quit stays open when automatic control cannot be verified")
  func rejectedQuit() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    var didTerminate = false
    let failedStatus = AutomaticControlStatus(
      isAutomatic: false,
      fanModes: [1, 0],
      forceTest: nil,
      message: "Fan 0 remained manual."
    )
    let state = AppState(
      monitor: StubMonitor(),
      helperInstaller: installer,
      helperClient: StubHelperClient(
        result: .success(BreezeHelperConstants.helperVersion), automaticResult: .success(failedStatus)),
      terminateApp: { didTerminate = true }
    )

    state.quitBreeze()
    for _ in 0..<50 where state.isRestoringAutomaticControl {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(!didTerminate)
    #expect(state.automaticControlStatus == failedStatus)
    #expect(state.helperErrorMessage == "Fan 0 remained manual.")
  }
}
