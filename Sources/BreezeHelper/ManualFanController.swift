import Foundation

enum VerifiedFan: Int, CaseIterable, Sendable {
  case fan0 = 0
  case fan1 = 1
}

protocol ManualFanHardware: AutomaticControlHardware {
  func currentRPM(for fan: VerifiedFan) throws -> Float
  func minimumRPM(for fan: VerifiedFan) throws -> Float
  func maximumRPM(for fan: VerifiedFan) throws -> Float
  func targetRPM(for fan: VerifiedFan) throws -> Float
  func mode(for fan: VerifiedFan) throws -> UInt8
  func writeManualMode(for fan: VerifiedFan) throws
  func writeAutomaticMode(for fan: VerifiedFan) throws
  func writeTargetRPM(_ rpm: Float, for fan: VerifiedFan) throws
  func writeTargetRPMInWorker(_ rpm: Float, for fan: VerifiedFan) throws
}

struct ManualFanReport: Equatable, Sendable {
  let success: Bool
  let fanID: Int
  let requestedRPM: Int
  let appliedRPM: Int
  let actualRPM: Int
  let minimumRPM: Int
  let maximumRPM: Int
  let isManual: Bool
  let didRestoreAutomatic: Bool
  let message: String
}

final class ManualFanController {
  private let hardware: any ManualFanHardware
  private let verificationAttempts: Int
  private let targetWriteAttempts: Int
  private let settleAfterManualMode: () -> Void
  private let pauseBeforeTargetRetry: () -> Void
  private let pause: () -> Void

  init(
    hardware: any ManualFanHardware,
    verificationAttempts: Int = 30,
    targetWriteAttempts: Int = 3,
    settleAfterManualMode: @escaping () -> Void = {
      Thread.sleep(forTimeInterval: 0.35)
    },
    pauseBeforeTargetRetry: @escaping () -> Void = {
      Thread.sleep(forTimeInterval: 0.2)
    },
    pause: @escaping () -> Void = { Thread.sleep(forTimeInterval: 0.5) }
  ) {
    self.hardware = hardware
    self.verificationAttempts = max(1, verificationAttempts)
    self.targetWriteAttempts = max(1, targetWriteAttempts)
    self.settleAfterManualMode = settleAfterManualMode
    self.pauseBeforeTargetRetry = pauseBeforeTargetRetry
    self.pause = pause
  }

  func setRPM(fanID: Int, requestedRPM: Int) -> ManualFanReport {
    guard let fan = VerifiedFan(rawValue: fanID) else {
      return failure(
        fanID: fanID, requested: requestedRPM,
        error: ManualFanError.invalidFan(fanID), restored: false)
    }

    var bounds: (minimum: Float, maximum: Float)?
    var touchedControl = false
    do {
      try validateHardware()
      bounds = try validatedBounds(for: fan)
      let applied = Float(requestedRPM).clamped(to: bounds!.minimum...bounds!.maximum)
      let initialMode = try hardware.mode(for: fan)
      guard initialMode == 0 || initialMode == 1 || initialMode == 3 else {
        throw ManualFanError.unknownMode(initialMode)
      }

      if initialMode != 1 {
        touchedControl = true
        try hardware.writeManualMode(for: fan)
        // On the verified M1 path the mode transition is asynchronous. Stats
        // allows roughly 300 ms before its separate target write; an immediate
        // target write can be overwritten by the still-active automatic loop.
        settleAfterManualMode()
      }

      touchedControl = true
      // AppleSMC associates this M1 control transition with the task, not only
      // its IOKit connection. A fixed, same-signed root worker provides the
      // process boundary used by the verified Stats implementation.
      var storedTarget: Float = 0
      for attempt in 0..<targetWriteAttempts {
        try hardware.writeTargetRPMInWorker(applied, for: fan)
        let observedMode = try hardware.mode(for: fan)
        storedTarget = try hardware.targetRPM(for: fan)
        guard observedMode == 1 else {
          throw ManualFanError.manualModeNotVerified(
            observedMode: observedMode,
            observedTarget: storedTarget
          )
        }
        if abs(storedTarget - applied) <= 1 { break }
        if attempt + 1 < targetWriteAttempts { pauseBeforeTargetRetry() }
      }
      guard abs(storedTarget - applied) <= 1 else {
        throw ManualFanError.targetNotVerified(expected: applied, observed: storedTarget)
      }

      var actual = try hardware.currentRPM(for: fan)
      for attempt in 0..<verificationAttempts {
        if isConverged(actual: actual, target: applied) {
          return ManualFanReport(
            success: true,
            fanID: fan.rawValue,
            requestedRPM: requestedRPM,
            appliedRPM: Int(applied.rounded()),
            actualRPM: Int(actual.rounded()),
            minimumRPM: Int(bounds!.minimum.rounded()),
            maximumRPM: Int(bounds!.maximum.rounded()),
            isManual: true,
            didRestoreAutomatic: false,
            message: requestedRPM == Int(applied.rounded())
              ? "Manual fan target reached and verified."
              : "Requested RPM was clamped to the verified hardware range and reached."
          )
        }
        if attempt + 1 < verificationAttempts {
          pause()
          actual = try hardware.currentRPM(for: fan)
        }
      }
      throw ManualFanError.rpmNotReached(expected: applied, observed: actual)
    } catch {
      let restored = touchedControl ? restoreAll() : false
      return failure(
        fanID: fanID,
        requested: requestedRPM,
        bounds: bounds,
        error: error,
        restored: restored
      )
    }
  }

