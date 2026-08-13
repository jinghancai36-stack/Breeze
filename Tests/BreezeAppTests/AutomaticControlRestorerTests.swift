import Foundation
import Testing

@testable import BreezeHelper

final class TestAutomaticHardware: ManualFanHardware {
  var modelIdentifier = AutomaticControlRestorer.supportedModel
  var isPrivileged = true
  var reportedFanCount = 2
  var values: [AutomaticControlKey: UInt8] = [
    .fan0Mode: 3, .fan1Mode: 3, .forceTest: 0,
  ]
  var writes: [AutomaticControlKey] = []
  var failingWrites: Set<AutomaticControlKey> = []
  var minimums: [VerifiedFan: Float] = [.fan0: 1_200, .fan1: 1_200]
  var maximums: [VerifiedFan: Float] = [.fan0: 5_779, .fan1: 6_241]
  var actuals: [VerifiedFan: Float] = [.fan0: 1_400, .fan1: 1_400]
  var targets: [VerifiedFan: Float] = [.fan0: 0, .fan1: 0]
  var manualModeWriteFails = false
  var manualModeWriteSticks = true
  var automaticModeReadbacksBeforeStick = 0
  var targetWriteFails = false
  var ignoredTargetWorkerWrites = 0
  var targetReadbackOffset: Float = 0
  var followsTarget = true
  var events: [String] = []

  func fanCount() throws -> Int { reportedFanCount }

  func readByte(_ key: AutomaticControlKey) throws -> UInt8 {
    guard let value = values[key] else { throw AutomaticControlError.invalidKey(key.smcName) }
    return value
  }

  func readForceTest() throws -> UInt8? { values[.forceTest] }

  func writeZero(_ key: AutomaticControlKey) throws {
    writes.append(key)
    events.append("zero:\(key.smcName)")
    if failingWrites.contains(key) { throw AutomaticControlError.firmware(1) }
    values[key] = 0
  }

  func currentRPM(for fan: VerifiedFan) throws -> Float { actuals[fan]! }
  func minimumRPM(for fan: VerifiedFan) throws -> Float { minimums[fan]! }
  func maximumRPM(for fan: VerifiedFan) throws -> Float { maximums[fan]! }
  func targetRPM(for fan: VerifiedFan) throws -> Float { targets[fan]! + targetReadbackOffset }
  func mode(for fan: VerifiedFan) throws -> UInt8 {
    if automaticModeReadbacksBeforeStick > 0 {
      automaticModeReadbacksBeforeStick -= 1
      return 1
    }
    return values[fan == .fan0 ? .fan0Mode : .fan1Mode]!
  }
  func writeManualMode(for fan: VerifiedFan) throws {
    events.append("manual:\(fan.rawValue)")
    if manualModeWriteFails { throw AutomaticControlError.firmware(1) }
    if manualModeWriteSticks {
      values[fan == .fan0 ? .fan0Mode : .fan1Mode] = 1
    }
  }
  func writeAutomaticMode(for fan: VerifiedFan) throws {
    events.append("auto:\(fan.rawValue)")
    values[fan == .fan0 ? .fan0Mode : .fan1Mode] = 0
  }
  func writeTargetRPMInWorker(_ rpm: Float, for fan: VerifiedFan) throws {
    events.append("worker:\(fan.rawValue):\(Int(rpm))")
    if ignoredTargetWorkerWrites > 0 {
      ignoredTargetWorkerWrites -= 1
      return
    }
    try writeTargetRPM(rpm, for: fan)
  }
  func writeTargetRPM(_ rpm: Float, for fan: VerifiedFan) throws {
    events.append("target:\(fan.rawValue):\(Int(rpm))")
    if targetWriteFails { throw AutomaticControlError.firmware(1) }
    targets[fan] = rpm
    if followsTarget { actuals[fan] = rpm }
  }
  func resetTargetRPM(for fan: VerifiedFan) throws {
    events.append("reset:\(fan.rawValue)")
    targets[fan] = 0
  }
}

@Suite("Automatic control restorer")
struct AutomaticControlRestorerTests {
  @Test("Automatic state performs only the idempotent Ftst zero write")
  func idempotentRestore() {
    let hardware = TestAutomaticHardware()
    let report = AutomaticControlRestorer(hardware: hardware, pause: {}).restore()

    #expect(report.success)
    #expect(report.fanModes == [3, 3])
    #expect(report.forceTest == 0)
    #expect(hardware.writes == [.forceTest])
  }

  @Test("Manual fan modes return to zero before Ftst is released")
  func manualRestoreOrder() {
    let hardware = TestAutomaticHardware()
    hardware.values = [.fan0Mode: 1, .fan1Mode: 1, .forceTest: 1]
    let report = AutomaticControlRestorer(hardware: hardware, pause: {}).restore()

    #expect(report.success)
    #expect(report.fanModes == [0, 0])
    #expect(report.forceTest == 0)
    #expect(hardware.writes == [.fan0Mode, .fan1Mode, .forceTest])
  }

  @Test("A mode write failure still attempts the safe Ftst release")
  func partialFailure() {
    let hardware = TestAutomaticHardware()
    hardware.values = [.fan0Mode: 1, .fan1Mode: 1, .forceTest: 1]
    hardware.failingWrites = [.fan0Mode]
    let report = AutomaticControlRestorer(hardware: hardware, pause: {}).restore()

    #expect(!report.success)
    #expect(hardware.writes == [.fan0Mode, .fan1Mode, .forceTest])
  }

  @Test("Unknown hardware is rejected before any SMC write")
  func unknownHardware() {
    let hardware = TestAutomaticHardware()
    hardware.modelIdentifier = "Mac99,9"
    let report = AutomaticControlRestorer(hardware: hardware, pause: {}).restore()

    #expect(!report.success)
    #expect(hardware.writes.isEmpty)
  }

  @Test("Unexpected fan count is rejected before any SMC write")
  func fanCountMismatch() {
    let hardware = TestAutomaticHardware()
    hardware.reportedFanCount = 1
    let report = AutomaticControlRestorer(hardware: hardware, pause: {}).restore()

    #expect(!report.success)
    #expect(hardware.writes.isEmpty)
  }

  @Test("Unknown fan mode is rejected before any SMC write")
  func unknownMode() {
    let hardware = TestAutomaticHardware()
    hardware.values[.fan0Mode] = 2
    let report = AutomaticControlRestorer(hardware: hardware, pause: {}).restore()

    #expect(!report.success)
    #expect(hardware.writes.isEmpty)
  }


  @Test("M1 direct-mode firmware restores both mode keys when Ftst is absent")
  func directModeRestore() {
    let hardware = TestAutomaticHardware()
    hardware.values.removeValue(forKey: .forceTest)
    let report = AutomaticControlRestorer(hardware: hardware, pause: {}).restore()

    #expect(report.success)
    #expect(report.forceTest == nil)
    #expect(report.fanModes == [0, 0])
    #expect(hardware.writes == [.fan0Mode, .fan1Mode])
  }
}
