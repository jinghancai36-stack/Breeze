import Foundation
import OSLog
import Darwin

#if canImport(BreezeIPC)
  import BreezeIPC
#endif

private func runInternalTargetWorker() -> Never {
  let arguments = ProcessInfo.processInfo.arguments
  guard geteuid() == 0,
    arguments.count == 4,
    arguments[1] == "--internal-target-worker",
    let fanID = Int(arguments[2]),
    let fan = VerifiedFan(rawValue: fanID),
    let rpm = Float(arguments[3])
  else {
    fputs("Invalid fixed target-worker request.\n", stderr)
    exit(EXIT_FAILURE)
  }
  do {
    let hardware = try SMCRestoreConnection()
    guard hardware.modelIdentifier == AutomaticControlRestorer.supportedModel,
      try hardware.fanCount() == AutomaticControlRestorer.supportedFanCount,
      try hardware.readForceTest() == nil,
      try hardware.mode(for: fan) == 1
    else {
      throw ManualFanError.unsupportedControlStrategy
    }
    let minimum = try hardware.minimumRPM(for: fan)
    let maximum = try hardware.maximumRPM(for: fan)
    guard minimum.isFinite, maximum.isFinite, minimum >= 1_000, maximum <= 7_000,
      minimum < maximum, rpm.isFinite, rpm >= minimum, rpm <= maximum
    else {
      throw ManualFanError.untrustedBounds(minimum: minimum, maximum: maximum)
    }
    try hardware.writeTargetRPM(rpm, for: fan)
    exit(EXIT_SUCCESS)
  } catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
  }
}

if ProcessInfo.processInfo.arguments.contains("--internal-target-worker") {
  runInternalTargetWorker()
}

let logger = Logger(subsystem: "com.breeze.monitor", category: "Helper")
let service = HelperService()
let startupReport = service.recoverOnStartup()
if startupReport.success {
  logger.info("Startup automatic recovery verified")
} else {
  logger.error("Startup recovery will retry: \(startupReport.message, privacy: .public)")
}
let powerObserver = SystemPowerObserver(watchdog: service.controlWatchdog)
powerObserver.start()
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let terminationSignals = [SIGTERM, SIGINT].map { signalNumber in
  let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
  source.setEventHandler {
    let report = service.restoreBeforeTermination()
    if report.success {
      logger.info("Termination recovery verified; exiting Helper")
      exit(EXIT_SUCCESS)
    }
    logger.critical(
      "Termination recovery failed; refusing graceful exit while retry remains armed: \(report.message, privacy: .public)"
    )
  }
  source.resume()
  return source
}
let delegate = HelperListenerDelegate(service: service)
let listener = NSXPCListener(machServiceName: BreezeHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
logger.info("BreezeHelper \(BreezeHelperConstants.helperVersion, privacy: .public) ready")
withExtendedLifetime((powerObserver, terminationSignals, delegate, listener)) {
  dispatchMain()
}
