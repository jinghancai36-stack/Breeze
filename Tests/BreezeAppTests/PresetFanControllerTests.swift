import Testing

@testable import BreezeHelper

@Suite("Fan presets")
struct PresetFanControllerTests {
  @Test("Balanced targets are calculated independently from each fan range")
  func dynamicTargets() throws {
    #expect(try FanPresetPolicy.targetRPM(
      for: .balanced, minimum: 1_200, maximum: 5_779) == 2_800)
    #expect(try FanPresetPolicy.targetRPM(
      for: .balanced, minimum: 1_200, maximum: 6_241) == 2_950)
  }

  @Test("Untrusted preset bounds are rejected")
  func rejectsBounds() {
    #expect(throws: ManualFanError.self) {
      try FanPresetPolicy.targetRPM(for: .balanced, minimum: 0, maximum: 6_000)
    }
    #expect(throws: ManualFanError.self) {
      try FanPresetPolicy.targetRPM(for: .balanced, minimum: 1_200, maximum: 9_000)
    }
  }

  @Test("Balanced preflights both fans before the first write")
  func preflightsBothFans() {
    let hardware = makeHardware()
    hardware.maximums[.fan1] = 9_000

    let report = makeController(hardware).apply(.balanced)

    #expect(!report.success)
    #expect(hardware.events.isEmpty)
    #expect(hardware.values[.fan0Mode] == 3)
    #expect(hardware.values[.fan1Mode] == 3)
  }

  @Test("Balanced applies and verifies a dynamic target for both fans")
  func appliesBothFans() {
    let hardware = makeHardware()

    let report = makeController(hardware).apply(.balanced)

    #expect(report.success)
    #expect(report.targetRPMs == [2_800, 2_950])
    #expect(report.actualRPMs == [2_800, 2_950])
    #expect(hardware.targets[.fan0] == 2_800)
    #expect(hardware.targets[.fan1] == 2_950)
    #expect(hardware.values[.fan0Mode] == 1)
    #expect(hardware.values[.fan1Mode] == 1)
  }

  @Test("A second-fan preset failure restores every fan")
  func secondFanFailureRollsBack() {
    let hardware = makeHardware()
    hardware.targetWriteFailingFans = [.fan1]

    let report = makeController(hardware).apply(.balanced)

    #expect(!report.success)
    #expect(report.didRestoreAutomatic)
    #expect(hardware.values[.fan0Mode] == 0)
    #expect(hardware.values[.fan1Mode] == 0)
    #expect(hardware.targets[.fan0] == 0)
    #expect(hardware.targets[.fan1] == 0)
  }

  private func makeHardware() -> TestAutomaticHardware {
    let hardware = TestAutomaticHardware()
    hardware.values.removeValue(forKey: .forceTest)
    return hardware
  }

  private func makeController(_ hardware: TestAutomaticHardware) -> PresetFanController {
    PresetFanController(
      hardware: hardware,
      makeManualController: {
        ManualFanController(
          hardware: hardware,
          settleAfterManualMode: {},
          pauseBeforeTargetRetry: {},
          pause: {}
        )
      }
    )
  }
}
