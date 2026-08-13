import Foundation
import OSLog
import ServiceManagement

#if canImport(BreezeIPC)
  import BreezeIPC
#endif

enum HelperRegistrationStatus: Equatable {
  case notRegistered
  case enabled
  case requiresApproval
  case notFound
}

protocol HelperInstalling {
  var status: HelperRegistrationStatus { get }
  func register() throws
  func unregister() throws
  func openSystemSettings()
}

struct SystemHelperInstaller: HelperInstalling {
  private var service: SMAppService {
    .daemon(plistName: BreezeHelperConstants.launchDaemonPlistName)
  }

  var status: HelperRegistrationStatus {
    switch service.status {
    case .notRegistered: .notRegistered
    case .enabled: .enabled
    case .requiresApproval: .requiresApproval
    case .notFound: .notFound
    @unknown default: .notFound
    }
  }

  func register() throws {
    try service.register()
  }

  func unregister() throws {
    try service.unregister()
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}

enum HelperConnectionError: LocalizedError, Equatable {
  case unavailable
  case rejected
  case timedOut
  case invalidVersion
  case invalidReport

  var errorDescription: String? {
    switch self {
    case .unavailable: "The Breeze helper is unavailable."
    case .rejected: "The Breeze helper rejected the connection."
    case .timedOut: "The Breeze helper did not respond in time."
    case .invalidVersion: "The Breeze helper returned an invalid version."
    case .invalidReport: "The Breeze helper returned an invalid automatic-control report."
    }
  }
}

protocol HelperProbing: Sendable {
  func probe(completion: @escaping @Sendable (Result<String, Error>) -> Void)
}

struct AutomaticControlStatus: Equatable, Sendable {
  let isAutomatic: Bool
  let fanModes: [Int]
  let forceTest: Int?
  let message: String

  var diagnosticDescription: String {
    let modes = fanModes.map(String.init).joined(separator: ",")
    return "\(message) modes=[\(modes)] Ftst=\(forceTest.map(String.init) ?? "n/a")"
  }
}

struct FanControlStatus: Equatable, Sendable {
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

  var diagnosticDescription: String {
    "\(message) fan=\(fanID) requested=\(requestedRPM) applied=\(appliedRPM) "
      + "actual=\(actualRPM) range=\(minimumRPM)...\(maximumRPM) "
      + "manual=\(isManual) restored=\(didRestoreAutomatic)"
  }
}

struct ControlLeaseStatus: Equatable, Sendable {
  let isActive: Bool
  let remainingSeconds: Int
  let message: String
}

struct PresetControlStatus: Equatable, Sendable {
  let success: Bool
  let targetRPMs: [Int]
  let actualRPMs: [Int]
  let didRestoreAutomatic: Bool
  let message: String
}

protocol AutomaticControlServicing: Sendable {
  func automaticControlStatus(
    completion: @escaping @Sendable (Result<AutomaticControlStatus, Error>) -> Void)
  func restoreAutomaticControl(
    completion: @escaping @Sendable (Result<AutomaticControlStatus, Error>) -> Void)
}

protocol ManualFanServicing: Sendable {
  func setFanRPM(
    fanID: Int, rpm: Int,
    completion: @escaping @Sendable (Result<FanControlStatus, Error>) -> Void)
  func setFanAutomatic(
    fanID: Int,
    completion: @escaping @Sendable (Result<FanControlStatus, Error>) -> Void)
}

protocol WatchdogServicing: Sendable {
  func renewControlLease(
    completion: @escaping @Sendable (Result<ControlLeaseStatus, Error>) -> Void)
  func controlLeaseStatus(
    completion: @escaping @Sendable (Result<ControlLeaseStatus, Error>) -> Void)
}

protocol PresetServicing: Sendable {
  func applyBalancedPreset(
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void)
  func applyCoolPreset(
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void)
}

protocol HelperCommunicating:
  HelperProbing, AutomaticControlServicing, ManualFanServicing, WatchdogServicing,
  PresetServicing {}

final class HelperClient: HelperCommunicating, @unchecked Sendable {
  private let connectionFactory: @Sendable () -> NSXPCConnection
  private let serverSigningRequirement: String?
  private let timeout: Duration
  private let manualTimeout: Duration
  private let presetTimeout: Duration
  private let logger = Logger(subsystem: "com.breeze.monitor", category: "XPC")

