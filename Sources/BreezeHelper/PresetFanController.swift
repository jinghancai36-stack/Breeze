import Foundation

enum FanPreset: String, Equatable, Sendable {
  case balanced

  var rangeFraction: Float {
    switch self {
    case .balanced: 0.35
    }
  }
}

enum FanPresetPolicy {
  static let rpmStep: Float = 50

  static func targetRPM(
    for preset: FanPreset,
    minimum: Float,
    maximum: Float
  ) throws -> Int {
    guard minimum.isFinite, maximum.isFinite,
      minimum >= 1_000, maximum <= 7_000, minimum < maximum
    else {
      throw ManualFanError.untrustedBounds(minimum: minimum, maximum: maximum)
    }
    let rawTarget = minimum + ((maximum - minimum) * preset.rangeFraction)
    let stepped = (rawTarget / rpmStep).rounded() * rpmStep
    return Int(min(max(stepped, minimum), maximum).rounded())
  }
}

struct PresetFanReport: Equatable, Sendable {
  let success: Bool
  let preset: FanPreset
  let targetRPMs: [Int]
  let actualRPMs: [Int]
  let didRestoreAutomatic: Bool
  let message: String
}

/// Applies a fixed preset as one privileged transaction. Both fan bounds are
/// preflighted before the first write. Any failure restores every fan.
final class PresetFanController {
  private let hardware: any ManualFanHardware
  private let makeManualController: () -> ManualFanController

  init(
    hardware: any ManualFanHardware,
    makeManualController: (() -> ManualFanController)? = nil
  ) {
    self.hardware = hardware
    self.makeManualController = makeManualController ?? {
      ManualFanController(hardware: hardware)
    }
  }

  func apply(_ preset: FanPreset) -> PresetFanReport {
    do {
      try validateHardware()
      let targets = try VerifiedFan.allCases.map { fan in
        try FanPresetPolicy.targetRPM(
          for: preset,
          minimum: hardware.minimumRPM(for: fan),
          maximum: hardware.maximumRPM(for: fan)
        )
      }

      var actuals: [Int] = []
      for fan in VerifiedFan.allCases {
        let report = makeManualController().setRPM(
          fanID: fan.rawValue,
          requestedRPM: targets[fan.rawValue]
        )
        guard report.success, report.isManual else {
          let restored = report.didRestoreAutomatic || restoreAll()
          return PresetFanReport(
            success: false,
            preset: preset,
            targetRPMs: targets,
            actualRPMs: actuals,
            didRestoreAutomatic: restored,
            message: "Balanced preset failed on Fan \(fan.rawValue + 1): \(report.message)"
              + (restored ? " Apple automatic control was restored." : "")
          )
        }
        actuals.append(report.actualRPM)
      }

      return PresetFanReport(
        success: true,
        preset: preset,
        targetRPMs: targets,
        actualRPMs: actuals,
        didRestoreAutomatic: false,
        message: "Balanced preset reached and verified on both fans."
      )
    } catch {
      return PresetFanReport(
        success: false,
        preset: preset,
        targetRPMs: [],
        actualRPMs: [],
        didRestoreAutomatic: false,
        message: error.localizedDescription
      )
    }
  }

  private func validateHardware() throws {
    guard hardware.isPrivileged else { throw AutomaticControlError.notPrivileged }
    guard hardware.modelIdentifier == AutomaticControlRestorer.supportedModel else {
      throw AutomaticControlError.unsupportedModel(hardware.modelIdentifier)
    }
    let count = try hardware.fanCount()
    guard count == AutomaticControlRestorer.supportedFanCount else {
      throw AutomaticControlError.unexpectedFanCount(count)
    }
    guard try hardware.readForceTest() == nil else {
      throw ManualFanError.unsupportedControlStrategy
    }
  }

  private func restoreAll() -> Bool {
    AutomaticControlRestorer(hardware: hardware).restore().success
  }
}