  func setAutomatic(fanID: Int) -> ManualFanReport {
    guard let fan = VerifiedFan(rawValue: fanID) else {
      return failure(fanID: fanID, requested: 0, error: ManualFanError.invalidFan(fanID), restored: false)
    }
    var bounds: (minimum: Float, maximum: Float)?
    do {
      try validateHardware()
      bounds = try validatedBounds(for: fan)
      try hardware.writeAutomaticMode(for: fan)
      try hardware.resetTargetRPM(for: fan)
      var mode = try hardware.mode(for: fan)
      for attempt in 0..<min(verificationAttempts, 10) {
        if mode == 0 || mode == 3 { break }
        if attempt + 1 < min(verificationAttempts, 10) {
          pause()
          mode = try hardware.mode(for: fan)
        }
      }
      guard mode == 0 || mode == 3 else {
        throw ManualFanError.automaticModeNotVerified(mode)
      }
      let actual = try hardware.currentRPM(for: fan)
      return ManualFanReport(
        success: true,
        fanID: fan.rawValue,
        requestedRPM: 0,
        appliedRPM: 0,
        actualRPM: Int(actual.rounded()),
        minimumRPM: Int(bounds!.minimum.rounded()),
        maximumRPM: Int(bounds!.maximum.rounded()),
        isManual: false,
        didRestoreAutomatic: false,
        message: "Fan returned to Apple automatic control."
      )
    } catch {
      return failure(
        fanID: fanID, requested: 0, bounds: bounds, error: error, restored: restoreAll())
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
    // The direct M1 control path is the only manual strategy verified by Breeze.
    guard try hardware.readForceTest() == nil else {
      throw ManualFanError.unsupportedControlStrategy
    }
  }

  private func validatedBounds(for fan: VerifiedFan) throws -> (minimum: Float, maximum: Float) {
    let minimum = try hardware.minimumRPM(for: fan)
    let maximum = try hardware.maximumRPM(for: fan)
    guard minimum.isFinite, maximum.isFinite, minimum >= 1_000, maximum <= 7_000,
      minimum < maximum
    else {
      throw ManualFanError.untrustedBounds(minimum: minimum, maximum: maximum)
    }
    return (minimum, maximum)
  }

  private func isConverged(actual: Float, target: Float) -> Bool {
    guard actual.isFinite else { return false }
    return abs(actual - target) <= max(150, target * 0.12)
  }

  private func restoreAll() -> Bool {
    AutomaticControlRestorer(hardware: hardware, pause: pause).restore().success
  }

  private func failure(
    fanID: Int,
    requested: Int,
    bounds: (minimum: Float, maximum: Float)? = nil,
    error: Error,
    restored: Bool
  ) -> ManualFanReport {
    ManualFanReport(
      success: false,
      fanID: fanID,
      requestedRPM: requested,
      appliedRPM: 0,
      actualRPM: 0,
      minimumRPM: bounds.map { Int($0.minimum.rounded()) } ?? 0,
      maximumRPM: bounds.map { Int($0.maximum.rounded()) } ?? 0,
      isManual: false,
      didRestoreAutomatic: restored,
      message: error.localizedDescription
        + (restored ? " Apple automatic control was restored." : "")
    )
  }
}

enum ManualFanError: LocalizedError, Equatable {
  case invalidFan(Int)
  case unsupportedControlStrategy
  case untrustedBounds(minimum: Float, maximum: Float)
  case unknownMode(UInt8)
  case manualModeNotVerified(observedMode: UInt8, observedTarget: Float)
  case automaticModeNotVerified(UInt8)
  case targetNotVerified(expected: Float, observed: Float)
  case rpmNotReached(expected: Float, observed: Float)
  case workerFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidFan(let id):
      "Fan \(id) is not in the verified two-fan whitelist."
    case .unsupportedControlStrategy:
      "This firmware does not match the verified M1 direct-control strategy."
    case .untrustedBounds(let minimum, let maximum):
      "Fan bounds are not safe for manual control (min \(minimum), max \(maximum))."
    case .unknownMode(let mode):
      "Unknown fan mode \(mode); manual control was not attempted."
    case .manualModeNotVerified(let mode, let target):
      "Manual mode could not be verified (observed mode \(mode), target \(target) RPM)."
    case .automaticModeNotVerified(let mode):
      "Automatic mode could not be verified (mode \(mode))."
    case .targetNotVerified(let expected, let observed):
      "Target RPM write was not verified (expected \(expected), observed \(observed))."
    case .rpmNotReached(let expected, let observed):
      "Fan did not reach the requested RPM (expected \(expected), observed \(observed))."
    case .workerFailed(let detail):
      "The fixed target worker failed (\(detail))."
    }
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