  init(
    timeout: Duration = .seconds(3),
    manualTimeout: Duration = .seconds(18),
    presetTimeout: Duration = .seconds(36)
  ) {
    self.timeout = timeout
    self.manualTimeout = manualTimeout
    self.presetTimeout = presetTimeout
    serverSigningRequirement = BreezeHelperConstants.peerSigningRequirement(
      identifier: BreezeHelperConstants.machServiceName)
    connectionFactory = {
      NSXPCConnection(
        machServiceName: BreezeHelperConstants.machServiceName,
        options: .privileged
      )
    }
  }

  init(
    endpoint: NSXPCListenerEndpoint,
    timeout: Duration = .seconds(3),
    manualTimeout: Duration = .seconds(18),
    presetTimeout: Duration = .seconds(36)
  ) {
    self.timeout = timeout
    self.manualTimeout = manualTimeout
    self.presetTimeout = presetTimeout
    serverSigningRequirement = nil
    connectionFactory = { NSXPCConnection(listenerEndpoint: endpoint) }
  }

  func setFanRPM(
    fanID: Int,
    rpm: Int,
    completion: @escaping @Sendable (Result<FanControlStatus, Error>) -> Void
  ) {
    performManualRequest(fanID: fanID, requestedRPM: rpm, automatic: false, completion: completion)
  }

  func setFanAutomatic(
    fanID: Int,
    completion: @escaping @Sendable (Result<FanControlStatus, Error>) -> Void
  ) {
    performManualRequest(fanID: fanID, requestedRPM: 0, automatic: true, completion: completion)
  }

  func applyBalancedPreset(
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    performPresetRequest(cool: false, completion: completion)
  }

  func applyCoolPreset(
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    performPresetRequest(cool: true, completion: completion)
  }

  private func performPresetRequest(
    cool: Bool,
    completion: @escaping @Sendable (Result<PresetControlStatus, Error>) -> Void
  ) {
    let connection = connectionFactory()
    let gate = HelperReplyGate(connection: connection, completion: completion)
    connection.remoteObjectInterface = NSXPCInterface(with: BreezeHelperProtocol.self)
    if let serverSigningRequirement { connection.setCodeSigningRequirement(serverSigningRequirement) }
    connection.interruptionHandler = { gate.finish(.failure(HelperConnectionError.unavailable)) }
    connection.invalidationHandler = { gate.finish(.failure(HelperConnectionError.unavailable)) }
    connection.resume()

    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler({ [logger] error in
        logger.error("Preset proxy error: \(error.localizedDescription, privacy: .public)")
        gate.finish(.failure(HelperConnectionError.rejected))
      }) as? BreezeHelperProtocol
    else {
      gate.finish(.failure(HelperConnectionError.unavailable))
      return
    }

    Task {
      try? await Task.sleep(for: presetTimeout)
      gate.finish(.failure(HelperConnectionError.timedOut))
    }
    let reply: (Bool, Int, Int, Int, Int, Bool, String) -> Void = {
      success, target0, target1, actual0, actual1, restored, message in
      guard !message.isEmpty,
        target0 >= 0, target1 >= 0, actual0 >= 0, actual1 >= 0
      else {
        gate.finish(.failure(HelperConnectionError.invalidReport))
        return
      }
      gate.finish(.success(.init(
        success: success,
        targetRPMs: [target0, target1],
        actualRPMs: [actual0, actual1],
        didRestoreAutomatic: restored,
        message: message
      )))
    }
    if cool {
      proxy.applyCoolPreset(withReply: reply)
    } else {
      proxy.applyBalancedPreset(withReply: reply)
    }
  }

