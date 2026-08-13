import Testing

@testable import BreezeHelper

@Suite("Manual fan controller")
struct ManualFanControllerTests {
  private func hardware() -> TestAutomaticHardware {
    let hardware = TestAutomaticHardware()
    hardware.values.removeValue(forKey: .forceTest)
    return hardware
  }

  @Test("Requested RPM is clamped to detected minimum and maximum")
  func clampsBounds() {
    let lowHardware = hardware()
    let low = ManualFanController(hardware: lowHardware, pause: {}).setRPM(
      fanID: 0, requestedRPM: 10)
    #expect(low.success)
    #expect(low.appliedRPM == 1_200)
    #expect(lowHardware.targets[.fan0] == 1_200)

    let highHardware = hardware()
    let high = ManualFanController(hardware: highHardware, pause: {}).setRPM(
      fanID: 1, requestedRPM: 99_999)
    #expect(high.success)
    #expect(high.appliedRPM == 6_241)
    #expect(highHardware.targets[.fan1] == 6_241)
  }

  @Test("Manual mode settles before target write and verification")
  func safeWriteOrder() {
    let hardware = hardware()
    let report = ManualFanController(
      hardware: hardware,
      settleAfterManualMode: { hardware.events.append("settle") },
      pause: {}
    ).setRPM(
      fanID: 0, requestedRPM: 1_400)

    #expect(report.success)
    #expect(hardware.events.prefix(4) == ["manual:0", "settle", "worker:0:1400", "target:0:1400"])
    #expect(report.actualRPM == 1_400)
  }

  @Test("Mode readback failure after target write restores automatic control")
  func modeReadbackRollsBack() {
    let hardware = hardware()
    hardware.manualModeWriteSticks = false
    let report = ManualFanController(hardware: hardware, pause: {}).setRPM(
      fanID: 0, requestedRPM: 1_400)

    #expect(!report.success)
    #expect(report.didRestoreAutomatic)
    #expect(report.message.contains("observed mode 3, target 1400.0 RPM"))
    #expect(hardware.events.prefix(3) == ["manual:0", "worker:0:1400", "target:0:1400"])
    #expect(hardware.values[.fan0Mode] == 0)
  }

  @Test("Untrusted bounds disable manual mode without writes")
  func rejectsBounds() {
    let hardware = hardware()
    hardware.minimums[.fan0] = 0
    let report = ManualFanController(hardware: hardware, pause: {}).setRPM(
      fanID: 0, requestedRPM: 1_400)

    #expect(!report.success)
    #expect(hardware.events.isEmpty)
  }

  @Test("Unknown models and fan IDs are rejected without writes")
  func rejectsUnknownHardware() {
    let modelHardware = hardware()
    modelHardware.modelIdentifier = "Mac99,9"
    let modelReport = ManualFanController(hardware: modelHardware, pause: {}).setRPM(
      fanID: 0, requestedRPM: 1_400)
    #expect(!modelReport.success)
    #expect(modelHardware.events.isEmpty)

    let idHardware = hardware()
    let idReport = ManualFanController(hardware: idHardware, pause: {}).setRPM(
      fanID: 2, requestedRPM: 1_400)
    #expect(!idReport.success)
    #expect(idHardware.events.isEmpty)
  }

  @Test("Manual-mode failure immediately invokes automatic restore")
  func modeFailureRollsBack() {
    let hardware = hardware()
    hardware.manualModeWriteFails = true
    let report = ManualFanController(hardware: hardware, pause: {}).setRPM(
      fanID: 0, requestedRPM: 1_400)

    #expect(!report.success)
    #expect(report.didRestoreAutomatic)
    #expect(hardware.events == [
      "manual:0", "zero:F0Md", "zero:F1Md", "reset:0", "reset:1",
    ])
  }

  @Test("Target write failure immediately invokes automatic restore")
  func targetFailureRollsBack() {
    let hardware = hardware()
    hardware.targetWriteFails = true
    let report = ManualFanController(hardware: hardware, pause: {}).setRPM(
      fanID: 0, requestedRPM: 1_400)

    #expect(!report.success)
    #expect(report.didRestoreAutomatic)
    #expect(hardware.values[.fan0Mode] == 0)
    #expect(hardware.values[.fan1Mode] == 0)
  }

  @Test("Target readback mismatch restores automatic control")
  func targetVerificationRollsBack() {
    let hardware = hardware()
    hardware.targetReadbackOffset = 10
    let report = ManualFanController(hardware: hardware, pause: {}).setRPM(
      fanID: 0, requestedRPM: 1_400)

    #expect(!report.success)
    #expect(report.didRestoreAutomatic)
    #expect(hardware.values[.fan0Mode] == 0)
  }

  @Test("An ignored target is retried through a fresh fixed worker")
  func retriesIgnoredTarget() {
    let hardware = hardware()
    hardware.ignoredTargetWorkerWrites = 1
    let report = ManualFanController(
      hardware: hardware,
      settleAfterManualMode: {},
      pauseBeforeTargetRetry: {},
      pause: {}
    ).setRPM(fanID: 1, requestedRPM: 1_400)

    #expect(report.success)
    #expect(hardware.events.filter { $0 == "worker:1:1400" }.count == 2)
    #expect(hardware.targets[.fan1] == 1_400)
  }

  @Test("RPM convergence timeout restores automatic control")
  func convergenceRollsBack() {
    let hardware = hardware()
    hardware.followsTarget = false
    hardware.actuals[.fan0] = 4_000
    let report = ManualFanController(
      hardware: hardware, verificationAttempts: 2, pause: {}
    ).setRPM(fanID: 0, requestedRPM: 1_400)

    #expect(!report.success)
    #expect(report.didRestoreAutomatic)
    #expect(hardware.values[.fan0Mode] == 0)
  }

  @Test("Per-fan automatic control resets mode and target")
  func perFanAutomatic() {
    let hardware = hardware()
    hardware.values[.fan0Mode] = 1
    hardware.targets[.fan0] = 1_800
    let report = ManualFanController(hardware: hardware, pause: {}).setAutomatic(fanID: 0)

    #expect(report.success)
    #expect(!report.isManual)
    #expect(hardware.values[.fan0Mode] == 0)
    #expect(hardware.targets[.fan0] == 0)
    #expect(hardware.events == ["auto:0", "reset:0"])
  }

  @Test("Per-fan automatic waits for the asynchronous mode transition")
  func perFanAutomaticWaits() {
    let hardware = hardware()
    hardware.values[.fan0Mode] = 1
    hardware.targets[.fan0] = 1_400
    hardware.automaticModeReadbacksBeforeStick = 2
    var pauses = 0
    let report = ManualFanController(hardware: hardware, pause: { pauses += 1 })
      .setAutomatic(fanID: 0)

    #expect(report.success)
    #expect(pauses == 2)
    #expect(hardware.values[.fan0Mode] == 0)
    #expect(hardware.targets[.fan0] == 0)
  }
}
