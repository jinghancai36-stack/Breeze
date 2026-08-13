import Darwin
import Foundation

enum AutomaticControlKey: Hashable, Sendable {
  case fan0Mode
  case fan1Mode
  case forceTest

  var smcName: String {
    switch self {
    case .fan0Mode: "F0Md"
    case .fan1Mode: "F1Md"
    case .forceTest: "Ftst"
    }
  }
}

struct AutomaticControlReport: Equatable, Sendable {
  let success: Bool
  let fanModes: [UInt8]
  let forceTest: UInt8?
  let message: String
  let shouldRetryAfterFailure: Bool

  init(
    success: Bool,
    fanModes: [UInt8],
    forceTest: UInt8?,
    message: String,
    shouldRetryAfterFailure: Bool = true
  ) {
    self.success = success
    self.fanModes = fanModes
    self.forceTest = forceTest
    self.message = message
    self.shouldRetryAfterFailure = shouldRetryAfterFailure
  }
}

protocol AutomaticControlHardware: AnyObject {
  var modelIdentifier: String { get }
  var isPrivileged: Bool { get }
  func fanCount() throws -> Int
  func readByte(_ key: AutomaticControlKey) throws -> UInt8
  func readForceTest() throws -> UInt8?
  func writeZero(_ key: AutomaticControlKey) throws
  func resetTargetRPM(for fan: VerifiedFan) throws
}

final class AutomaticControlRestorer {
  static let supportedModel = "MacBookPro18,3"
  static let supportedFanCount = 2
  private static let fanModeKeys: [AutomaticControlKey] = [.fan0Mode, .fan1Mode]

  private let hardware: any AutomaticControlHardware
  private let verificationAttempts: Int
  private let pause: () -> Void

  init(
    hardware: any AutomaticControlHardware,
    verificationAttempts: Int = 20,
    pause: @escaping () -> Void = { Thread.sleep(forTimeInterval: 0.1) }
  ) {
    self.hardware = hardware
    self.verificationAttempts = max(1, verificationAttempts)
    self.pause = pause
  }

  func status() -> AutomaticControlReport {
    do {
      try validateHardware()
      let state = try readState()
      return AutomaticControlReport(
        success: isAutomatic(state),
        fanModes: state.fanModes,
        forceTest: state.forceTest,
        message: isAutomatic(state)
          ? "Apple automatic control is active."
          : "Fan control is not fully automatic."
      )
    } catch {
      return failure(error)
    }
  }

  func restore() -> AutomaticControlReport {
    do {
      try validateHardware()
      let initial = try readState()
      guard initial.fanModes.allSatisfy({ $0 == 0 || $0 == 1 || $0 == 3 }) else {
        throw AutomaticControlError.unknownFanMode(initial.fanModes)
      }

      var writeErrors: [String] = []
      let modeIndicesToRestore: [Int]
      if initial.forceTest == nil {
        // M1-family firmware uses the direct per-fan mode path. Writing zero is
        // the documented automatic-control operation, including from mode 3.
        modeIndicesToRestore = Array(initial.fanModes.indices)
      } else {
        modeIndicesToRestore = initial.fanModes.indices.filter { initial.fanModes[$0] == 1 }
      }
      for index in modeIndicesToRestore {
        do {
          try hardware.writeZero(Self.fanModeKeys[index])
        } catch {
          writeErrors.append("F\(index)Md: \(error.localizedDescription)")
        }
      }

      for fan in VerifiedFan.allCases {
        do {
          try hardware.resetTargetRPM(for: fan)
        } catch {
          writeErrors.append("F\(fan.rawValue)Tg: \(error.localizedDescription)")
        }
      }

      if initial.forceTest != nil {
        // This idempotent write asks Apple's thermal daemon to reclaim control
        // on firmware generations that expose the force-test latch.
        do {
          try hardware.writeZero(.forceTest)
        } catch {
          writeErrors.append("Ftst: \(error.localizedDescription)")
        }
      }

      guard writeErrors.isEmpty else {
        let observed = (try? readState()) ?? initial
        return AutomaticControlReport(
          success: false,
          fanModes: observed.fanModes,
          forceTest: observed.forceTest,
          message: "Automatic restore write failed: \(writeErrors.joined(separator: "; "))"
        )
      }

      var observed = try readState()
      for attempt in 0..<verificationAttempts {
        if isAutomatic(observed) {
          return AutomaticControlReport(
            success: true,
            fanModes: observed.fanModes,
            forceTest: observed.forceTest,
            message: "Apple automatic control restored and verified."
          )
        }
        if attempt + 1 < verificationAttempts {
          pause()
          observed = try readState()
        }
      }
      return AutomaticControlReport(
        success: false,
        fanModes: observed.fanModes,
        forceTest: observed.forceTest,
        message: "Restore command completed, but automatic state was not verified."
      )
    } catch {
      return failure(error)
    }
  }