  private func performManualRequest(
    fanID: Int,
    requestedRPM: Int,
    automatic: Bool,
    completion: @escaping @Sendable (Result<FanControlStatus, Error>) -> Void
  ) {
    let connection = connectionFactory()
    let gate = HelperReplyGate(connection: connection, completion: completion)
    connection.remoteObjectInterface = NSXPCInterface(with: BreezeHelperProtocol.self)
    if let serverSigningRequirement { connection.setCodeSigningRequirement(serverSigningRequirement) }
    connection.interruptionHandler = { gate.finish(.failure(HelperConnectionError.unavailable)) }
    connection.invalidationHandler = { gate.finish(.failure(HelperConnectionError.unavailable)) }
    connection.resume()

    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler({ [logger] error in
        logger.error("Helper proxy error: \(error.localizedDescription, privacy: .public)")
        gate.finish(.failure(HelperConnectionError.rejected))
      }) as? BreezeHelperProtocol
    else {
      gate.finish(.failure(HelperConnectionError.unavailable))
      return
    }

    Task {
      try? await Task.sleep(for: manualTimeout)
      gate.finish(.failure(HelperConnectionError.timedOut))
    }

    let reply: (Bool, Int, Int, Int, Int, Int, Bool, Bool, String) -> Void = {
      success, applied, actual, minimum, maximum, returnedFanID, isManual, restored, message in
      guard !message.isEmpty, returnedFanID == fanID else {
        gate.finish(.failure(HelperConnectionError.invalidReport))
        return
      }
      gate.finish(.success(FanControlStatus(
        success: success, fanID: returnedFanID, requestedRPM: requestedRPM,
        appliedRPM: applied, actualRPM: actual, minimumRPM: minimum, maximumRPM: maximum,
        isManual: isManual, didRestoreAutomatic: restored, message: message)))
    }
    if automatic {
      proxy.setFanAutomatic(fanID, withReply: reply)
    } else {
      proxy.setFanRPM(fanID, rpm: requestedRPM, withReply: reply)
    }
  }

  func probe(completion: @escaping @Sendable (Result<String, Error>) -> Void) {
    let connection = connectionFactory()
    let gate = HelperReplyGate(connection: connection, completion: completion)
    connection.remoteObjectInterface = NSXPCInterface(with: BreezeHelperProtocol.self)
    if let serverSigningRequirement {
      connection.setCodeSigningRequirement(serverSigningRequirement)
    }
    connection.interruptionHandler = { gate.finish(.failure(HelperConnectionError.unavailable)) }
    connection.invalidationHandler = { gate.finish(.failure(HelperConnectionError.unavailable)) }
    connection.resume()

    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler({ [logger] error in
        logger.error("Helper proxy error: \(error.localizedDescription, privacy: .public)")
        gate.finish(.failure(HelperConnectionError.rejected))
      }) as? BreezeHelperProtocol
    else {
      gate.finish(.failure(HelperConnectionError.unavailable))
      return
    }

    Task {
      try? await Task.sleep(for: timeout)
      gate.finish(.failure(HelperConnectionError.timedOut))
    }

    proxy.ping { alive in
      guard alive else {
        gate.finish(.failure(HelperConnectionError.rejected))
        return
      }
      proxy.getHelperVersion { version in
        guard !version.isEmpty else {
          gate.finish(.failure(HelperConnectionError.invalidVersion))
          return
        }
        gate.finish(.success(version))
      }
    }
  }

  func automaticControlStatus(
    completion: @escaping @Sendable (Result<AutomaticControlStatus, Error>) -> Void
  ) {
    performAutomaticControlRequest(restoring: false, completion: completion)
  }

  func restoreAutomaticControl(
    completion: @escaping @Sendable (Result<AutomaticControlStatus, Error>) -> Void
  ) {
    performAutomaticControlRequest(restoring: true, completion: completion)
  }

  func renewControlLease(
    completion: @escaping @Sendable (Result<ControlLeaseStatus, Error>) -> Void
  ) {
    performLeaseRequest(renewing: true, completion: completion)
  }

  func controlLeaseStatus(
    completion: @escaping @Sendable (Result<ControlLeaseStatus, Error>) -> Void
  ) {
    performLeaseRequest(renewing: false, completion: completion)
  }

