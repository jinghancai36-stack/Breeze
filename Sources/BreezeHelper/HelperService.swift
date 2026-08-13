import Foundation
import OSLog
import Darwin

#if canImport(BreezeIPC)
  import BreezeIPC
#endif

final class HelperService: NSObject, BreezeHelperProtocol {
  private let logger = Logger(subsystem: "com.breeze.monitor", category: "Helper")
  private let restorerFactory: () throws -> AutomaticControlRestorer
  private let manualControllerFactory: () throws -> ManualFanController
  private let presetControllerFactory: () throws -> PresetFanController
  private let operationGate: ControlOperationGate
  private let watchdog: ControlLeaseWatchdog

  override convenience init() {
    self.init(
      restorerFactory: { AutomaticControlRestorer(hardware: try SMCRestoreConnection()) },
      manualControllerFactory: { ManualFanController(hardware: try SMCRestoreConnection()) },
      presetControllerFactory: { PresetFanController(hardware: try SMCRestoreConnection()) }
    )
  }

  init(
    restorerFactory: @escaping () throws -> AutomaticControlRestorer,
    manualControllerFactory: @escaping () throws -> ManualFanController = {
      ManualFanController(hardware: try SMCRestoreConnection())
    },
    presetControllerFactory: @escaping () throws -> PresetFanController = {
      PresetFanController(hardware: try SMCRestoreConnection())
    },
    operationGate: ControlOperationGate = ControlOperationGate(),
    watchdog: ControlLeaseWatchdog? = nil
  ) {
    self.restorerFactory = restorerFactory
    self.manualControllerFactory = manualControllerFactory
    self.presetControllerFactory = presetControllerFactory
    self.operationGate = operationGate
    self.watchdog = watchdog ?? ControlLeaseWatchdog(operationGate: operationGate, restore: {
      do {
        return try restorerFactory().restore()
      } catch {
        return AutomaticControlReport(
          success: false, fanModes: [], forceTest: nil, message: error.localizedDescription)
      }
    })
    super.init()
  }

  @discardableResult
  func recoverOnStartup() -> AutomaticControlReport {
    watchdog.recoverOnStartup()
  }

  var controlWatchdog: ControlLeaseWatchdog { watchdog }

  @discardableResult
  func restoreBeforeTermination() -> AutomaticControlReport {
    watchdog.restoreForSystemEvent("Helper termination recovery")
  }

  func setFanRPM(
    _ fanID: Int,
    rpm: Int,
    withReply reply: @escaping (Bool, Int, Int, Int, Int, Int, Bool, Bool, String) -> Void
  ) {
    let report = operationGate.perform {
      let report = makeManualReport(fanID: fanID, rpm: rpm, automatic: false)
      if report.success {
        watchdog.arm(reason: "Manual fan \(fanID) verified; awaiting heartbeat.")
        logger.info(
          "Manual fan verified: fan=\(report.fanID, privacy: .public) requested=\(report.requestedRPM, privacy: .public) applied=\(report.appliedRPM, privacy: .public) actual=\(report.actualRPM, privacy: .public)"
        )
      } else {
        if report.didRestoreAutomatic {
          watchdog.disarm(reason: "Failed manual request rolled back to Apple automatic control.")
        } else {
          watchdog.arm(reason: "Manual request failed without verified rollback; recovery armed.")
        }
        logger.error("Manual fan request failed: \(report.message, privacy: .public)")
      }
      return report
    }
    send(report, to: reply)
  }

  func setFanAutomatic(
    _ fanID: Int,
    withReply reply: @escaping (Bool, Int, Int, Int, Int, Int, Bool, Bool, String) -> Void
  ) {
    let report = operationGate.perform {
      let report = makeManualReport(fanID: fanID, rpm: 0, automatic: true)
      if makeReport(restoring: false).success {
        watchdog.disarm(reason: "All fans are under Apple automatic control.")
      }
      return report
    }
    send(report, to: reply)
  }

  func ping(withReply reply: @escaping (Bool) -> Void) {
    logger.debug("Received authenticated ping")
    reply(true)
  }

  func getHelperVersion(withReply reply: @escaping (String) -> Void) {
    reply(BreezeHelperConstants.helperVersion)
  }

  func getAutomaticControlStatus(
    withReply reply: @escaping (Bool, Int, Int, Int, String) -> Void
  ) {
    send(operationGate.perform { makeReport(restoring: false) }, to: reply)
  }

  func restoreAutomaticControl(
    withReply reply: @escaping (Bool, Int, Int, Int, String) -> Void
  ) {
    let report = operationGate.perform {
      let report = makeReport(restoring: true)
      if report.success {
        watchdog.disarm()
        logger.info(
          "Automatic control restored: modes=\(report.fanModes.description, privacy: .public) Ftst=\(report.forceTest.map(String.init) ?? "nil", privacy: .public)"
        )
      } else {
        watchdog.arm(reason: "Explicit automatic restore failed; watchdog retry armed.")
        logger.error("Automatic restore failed: \(report.message, privacy: .public)")
      }
      return report
    }
    send(report, to: reply)
  }

  func applyBalancedPreset(
    withReply reply: @escaping (Bool, Int, Int, Int, Int, Bool, String) -> Void
  ) {
    applyPreset(.balanced, reply: reply)
  }

  func applyCoolPreset(
    withReply reply: @escaping (Bool, Int, Int, Int, Int, Bool, String) -> Void
  ) {
    applyPreset(.cool, reply: reply)
  }

  func applyMaxPreset(
    withReply reply: @escaping (Bool, Int, Int, Int, Int, Bool, String) -> Void
  ) {
    applyPreset(.max, reply: reply)
  }

