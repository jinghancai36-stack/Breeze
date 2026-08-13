import Foundation
import Testing

@testable import BreezeApp
@testable import BreezeHelper
import BreezeIPC

private final class LeaseTestClock: @unchecked Sendable {
  var value: TimeInterval = 2_000
  func now() -> TimeInterval { value }
  func advance(_ seconds: TimeInterval) { value += seconds }
}

@Suite("Helper XPC")
struct HelperXPCTests {
  @Test("Graceful Helper termination restores Automatic before exit")
  func gracefulTerminationRecovery() {
    let hardware = TestAutomaticHardware()
    hardware.values.removeValue(forKey: .forceTest)
    hardware.values[.fan0Mode] = 1
    let service = HelperService(restorerFactory: {
      AutomaticControlRestorer(hardware: hardware, pause: {})
    })

    let report = service.restoreBeforeTermination()

    #expect(report.success)
    #expect(report.fanModes == [0, 0])
    #expect(hardware.values[.fan0Mode] == 0)
    #expect(hardware.values[.fan1Mode] == 0)
    #expect(!service.controlWatchdog.status().isActive)
  }

  @Test("The fixed helper protocol is stable over repeated real XPC transports")
  func transport() async throws {
    let listener = NSXPCListener.anonymous()
    let delegate = HelperListenerDelegate(
      clientSigningRequirement: nil,
      expectedClientExecutableURL: nil
    )
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let client = HelperClient(endpoint: listener.endpoint, timeout: .seconds(1))
    for _ in 0..<25 {
      let version = try await probe(client)
      #expect(version == BreezeHelperConstants.helperVersion)
    }
  }

  @Test("A missing helper fails within the bounded timeout")
  func unavailable() async {
    let listener = NSXPCListener.anonymous()
    let endpoint = listener.endpoint
    listener.invalidate()
    let client = HelperClient(endpoint: endpoint, timeout: .milliseconds(100))
    do {
      _ = try await probe(client)
      Issue.record("An unregistered system helper unexpectedly replied")
    } catch {
      #expect(error is HelperConnectionError)
    }
  }

  @Test("Automatic status and restore cross the narrow XPC interface")
  func automaticControlTransport() async throws {
    let hardware = TestAutomaticHardware()
    hardware.values = [.fan0Mode: 1, .fan1Mode: 1, .forceTest: 1]
    let service = HelperService(restorerFactory: {
      AutomaticControlRestorer(hardware: hardware, pause: {})
    })
    let listener = NSXPCListener.anonymous()
    let delegate = HelperListenerDelegate(
      service: service,
      clientSigningRequirement: nil,
      expectedClientExecutableURL: nil
    )
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let client = HelperClient(endpoint: listener.endpoint, timeout: .seconds(1))
    let before = try await automaticStatus(client)
    #expect(!before.isAutomatic)
    #expect(before.fanModes == [1, 1])
    #expect(before.forceTest == 1)

    let restored = try await restoreAutomatic(client)
    #expect(restored.isAutomatic)
    #expect(restored.fanModes == [0, 0])
    #expect(restored.forceTest == 0)
    #expect(hardware.writes == [.fan0Mode, .fan1Mode, .forceTest])
  }

  @Test("Clamped manual control and per-fan automatic restore cross XPC")
  func manualControlTransport() async throws {
    let hardware = TestAutomaticHardware()
    hardware.values.removeValue(forKey: .forceTest)
    let service = HelperService(
      restorerFactory: { AutomaticControlRestorer(hardware: hardware, pause: {}) },
      manualControllerFactory: { ManualFanController(hardware: hardware, pause: {}) }
    )
    let listener = NSXPCListener.anonymous()
    let delegate = HelperListenerDelegate(
      service: service, clientSigningRequirement: nil, expectedClientExecutableURL: nil)
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let client = HelperClient(
      endpoint: listener.endpoint, timeout: .seconds(1), manualTimeout: .seconds(1))
    let manual = try await setRPM(client, fanID: 0, rpm: 10)
    #expect(manual.success)
    #expect(manual.appliedRPM == 1_200)
    #expect(manual.actualRPM == 1_200)
    #expect(manual.isManual)

    let automatic = try await setAutomatic(client, fanID: 0)
    #expect(automatic.success)
    #expect(!automatic.isManual)
    #expect(hardware.values[.fan0Mode] == 0)
  }