  private func performLeaseRequest(
    renewing: Bool,
    completion: @escaping @Sendable (Result<ControlLeaseStatus, Error>) -> Void
  ) {
    let connection = connectionFactory()
    let gate = HelperReplyGate(connection: connection, completion: completion)
    connection.remoteObjectInterface = NSXPCInterface(with: BreezeHelperProtocol.self)
    if let serverSigningRequirement { connection.setCodeSigningRequirement(serverSigningRequirement) }
    connection.interruptionHandler = { gate.finish(.failure(HelperConnectionError.unavailable)) }
    connection.invalidationHandler = { gate.finish(.failure(HelperConnectionError.unavailable)) }
    connection.resume()

    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler({ [logger] error in
        logger.error("Watchdog proxy error: \(error.localizedDescription, privacy: .public)")
        gate.finish(.failure(HelperConnectionError.rejected))
      }) as? BreezeHelperProtocol
    else {
      gate.finish(.failure(HelperConnectionError.unavailable))
      return
    }

    Task {
      try? await Task.sleep(for: timeout)
      gate.finish(.failure(HelperConnectionError.timedOut))
    }
    let reply: (Bool, Int, String) -> Void = { active, remaining, message in
      guard !message.isEmpty, remaining >= 0 else {
        gate.finish(.failure(HelperConnectionError.invalidReport))
        return
      }
      gate.finish(.success(.init(
        isActive: active, remainingSeconds: remaining, message: message)))
    }
    if renewing {
      proxy.renewControlLease(withReply: reply)
    } else {
      proxy.getControlLeaseStatus(withReply: reply)
    }
  }

  private func performAutomaticControlRequest(
    restoring: Bool,
    completion: @escaping @Sendable (Result<AutomaticControlStatus, Error>) -> Void
  ) {
    let connection = connectionFactory()
    let gate = HelperReplyGate(connection: connection, completion: completion)
    connection.remoteObjectInterface = NSXPCInterface(with: BreezeHelperProtocol.self)
    if let serverSigningRequirement {
      connection.setCodeSigningRequirement(serverSigningRequirement)
    }
    connection.interruptionHandler = { gate.finish(.failure(HelperConnectionError.unavailable)) }
    connection.invalidationHandler = { gate.finish(.failure(HelperConnectionError.unavailable)) }
    connection.resume()

    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler({ [logger] error in
        logger.error("Helper proxy error: \(error.localizedDescription, privacy: .public)")
        gate.finish(.failure(HelperConnectionError.rejected))
      }) as? BreezeHelperProtocol
    else {
      gate.finish(.failure(HelperConnectionError.unavailable))
      return
    }

    Task {
      try? await Task.sleep(for: timeout)
      gate.finish(.failure(HelperConnectionError.timedOut))
    }

    let reply: (Bool, Int, Int, Int, String) -> Void = {
      success, fan0, fan1, forceTest, message in
      guard !message.isEmpty else {
        gate.finish(.failure(HelperConnectionError.invalidReport))
        return
      }
      let fanModes = [fan0, fan1].filter { $0 >= 0 }
      gate.finish(
        .success(
          AutomaticControlStatus(
            isAutomatic: success,
            fanModes: fanModes,
            forceTest: forceTest >= 0 ? forceTest : nil,
            message: message
          )))
    }
    if restoring {
      proxy.restoreAutomaticControl(withReply: reply)
    } else {
      proxy.getAutomaticControlStatus(withReply: reply)
    }
  }
}

private final class HelperReplyGate<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var finished = false
  private let connection: NSXPCConnection
  private let completion: @Sendable (Result<Value, Error>) -> Void

  init(
    connection: NSXPCConnection,
    completion: @escaping @Sendable (Result<Value, Error>) -> Void
  ) {
    self.connection = connection
    self.completion = completion
  }

  func finish(_ result: Result<Value, Error>) {
    let shouldFinish = lock.withLock {
      guard !finished else { return false }
      finished = true
      return true
    }
    guard shouldFinish else { return }
    completion(result)
    connection.invalidate()
  }
}