  private func applyPreset(
    _ preset: FanPreset,
    reply: @escaping (Bool, Int, Int, Int, Int, Bool, String) -> Void
  ) {
    let report = operationGate.perform {
      let report: PresetFanReport
      do {
        report = try presetControllerFactory().apply(preset)
      } catch {
        report = PresetFanReport(
          success: false, preset: preset, targetRPMs: [], actualRPMs: [],
          didRestoreAutomatic: false, message: error.localizedDescription)
      }
      if report.success {
        watchdog.arm(reason: "\(preset.displayName) preset verified; awaiting heartbeat.")
        logger.info("\(preset.displayName, privacy: .public) preset verified: targets=\(report.targetRPMs.description, privacy: .public)")
      } else if report.didRestoreAutomatic {
        watchdog.disarm(reason: "Failed \(preset.displayName) preset rolled back to Apple automatic control.")
      } else {
        watchdog.arm(reason: "\(preset.displayName) preset failed without verified rollback; recovery armed.")
      }
      return report
    }
    reply(
      report.success,
      report.targetRPMs.indices.contains(0) ? report.targetRPMs[0] : 0,
      report.targetRPMs.indices.contains(1) ? report.targetRPMs[1] : 0,
      report.actualRPMs.indices.contains(0) ? report.actualRPMs[0] : 0,
      report.actualRPMs.indices.contains(1) ? report.actualRPMs[1] : 0,
      report.didRestoreAutomatic,
      report.message
    )
  }

  func renewControlLease(withReply reply: @escaping (Bool, Int, String) -> Void) {
    let status = watchdog.heartbeat()
    reply(status.isActive, status.remainingSeconds, status.message)
  }

  func getControlLeaseStatus(withReply reply: @escaping (Bool, Int, String) -> Void) {
    let status = watchdog.status()
    reply(status.isActive, status.remainingSeconds, status.message)
  }

  private func makeReport(restoring: Bool) -> AutomaticControlReport {
    do {
      let restorer = try restorerFactory()
      return restoring ? restorer.restore() : restorer.status()
    } catch {
      return AutomaticControlReport(
        success: false, fanModes: [], forceTest: nil, message: error.localizedDescription)
    }
  }

  private func makeManualReport(fanID: Int, rpm: Int, automatic: Bool) -> ManualFanReport {
    do {
      let controller = try manualControllerFactory()
      return automatic
        ? controller.setAutomatic(fanID: fanID)
        : controller.setRPM(fanID: fanID, requestedRPM: rpm)
    } catch {
      return ManualFanReport(
        success: false, fanID: fanID, requestedRPM: rpm, appliedRPM: 0, actualRPM: 0,
        minimumRPM: 0, maximumRPM: 0, isManual: false, didRestoreAutomatic: false,
        message: error.localizedDescription)
    }
  }

  private func send(
    _ report: AutomaticControlReport,
    to callback: (Bool, Int, Int, Int, String) -> Void
  ) {
    callback(
      report.success,
      report.fanModes.indices.contains(0) ? Int(report.fanModes[0]) : -1,
      report.fanModes.indices.contains(1) ? Int(report.fanModes[1]) : -1,
      report.forceTest.map(Int.init) ?? -1,
      report.message
    )
  }


  private func send(
    _ report: ManualFanReport,
    to callback: (Bool, Int, Int, Int, Int, Int, Bool, Bool, String) -> Void
  ) {
    callback(
      report.success, report.appliedRPM, report.actualRPM, report.minimumRPM, report.maximumRPM,
      report.fanID, report.isManual, report.didRestoreAutomatic, report.message)
  }
}

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
  private let logger = Logger(subsystem: "com.breeze.monitor", category: "XPC")
  private let service: BreezeHelperProtocol
  private let clientSigningRequirement: String?
  private let expectedClientExecutableURL: URL?

  init(
    service: BreezeHelperProtocol = HelperService(),
    clientSigningRequirement: String? = BreezeHelperConstants.peerSigningRequirement(
      identifier: "com.cai.Breeze"),
    expectedClientExecutableURL: URL? = HelperListenerDelegate.bundledAppExecutableURL
  ) {
    self.service = service
    self.clientSigningRequirement = clientSigningRequirement
    self.expectedClientExecutableURL = expectedClientExecutableURL
  }

  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    // The nil option exists only for same-process transport tests. The launch
    // daemon always uses the identifier requirement before resuming a client.
    if let expectedClientExecutableURL {
      guard Self.executableURL(for: connection.processIdentifier) == expectedClientExecutableURL else {
        logger.error(
          "Rejected XPC client with unexpected executable path, pid=\(connection.processIdentifier, privacy: .public)"
        )
        return false
      }
    }
    if let clientSigningRequirement {
      connection.setCodeSigningRequirement(clientSigningRequirement)
    }
    connection.exportedInterface = NSXPCInterface(with: BreezeHelperProtocol.self)
    connection.exportedObject = service
    connection.invalidationHandler = { [logger] in
      logger.debug("XPC client disconnected")
    }
    connection.resume()
    logger.info(
      "Accepted XPC client pid=\(connection.processIdentifier, privacy: .public) uid=\(connection.effectiveUserIdentifier, privacy: .public)"
    )
    return true
  }

  private static func executableURL(for processIdentifier: pid_t) -> URL? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let length = proc_pidpath(processIdentifier, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    let pathBytes = buffer.prefix(Int(length)).prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return URL(fileURLWithPath: String(decoding: pathBytes, as: UTF8.self))
      .resolvingSymlinksInPath()
      .standardizedFileURL
  }

  private static var bundledAppExecutableURL: URL? {
    executableURL(for: getpid())?
      .deletingLastPathComponent()
      .appendingPathComponent("Breeze")
  }
}