  @Test("Manual control arms a lease and heartbeat crosses XPC")
  func watchdogTransport() async throws {
    let hardware = TestAutomaticHardware()
    hardware.values.removeValue(forKey: .forceTest)
    let operationGate = ControlOperationGate()
    let watchdog = ControlLeaseWatchdog(
      timeout: 15,
      operationGate: operationGate,
      restore: { AutomaticControlRestorer(hardware: hardware, pause: {}).restore() },
      startsTimer: false)
    let service = HelperService(
      restorerFactory: { AutomaticControlRestorer(hardware: hardware, pause: {}) },
      manualControllerFactory: { ManualFanController(hardware: hardware, pause: {}) },
      operationGate: operationGate,
      watchdog: watchdog)
    let listener = NSXPCListener.anonymous()
    let delegate = HelperListenerDelegate(
      service: service, clientSigningRequirement: nil, expectedClientExecutableURL: nil)
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let client = HelperClient(
      endpoint: listener.endpoint, timeout: .seconds(1), manualTimeout: .seconds(1))
    _ = try await setRPM(client, fanID: 0, rpm: 1_400)

    let armed = try await leaseStatus(client)
    #expect(armed.isActive)
    #expect(armed.remainingSeconds > 0)

    let renewed = try await renewLease(client)
    #expect(renewed.isActive)
    #expect(renewed.remainingSeconds == 15)

    _ = try await restoreAutomatic(client)
    #expect(!(try await leaseStatus(client)).isActive)
  }

  @Test("Balanced dynamically controls both fans and arms a lease over XPC")
  func balancedPresetTransport() async throws {
    let hardware = TestAutomaticHardware()
    hardware.values.removeValue(forKey: .forceTest)
    let gate = ControlOperationGate()
    let watchdog = ControlLeaseWatchdog(
      operationGate: gate,
      restore: { AutomaticControlRestorer(hardware: hardware, pause: {}).restore() },
      startsTimer: false)
    let service = HelperService(
      restorerFactory: { AutomaticControlRestorer(hardware: hardware, pause: {}) },
      manualControllerFactory: { ManualFanController(hardware: hardware, pause: {}) },
      presetControllerFactory: {
        PresetFanController(hardware: hardware, makeManualController: {
          ManualFanController(
            hardware: hardware,
            settleAfterManualMode: {}, pauseBeforeTargetRetry: {}, pause: {})
        })
      },
      operationGate: gate,
      watchdog: watchdog)
    let listener = NSXPCListener.anonymous()
    let delegate = HelperListenerDelegate(
      service: service, clientSigningRequirement: nil, expectedClientExecutableURL: nil)
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let client = HelperClient(
      endpoint: listener.endpoint, timeout: .seconds(1), presetTimeout: .seconds(1))
    let balanced = try await applyBalanced(client)

    #expect(balanced.success)
    #expect(balanced.targetRPMs == [2_800, 2_950])
    #expect(balanced.actualRPMs == [2_800, 2_950])
    #expect((try await leaseStatus(client)).isActive)
  }

  @Test("Cool dynamically controls both fans and arms a lease over XPC")
  func coolPresetTransport() async throws {
    let hardware = TestAutomaticHardware()
    hardware.values.removeValue(forKey: .forceTest)
    let gate = ControlOperationGate()
    let watchdog = ControlLeaseWatchdog(
      operationGate: gate,
      restore: { AutomaticControlRestorer(hardware: hardware, pause: {}).restore() },
      startsTimer: false)
    let service = HelperService(
      restorerFactory: { AutomaticControlRestorer(hardware: hardware, pause: {}) },
      presetControllerFactory: {
        PresetFanController(hardware: hardware, makeManualController: {
          ManualFanController(
            hardware: hardware,
            settleAfterManualMode: {}, pauseBeforeTargetRetry: {}, pause: {})
        })
      },
      operationGate: gate,
      watchdog: watchdog)
    let listener = NSXPCListener.anonymous()
    let delegate = HelperListenerDelegate(
      service: service, clientSigningRequirement: nil, expectedClientExecutableURL: nil)
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let client = HelperClient(
      endpoint: listener.endpoint, timeout: .seconds(1), presetTimeout: .seconds(1))
    let cool = try await applyCool(client)

    #expect(cool.success)
    #expect(cool.targetRPMs == [3_950, 4_200])
    #expect((try await leaseStatus(client)).isActive)
  }