  private func validateHardware() throws {
    guard hardware.isPrivileged else { throw AutomaticControlError.notPrivileged }
    guard hardware.modelIdentifier == Self.supportedModel else {
      throw AutomaticControlError.unsupportedModel(hardware.modelIdentifier)
    }
    let count = try hardware.fanCount()
    guard count == Self.supportedFanCount else {
      throw AutomaticControlError.unexpectedFanCount(count)
    }
  }

  private func readState() throws -> (fanModes: [UInt8], forceTest: UInt8?) {
    let modes = try Self.fanModeKeys.map { key in
      try read(key)
    }
    do {
      return (modes, try hardware.readForceTest())
    } catch {
      throw AutomaticControlError.keyOperation("Ftst", error.localizedDescription)
    }
  }

  private func read(_ key: AutomaticControlKey) throws -> UInt8 {
    do {
      return try hardware.readByte(key)
    } catch {
      throw AutomaticControlError.keyOperation(key.smcName, error.localizedDescription)
    }
  }

  private func isAutomatic(_ state: (fanModes: [UInt8], forceTest: UInt8?)) -> Bool {
    (state.forceTest == nil || state.forceTest == 0)
      && state.fanModes.allSatisfy { $0 == 0 || $0 == 3 }
  }

  private func failure(_ error: Error) -> AutomaticControlReport {
    let isUnsupportedConfiguration: Bool
    switch error as? AutomaticControlError {
    case .unsupportedModel, .unexpectedFanCount:
      isUnsupportedConfiguration = true
    default:
      isUnsupportedConfiguration = false
    }
    return AutomaticControlReport(
      success: false,
      fanModes: [],
      forceTest: nil,
      message: error.localizedDescription,
      shouldRetryAfterFailure: !isUnsupportedConfiguration
    )
  }
}

enum AutomaticControlError: LocalizedError, Equatable {
  case notPrivileged
  case unsupportedModel(String)
  case unexpectedFanCount(Int)
  case unknownFanMode([UInt8])
  case appleSMCUnavailable
  case invalidKey(String)
  case invalidValue(String)
  case ioKit(kern_return_t)
  case firmware(UInt8)
  case keyOperation(String, String)

  var errorDescription: String? {
    switch self {
    case .notPrivileged:
      "Automatic restoration is available only in the root helper."
    case .unsupportedModel(let model):
      "SMC writes are not verified for \(model); no write was attempted."
    case .unexpectedFanCount(let count):
      "Expected two fans on the verified model, found \(count); no write was attempted."
    case .unknownFanMode(let modes):
      "Unknown fan mode values \(modes); no write was attempted."
    case .appleSMCUnavailable:
      "AppleSMC is unavailable."
    case .invalidKey(let key):
      "Invalid SMC key \(key)."
    case .invalidValue(let key):
      "Unexpected SMC value for \(key)."
    case .ioKit(let code):
      "AppleSMC I/O failed (\(code))."
    case .firmware(let code):
      "AppleSMC rejected the operation (\(code))."
    case .keyOperation(let key, let detail):
      "SMC key \(key) failed: \(detail)"
    }
  }
}
