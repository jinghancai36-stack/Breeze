import AppKit
import BreezeHardware
import Foundation
import Testing

@testable import BreezeApp

private final class StubMonitor: HardwareMonitoring, @unchecked Sendable {
  private let lock = NSLock()
  private var reads = 0
  private var failing = false
  private let controlVerified: Bool

  init(controlVerified: Bool = false) {
    self.controlVerified = controlVerified
  }

  var readCount: Int {
    lock.withLock { reads }
  }

  func setFailing(_ value: Bool) {
    lock.withLock { failing = value }
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
    [ThermalSensor(id: "cpu", name: "CPU", temperature: 60, category: .cpu)]
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
  var coolPresetResult: Result<PresetControlStatus, Error>
  var maxPresetResult: Result<PresetControlStatus, Error>
  private(set) var restoreCount = 0
  private(set) var renewalCount = 0
  private(set) var presetCount = 0
  private(set) var coolPresetCount = 0
  private(set) var maxPresetCount = 0

  init(
    result: Result<String, Error>,
    automaticResult: Result<AutomaticControlStatus, Error> = .success(
      .init(isAutomatic: true, fanModes: [3, 3], forceTest: 0, message: "Automatic")),
    leaseResult: Result<ControlLeaseStatus, Error> = .success(
      .init(isActive: true, remainingSeconds: 15, message: "Lease renewed")),
    presetResult: Result<PresetControlStatus, Error> = .success(.init(
      success: true, targetRPMs: [2_800, 2_950], actualRPMs: [2_800, 2_950],
      didRestoreAutomatic: false, message: "Balanced")),
    coolPresetResult: Result<PresetControlStatus, Error> = .success(.init(
      success: true, targetRPMs: [3_950, 4_200], actualRPMs: [3_950, 4_200],
      didRestoreAutomatic: false, message: "Cool")),
    maxPresetResult: Result<PresetControlStatus, Error> = .success(.init(
      success: true, targetRPMs: [5_779, 6_241], actualRPMs: [5_779, 6_241],
      didRestoreAutomatic: false, message: "Max"))
  ) {
    self.result = result
    self.automaticResult = automaticResult
    self.leaseResult = leaseResult
    self.presetResult = presetResult
    self.coolPresetResult = coolPresetResult
    self.maxPresetResult = maxPresetResult
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
    completion(.success(.init(
      success: true, fanID: fanID, requestedRPM: rpm, appliedRPM: rpm, actualRPM: rpm,
      minimumRPM: 1_200, maximumRPM: 6_000, isManual: true,
      didRestoreAutomatic: false, message: "Manual")))
  }

  func setFanAutomatic(
    fanID: Int,
    completion: @escaping @Sendable (Result<FanControlStatus, Error>) -> Void
  ) {
    completion(.success(.init(
      success: true, fanID: fanID, requestedRPM: 0, appliedRPM: 0, actualRPM: 2_000,
      minimumRPM: 1_200, maximumRPM: 6_000, isManual: false,
      didRestoreAutomatic: false, message: "Automatic")))
  }

  func renewControlLease(
    completion: @escaping @Sendable (Result<ControlLeaseStatus, Error>) -> Void
  ) {
    renewalCount += 1
    completion(leaseResult)
  }

  func controlLeaseStatus(
    completion: @escaping @Sendable (Result<ControlLeaseStatus, Error>) -> Void
  ) {
    completion(.success(.init(
      isActive: false, remainingSeconds: 0, message: "No manual-control lease is active.")))
  }

  func applyBalancedPreset(
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    presetCount += 1
    completion(presetResult)
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
}

@Suite("App state")
@MainActor
struct AppStateTests {
  @Test("A refresh publishes a complete snapshot")
  func refresh() async {
    let monitor = StubMonitor()
    let state = AppState(monitor: monitor)

    await state.refreshForTesting()

    #expect(state.snapshot?.fans.count == 2)
    #expect(state.snapshot?.primaryTemperature?.temperature == 60)
    #expect(state.lastSuccessfulUpdate != nil)
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
  }

  @Test("Sleep pauses polling and wake performs an immediate refresh")
  func sleepAndWake() async throws {
    let monitor = StubMonitor()
    let state = AppState(monitor: monitor)
    state.start()
    defer { state.stop() }

    NSWorkspace.shared.notificationCenter.post(
      name: NSWorkspace.willSleepNotification, object: nil)
    await Task.yield()
    #expect(state.isSleeping)

    // Let an already-scheduled initial poll settle before measuring wake behavior.
    try await Task.sleep(for: .milliseconds(20))
    let readsBeforeWake = monitor.readCount
    NSWorkspace.shared.notificationCenter.post(
      name: NSWorkspace.didWakeNotification, object: nil)

    for _ in 0..<50 {
      if !state.isSleeping, monitor.readCount > readsBeforeWake { break }
      try await Task.sleep(for: .milliseconds(10))
    }

    #expect(!state.isSleeping)
    #expect(monitor.readCount > readsBeforeWake)
  }

  @Test("Helper registration and ping state stay in AppState")
  func helperState() async throws {
    let installer = StubHelperInstaller()
    let helper = StubHelperClient(result: .success("0.7.2"))
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
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(state.helperVersion == "0.7.2")
    #expect(state.helperErrorMessage == nil)

    state.uninstallHelper()
    for _ in 0..<50 where installer.unregisterCount == 0 {
      try await Task.sleep(for: .milliseconds(10))
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
      result: .success("0.7.2"),
      automaticResult: .success(.init(
        isAutomatic: false, fanModes: [1, 0], forceTest: nil,
        message: "Fan 0 remained manual.")))
    let state = AppState(
      monitor: StubMonitor(), helperInstaller: installer, helperClient: helper)

    state.uninstallHelper()
    for _ in 0..<50 where state.isRestoringAutomaticControl {
      try await Task.sleep(for: .milliseconds(10))
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
      helperClient: StubHelperClient(result: .success("0.7.2"))
    )

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    state.setFanRPM(fanID: 0, rpm: 1_400)
    for _ in 0..<50 where state.fanControlStatuses[0] == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(state.fanControlStatuses[0]?.isManual == true)

    state.restoreAutomaticControl()
    for _ in 0..<50 where state.automaticControlStatus == nil {
      try await Task.sleep(for: .milliseconds(10))
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
    let client = StubHelperClient(result: .success("0.7.2"))
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: client
    )
    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(state.canControlFan(0))

    state.setFanRPM(fanID: 0, rpm: 1_400)
    for _ in 0..<50 where state.fanControlStatuses[0] == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(state.fanControlStatuses[0]?.isManual == true)
    #expect(state.fanControlStatuses[0]?.appliedRPM == 1_400)
    for _ in 0..<50 where client.renewalCount == 0 {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(client.renewalCount == 1)
    #expect(state.controlLeaseStatus?.isActive == true)

    state.setFanAutomatic(fanID: 0)
    for _ in 0..<50 where state.fanControlStatuses[0]?.isManual == true {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(state.fanControlStatuses[0]?.isManual == false)
    #expect(state.controlLeaseStatus == nil)

    state.setFanRPM(fanID: 0, rpm: 1_450)
    for _ in 0..<50 where client.renewalCount < 2 {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(client.renewalCount == 2)
    #expect(state.controlLeaseStatus?.isActive == true)
  }

  @Test("Balanced publishes dynamic targets and uses the safety heartbeat")
  func balancedState() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(result: .success("0.7.2"))
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: client)

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    state.applyBalancedPreset()
    for _ in 0..<50 where client.presetCount == 0 || client.renewalCount == 0 {
      try await Task.sleep(for: .milliseconds(10))
    }

    #expect(client.presetCount == 1)
    #expect(state.activeControlMode == .balanced)
    #expect(state.presetControlStatus?.targetRPMs == [2_800, 2_950])
    #expect(state.controlLeaseStatus?.isActive == true)

    state.restoreAutomaticControl()
    for _ in 0..<50 where state.activeControlMode != .automatic {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(state.presetControlStatus == nil)
    #expect(state.controlLeaseStatus == nil)
  }

  @Test("A failed Balanced request never renews an uncertain control state")
  func failedBalancedDoesNotHeartbeat() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(
      result: .success("0.7.2"),
      presetResult: .success(.init(
        success: false, targetRPMs: [2_800, 2_950], actualRPMs: [2_800, 0],
        didRestoreAutomatic: false, message: "Second fan failed.")))
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: client)

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    state.applyBalancedPreset()
    for _ in 0..<50 where state.presetControlStatus == nil {
      try await Task.sleep(for: .milliseconds(10))
    }

    #expect(state.activeControlMode == .automatic)
    #expect(client.renewalCount == 0)
    #expect(state.helperErrorMessage == "Second fan failed.")
  }

  @Test("Cool publishes its dynamic targets and uses the safety heartbeat")
  func coolState() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(result: .success("0.7.2"))
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: client)

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    state.applyCoolPreset()
    for _ in 0..<50 where client.coolPresetCount == 0 || client.renewalCount == 0 {
      try await Task.sleep(for: .milliseconds(10))
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
    let client = StubHelperClient(result: .success("0.7.2"))
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: client)

    await state.refreshForTesting()
    state.pingHelper()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    state.applyMaxPreset()
    for _ in 0..<50 where client.maxPresetCount == 0 || client.renewalCount == 0 {
      try await Task.sleep(for: .milliseconds(10))
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
      try await Task.sleep(for: .milliseconds(10))
    }

    #expect(state.helperVersion == "0.5.0")
    #expect(!state.canControlFan(0))
    state.setFanRPM(fanID: 0, rpm: 1_400)
    #expect(state.fanControlStatuses.isEmpty)
  }

