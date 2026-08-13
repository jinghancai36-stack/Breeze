import Foundation
import OSLog

struct ControlLeaseSnapshot: Equatable, Sendable {
  let isActive: Bool
  let remainingSeconds: Int
  let message: String
}

final class ControlOperationGate: @unchecked Sendable {
  private let lock = NSRecursiveLock()

  func perform<T>(_ operation: () throws -> T) rethrows -> T {
    try lock.withLock(operation)
  }
}

/// Helper-owned fail-safe for every manual-control session.
///
/// The GUI can renew the lease but cannot lengthen or disable its fixed
/// timeout. A failed automatic restore remains armed and is retried.
final class ControlLeaseWatchdog: @unchecked Sendable {
  static let defaultTimeout: TimeInterval = 15
  static let defaultHeartbeatInterval: TimeInterval = 5

  private let lock = NSLock()
  private let restoreLock = NSLock()
  private let timeout: TimeInterval
  private let retryInterval: TimeInterval
  private let now: () -> TimeInterval
  private let restore: () -> AutomaticControlReport
  private let operationGate: ControlOperationGate
  private let logger = Logger(subsystem: "com.breeze.monitor", category: "Watchdog")
  private var deadline: TimeInterval?
  private var isRestoring = false
  private var lastMessage = "No manual-control lease is active."
  private var timer: DispatchSourceTimer?

  init(
    timeout: TimeInterval = ControlLeaseWatchdog.defaultTimeout,
    retryInterval: TimeInterval = 2,
    checkInterval: TimeInterval = 1,
    now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    operationGate: ControlOperationGate = ControlOperationGate(),
    restore: @escaping () -> AutomaticControlReport,
    startsTimer: Bool = true
  ) {
    self.timeout = max(1, timeout)
    self.retryInterval = max(0.1, retryInterval)
    self.now = now
    self.operationGate = operationGate
    self.restore = restore
    if startsTimer {
      let source = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
      source.schedule(deadline: .now() + max(0.1, checkInterval), repeating: max(0.1, checkInterval))
      source.setEventHandler { [weak self] in self?.checkNow() }
      source.resume()
      timer = source
    }
  }

  deinit {
    timer?.cancel()
  }

  @discardableResult
  func arm(reason: String = "Manual control active.") -> ControlLeaseSnapshot {
    lock.withLock {
      deadline = now() + timeout
      lastMessage = reason
      return snapshotLocked(at: now())
    }
  }

  func heartbeat() -> ControlLeaseSnapshot {
    lock.withLock {
      guard deadline != nil else {
        lastMessage = "Heartbeat rejected because no manual-control lease is active."
        return snapshotLocked(at: now())
      }
      deadline = now() + timeout
      lastMessage = "Manual-control lease renewed."
      return snapshotLocked(at: now())
    }
  }

  func status() -> ControlLeaseSnapshot {
    lock.withLock { snapshotLocked(at: now()) }
  }

  func disarm(reason: String = "Apple automatic control verified.") {
    lock.withLock {
      deadline = nil
      isRestoring = false
      lastMessage = reason
    }
  }

  /// Used at daemon launch and by tests. Startup recovery is unconditional so
  /// a previous helper crash or reboot cannot silently preserve manual state.
  @discardableResult
  func recoverOnStartup() -> AutomaticControlReport {
    restoreNow(reason: "Helper startup recovery")
  }

  @discardableResult
  func restoreForSystemEvent(_ reason: String) -> AutomaticControlReport {
    restoreNow(reason: reason)
  }

  func checkNow() {
    let shouldRestore = lock.withLock {
      guard let deadline, now() >= deadline, !isRestoring else { return false }
      isRestoring = true
      // Prevent concurrent timer ticks while the IOKit verification runs.
      self.deadline = now() + retryInterval
      lastMessage = "Lease expired; restoring Apple automatic control."
      return true
    }
    guard shouldRestore else { return }
    _ = restoreNow(reason: "Heartbeat timeout")
  }

  @discardableResult
  private func restoreNow(reason: String) -> AutomaticControlReport {
    restoreLock.withLock {
      operationGate.perform {
        let report = restore()
        lock.withLock {
          isRestoring = false
          if report.success {
            deadline = nil
            lastMessage = "\(reason): Apple automatic control restored and verified."
          } else if report.shouldRetryAfterFailure {
            // Startup failures also become an active retry lease. This keeps the
            // daemon trying rather than treating one transient IOKit error as safe.
            deadline = now() + retryInterval
            lastMessage = "\(reason) failed; automatic restore will retry: \(report.message)"
          } else {
            deadline = nil
            lastMessage = "\(reason) skipped retry: \(report.message)"
          }
        }
        if report.success {
          logger.info("\(reason, privacy: .public) succeeded")
        } else if report.shouldRetryAfterFailure {
          logger.error("\(reason, privacy: .public) failed: \(report.message, privacy: .public)")
        } else {
          logger.notice("\(reason, privacy: .public) is not applicable: \(report.message, privacy: .public)")
        }
        return report
      }
    }
  }

  private func snapshotLocked(at time: TimeInterval) -> ControlLeaseSnapshot {
    guard let deadline else {
      return ControlLeaseSnapshot(isActive: false, remainingSeconds: 0, message: lastMessage)
    }
    return ControlLeaseSnapshot(
      isActive: true,
      remainingSeconds: max(0, Int(ceil(deadline - time))),
      message: lastMessage
    )
  }
}
