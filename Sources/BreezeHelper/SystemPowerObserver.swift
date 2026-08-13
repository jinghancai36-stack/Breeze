import Foundation
import IOKit
import IOKit.pwr_mgt
import OSLog

/// Root-side sleep/wake safety hook. The app also requests Automatic on
/// `willSleep`, but this observer remains effective if the GUI is hung.
final class SystemPowerObserver: @unchecked Sendable {
  // Swift cannot import IOMessage.h's iokit_common_msg macro. These are the
  // SDK-defined values: err_system(0x38) | err_sub(0) | message.
  private static let canSystemSleep: UInt32 = 0xe000_0270
  private static let systemWillSleep: UInt32 = 0xe000_0280
  private static let systemHasPoweredOn: UInt32 = 0xe000_0300
  private let logger = Logger(subsystem: "com.breeze.monitor", category: "Power")
  private let watchdog: ControlLeaseWatchdog
  private let stateLock = NSLock()
  private var workerThread: Thread?
  private var runLoop: CFRunLoop?
  private var isStopping = false
  private var rootPort: io_connect_t = 0
  private var notificationPort: IONotificationPortRef?
  private var notifier: io_object_t = 0

  init(watchdog: ControlLeaseWatchdog) {
    self.watchdog = watchdog
  }

  func start() {
    let thread = stateLock.withLock { () -> Thread? in
      guard workerThread == nil else { return nil }
      isStopping = false
      let thread = Thread { [weak self] in self?.runPowerLoop() }
      thread.name = "com.cai.Breeze.Helper.power-observer"
      workerThread = thread
      return thread
    }
    thread?.start()
  }

  private func runPowerLoop() {
    let context = Unmanaged.passUnretained(self).toOpaque()
    rootPort = IORegisterForSystemPower(
      context,
      &notificationPort,
      { context, _, messageType, messageArgument in
        guard let context else { return }
        Unmanaged<SystemPowerObserver>.fromOpaque(context).takeUnretainedValue()
          .handle(messageType: messageType, argument: messageArgument)
      },
      &notifier)

    guard rootPort != 0, let notificationPort,
      let source = IONotificationPortGetRunLoopSource(notificationPort)?.takeUnretainedValue()
    else {
      logger.error("Unable to register root power notifications")
      cleanUpPowerRegistration()
      stateLock.withLock { workerThread = nil }
      return
    }
    let currentRunLoop = CFRunLoopGetCurrent()
    let shouldRun = stateLock.withLock {
      runLoop = currentRunLoop
      return !isStopping
    }
    guard shouldRun else {
      cleanUpPowerRegistration()
      stateLock.withLock {
        runLoop = nil
        workerThread = nil
      }
      return
    }
    CFRunLoopAddSource(currentRunLoop, source, .defaultMode)
    logger.info("Root sleep/wake safety observer ready")
    CFRunLoopRun()
    cleanUpPowerRegistration()
    stateLock.withLock {
      runLoop = nil
      workerThread = nil
    }
  }

  func stop() {
    let currentRunLoop = stateLock.withLock { () -> CFRunLoop? in
      isStopping = true
      return runLoop
    }
    guard let currentRunLoop else { return }
    CFRunLoopPerformBlock(currentRunLoop, CFRunLoopMode.defaultMode.rawValue) {
      CFRunLoopStop(currentRunLoop)
    }
    CFRunLoopWakeUp(currentRunLoop)
  }

  private func cleanUpPowerRegistration() {
    if notifier != 0 {
      IOObjectRelease(notifier)
      notifier = 0
    }
    if rootPort != 0 {
      IOServiceClose(rootPort)
      rootPort = 0
    }
    if let notificationPort {
      IONotificationPortDestroy(notificationPort)
      self.notificationPort = nil
    }
  }

  deinit { stop() }

  private func handle(messageType: UInt32, argument: UnsafeMutableRawPointer?) {
    switch messageType {
    case Self.canSystemSleep:
      allowPowerChange(argument)
    case Self.systemWillSleep:
      let report = watchdog.restoreForSystemEvent("System sleep recovery")
      if report.success {
        logger.info("Automatic control verified before sleep")
      } else {
        logger.error("Pre-sleep restore failed and remains armed for retry")
      }
      allowPowerChange(argument)
    case Self.systemHasPoweredOn:
      // Never reapply Manual after wake. Reassert Automatic in case sleep
      // interrupted the pre-sleep IOKit transaction.
      _ = watchdog.restoreForSystemEvent("System wake recovery")
    default:
      break
    }
  }

  private func allowPowerChange(_ argument: UnsafeMutableRawPointer?) {
    guard let argument, rootPort != 0 else { return }
    IOAllowPowerChange(rootPort, Int(bitPattern: argument))
  }
}