  @Test("XPC disconnect followed by heartbeat timeout restores Automatic")
  func disconnectedClientTimesOut() async throws {
    let hardware = TestAutomaticHardware()
    hardware.values.removeValue(forKey: .forceTest)
    let clock = LeaseTestClock()
    let operationGate = ControlOperationGate()
    let watchdog = ControlLeaseWatchdog(
      timeout: 15,
      now: clock.now,
      operationGate: operationGate,
      restore: { AutomaticControlRestorer(hardware: hardware, pause: {}).restore() },
      startsTimer: false)
    let service = HelperService(
      restorerFactory: { AutomaticControlRestorer(hardware: hardware, pause: {}) },
      manualControllerFactory: { ManualFanController(hardware: hardware, pause: {}) },
      operationGate: operationGate,
      watchdog: watchdog)
    let listener = NSXPCListener.anonymous()
    let delegate = HelperListenerDelegate(
      service: service, clientSigningRequirement: nil, expectedClientExecutableURL: nil)
    listener.delegate = delegate
    listener.resume()

    let client = HelperClient(
      endpoint: listener.endpoint, timeout: .seconds(1), manualTimeout: .seconds(1))
    _ = try await setRPM(client, fanID: 0, rpm: 1_400)
    #expect(hardware.values[.fan0Mode] == 1)
    listener.invalidate() // No more heartbeat transport can reach the Helper.

    clock.advance(15)
    watchdog.checkNow()

    #expect(hardware.values[.fan0Mode] == 0)
    #expect(hardware.values[.fan1Mode] == 0)
    #expect(!watchdog.status().isActive)
  }

  @Test("The helper rejects a client outside its expected app bundle")
  func rejectsUnexpectedClientPath() async {
    let listener = NSXPCListener.anonymous()
    let delegate = HelperListenerDelegate(
      clientSigningRequirement: nil,
      expectedClientExecutableURL: URL(fileURLWithPath: "/not-the-breeze-client")
    )
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let client = HelperClient(endpoint: listener.endpoint, timeout: .milliseconds(200))
    do {
      _ = try await probe(client)
      Issue.record("An unexpected executable path was accepted")
    } catch {
      #expect(error is HelperConnectionError)
    }
  }

  private func probe(_ client: HelperClient) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      client.probe { result in
        continuation.resume(with: result)
      }
    }
  }


  private func automaticStatus(_ client: HelperClient) async throws -> AutomaticControlStatus {
    try await withCheckedThrowingContinuation { continuation in
      client.automaticControlStatus { result in continuation.resume(with: result) }
    }
  }

  private func restoreAutomatic(_ client: HelperClient) async throws -> AutomaticControlStatus {
    try await withCheckedThrowingContinuation { continuation in
      client.restoreAutomaticControl { result in continuation.resume(with: result) }
    }
  }

  private func setRPM(_ client: HelperClient, fanID: Int, rpm: Int) async throws -> FanControlStatus {
    try await withCheckedThrowingContinuation { continuation in
      client.setFanRPM(fanID: fanID, rpm: rpm) { result in continuation.resume(with: result) }
    }
  }

  private func setAutomatic(_ client: HelperClient, fanID: Int) async throws -> FanControlStatus {
    try await withCheckedThrowingContinuation { continuation in
      client.setFanAutomatic(fanID: fanID) { result in continuation.resume(with: result) }
    }
  }

  private func renewLease(_ client: HelperClient) async throws -> ControlLeaseStatus {
    try await withCheckedThrowingContinuation { continuation in
      client.renewControlLease { result in continuation.resume(with: result) }
    }
  }

  private func applyBalanced(_ client: HelperClient) async throws -> PresetControlStatus {
    try await withCheckedThrowingContinuation { continuation in
      client.applyBalancedPreset { result in continuation.resume(with: result) }
    }
  }

  private func applyCool(_ client: HelperClient) async throws -> PresetControlStatus {
    try await withCheckedThrowingContinuation { continuation in
      client.applyCoolPreset { result in continuation.resume(with: result) }
    }
  }

  private func leaseStatus(_ client: HelperClient) async throws -> ControlLeaseStatus {
    try await withCheckedThrowingContinuation { continuation in
      client.controlLeaseStatus { result in continuation.resume(with: result) }
    }
  }
}
