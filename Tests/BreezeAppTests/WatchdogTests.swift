import Foundation
import Testing

@testable import BreezeHelper

private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: TimeInterval = 1_000

  func now() -> TimeInterval { lock.withLock { value } }
  func advance(_ seconds: TimeInterval) {
    lock.withLock { value += seconds }
  }
}

private final class RestoreRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var reports: [AutomaticControlReport]
  private(set) var callCount = 0

  init(_ reports: [AutomaticControlReport]) {
    self.reports = reports
  }

  func restore() -> AutomaticControlReport {
    lock.withLock {
      callCount += 1
      if reports.count > 1 { return reports.removeFirst() }
      return reports[0]
    }
  }
}

private let successfulRestore = AutomaticControlReport(
  success: true, fanModes: [0, 0], forceTest: nil,
  message: "Apple automatic control restored and verified.")

private let failedRestore = AutomaticControlReport(
  success: false, fanModes: [1, 0], forceTest: nil,
  message: "Fan 0 remained manual.")

@Suite("Safety watchdog")
struct WatchdogTests {
  @Test("Heartbeat extends an active lease")
  func heartbeatExtendsLease() {
    let clock = TestClock()
    let recorder = RestoreRecorder([successfulRestore])
    let watchdog = ControlLeaseWatchdog(
      timeout: 15, now: clock.now, restore: recorder.restore, startsTimer: false)

    #expect(watchdog.arm().remainingSeconds == 15)
    clock.advance(10)
    #expect(watchdog.heartbeat().remainingSeconds == 15)
    clock.advance(10)
    watchdog.checkNow()

    #expect(recorder.callCount == 0)
    #expect(watchdog.status().isActive)
  }

  @Test("Heartbeat timeout restores Automatic and disarms")
  func timeoutRestores() {
    let clock = TestClock()
    let recorder = RestoreRecorder([successfulRestore])
    let watchdog = ControlLeaseWatchdog(
      timeout: 15, now: clock.now, restore: recorder.restore, startsTimer: false)

    watchdog.arm()
    clock.advance(15)
    watchdog.checkNow()

    #expect(recorder.callCount == 1)
    #expect(!watchdog.status().isActive)
    #expect(watchdog.status().message.contains("Heartbeat timeout"))
  }

  @Test("Failed timeout restore stays armed and retries")
  func failedRestoreRetries() {
    let clock = TestClock()
    let recorder = RestoreRecorder([failedRestore, successfulRestore])
    let watchdog = ControlLeaseWatchdog(
      timeout: 15, retryInterval: 2, now: clock.now,
      restore: recorder.restore, startsTimer: false)

    watchdog.arm()
    clock.advance(15)
    watchdog.checkNow()
    #expect(recorder.callCount == 1)
    #expect(watchdog.status().isActive)

    clock.advance(2)
    watchdog.checkNow()
    #expect(recorder.callCount == 2)
    #expect(!watchdog.status().isActive)
  }

  @Test("Helper startup always attempts Automatic recovery")
  func startupRecovery() {
    let recorder = RestoreRecorder([successfulRestore])
    let watchdog = ControlLeaseWatchdog(
      restore: recorder.restore, startsTimer: false)

    let report = watchdog.recoverOnStartup()

    #expect(report.success)
    #expect(recorder.callCount == 1)
    #expect(!watchdog.status().isActive)
  }

  @Test("Unsupported hardware does not create a permanent retry loop")
  func unsupportedHardwareDoesNotRetry() {
    let clock = TestClock()
    let unsupported = AutomaticControlReport(
      success: false, fanModes: [], forceTest: nil,
      message: "Unsupported model.", shouldRetryAfterFailure: false)
    let recorder = RestoreRecorder([unsupported])
    let watchdog = ControlLeaseWatchdog(
      retryInterval: 2, now: clock.now, restore: recorder.restore, startsTimer: false)

    _ = watchdog.recoverOnStartup()
    clock.advance(10)
    watchdog.checkNow()

    #expect(recorder.callCount == 1)
    #expect(!watchdog.status().isActive)
  }

  @Test("A new Manual lease cannot be cleared by an older timeout restore")
  func newManualLeaseWinsRestoreRace() {
    let clock = TestClock()
    let gate = ControlOperationGate()
    let restoreEntered = DispatchSemaphore(value: 0)
    let allowRestore = DispatchSemaphore(value: 0)
    let restoreFinished = DispatchSemaphore(value: 0)
    let manualFinished = DispatchSemaphore(value: 0)
    let watchdog = ControlLeaseWatchdog(
      timeout: 15,
      now: clock.now,
      operationGate: gate,
      restore: {
        restoreEntered.signal()
        allowRestore.wait()
        return successfulRestore
      },
      startsTimer: false)

    watchdog.arm()
    clock.advance(15)
    DispatchQueue.global().async {
      watchdog.checkNow()
      restoreFinished.signal()
    }
    #expect(restoreEntered.wait(timeout: .now() + 1) == .success)

    DispatchQueue.global().async {
      _ = gate.perform { watchdog.arm(reason: "New Manual session") }
      manualFinished.signal()
    }
    #expect(manualFinished.wait(timeout: .now() + 0.05) == .timedOut)

    allowRestore.signal()
    #expect(restoreFinished.wait(timeout: .now() + 1) == .success)
    #expect(manualFinished.wait(timeout: .now() + 1) == .success)
    #expect(watchdog.status().isActive)
    #expect(watchdog.status().message == "New Manual session")
  }

  @Test("A replacement Helper restores state left by a crashed Helper")
  func helperRestartRecovery() {
    let oldRecorder = RestoreRecorder([successfulRestore])
    let oldWatchdog = ControlLeaseWatchdog(
      restore: oldRecorder.restore, startsTimer: false)
    oldWatchdog.arm()
    #expect(oldWatchdog.status().isActive)

    // A new daemon process has no in-memory lease, so startup recovery must
    // perform a real restore rather than trusting a clean initial state.
    let replacementRecorder = RestoreRecorder([successfulRestore])
    let replacement = ControlLeaseWatchdog(
      restore: replacementRecorder.restore, startsTimer: false)
    _ = replacement.recoverOnStartup()

    #expect(replacementRecorder.callCount == 1)
    #expect(!replacement.status().isActive)
  }

  @Test("Explicit Automatic verification disarms without another write")
  func explicitDisarm() {
    let clock = TestClock()
    let recorder = RestoreRecorder([successfulRestore])
    let watchdog = ControlLeaseWatchdog(
      timeout: 15, now: clock.now, restore: recorder.restore, startsTimer: false)

    watchdog.arm()
    watchdog.disarm()
    clock.advance(30)
    watchdog.checkNow()

    #expect(recorder.callCount == 0)
    #expect(!watchdog.status().isActive)
  }

  @Test("A heartbeat cannot create a lease after Automatic")
  func heartbeatCannotArm() {
    let recorder = RestoreRecorder([successfulRestore])
    let watchdog = ControlLeaseWatchdog(
      restore: recorder.restore, startsTimer: false)

    let status = watchdog.heartbeat()

    #expect(!status.isActive)
    #expect(status.remainingSeconds == 0)
    #expect(recorder.callCount == 0)
  }
}