  @Test("Sleep requests Automatic and wake never resumes Manual")
  func sleepSafety() async throws {
    let installer = StubHelperInstaller()
    installer.currentStatus = .enabled
    let client = StubHelperClient(result: .success("0.7.2"))
    let state = AppState(
      monitor: StubMonitor(controlVerified: true),
      helperInstaller: installer,
      helperClient: client)
    state.start()
    defer { state.stop() }
    await state.refreshForTesting()
    for _ in 0..<50 where state.helperVersion == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    state.setFanRPM(fanID: 0, rpm: 1_400)
    for _ in 0..<50 where state.fanControlStatuses[0]?.isManual != true {
      try await Task.sleep(for: .milliseconds(10))
    }

    NSWorkspace.shared.notificationCenter.post(
      name: NSWorkspace.willSleepNotification, object: nil)
    for _ in 0..<50 where client.restoreCount == 0 {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(client.restoreCount == 1)
    #expect(state.fanControlStatuses.isEmpty)

    NSWorkspace.shared.notificationCenter.post(
      name: NSWorkspace.didWakeNotification, object: nil)
    try await Task.sleep(for: .milliseconds(30))
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
      helperClient: StubHelperClient(result: .success("0.7.2")),
      terminateApp: { didTerminate = true }
    )

    state.quitBreeze()
    for _ in 0..<50 where !didTerminate {
      try await Task.sleep(for: .milliseconds(10))
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
        result: .success("0.7.2"), automaticResult: .success(failedStatus)),
      terminateApp: { didTerminate = true }
    )

    state.quitBreeze()
    for _ in 0..<50 where state.isRestoringAutomaticControl {
      try await Task.sleep(for: .milliseconds(10))
    }

    #expect(!didTerminate)
    #expect(state.automaticControlStatus == failedStatus)
    #expect(state.helperErrorMessage == "Fan 0 remained manual.")
  }
}
