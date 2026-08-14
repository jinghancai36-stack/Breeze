import BreezeHardware
import Foundation
import Testing

@testable import BreezeApp

@Suite("Custom fan curve")
struct CurveConfigurationTests {
  @Test("Default curve is valid and interpolation is quantized")
  func interpolation() {
    let configuration = FanCurveConfiguration.default

    #expect(configuration.isValid)
    #expect(CustomFanCurvePolicy.interpolatedPercent(
      for: 40, configuration: configuration) == 20)
    #expect(CustomFanCurvePolicy.interpolatedPercent(
      for: 55, configuration: configuration) == 30)
    #expect(CustomFanCurvePolicy.interpolatedPercent(
      for: 60, configuration: configuration) == 35)
    #expect(CustomFanCurvePolicy.interpolatedPercent(
      for: 75, configuration: configuration) == 60)
    #expect(CustomFanCurvePolicy.interpolatedPercent(
      for: 95, configuration: configuration) == 100)
  }

  @Test("Invalid or descending points are rejected")
  func validation() {
    var configuration = FanCurveConfiguration.default
    configuration.points[1].fanPercent = 15
    #expect(!configuration.isValid)

    configuration = .default
    configuration.points[2].temperature = 61
    #expect(!configuration.isValid)

    configuration = .default
    configuration.points[2].fanPercent = 30
    #expect(!configuration.isValid)
  }

  @Test("Sensor source selects CPU, GPU, or their peak")
  func sensorSource() {
    let snapshot = HardwareSnapshot(
      hardware: MacHardware(
        modelIdentifier: "MacBookPro18,3", chipName: "Apple M1 Pro",
        architecture: "arm64", fanCount: 2, isControlVerified: true),
      fans: [],
      sensors: [
        ThermalSensor(id: "cpu", name: "CPU", temperature: 64, category: .cpu),
        ThermalSensor(id: "gpu", name: "GPU", temperature: 71, category: .gpu),
      ])

    #expect(CustomFanCurvePolicy.controlTemperature(for: snapshot, source: .cpu) == 64)
    #expect(CustomFanCurvePolicy.controlTemperature(for: snapshot, source: .gpu) == 71)
    #expect(CustomFanCurvePolicy.controlTemperature(for: snapshot, source: .cpuGPUPeak) == 71)
  }

  @Test("Rising targets apply immediately while decreases honor hysteresis and delay")
  func responsePolicy() {
    var configuration = FanCurveConfiguration.default
    configuration.hysteresis = 3
    configuration.decreaseDelaySeconds = 5
    var state = FanCurveDecisionState()
    let start = Date(timeIntervalSince1970: 1_000)

    #expect(CustomFanCurvePolicy.nextTarget(
      temperature: 60, configuration: configuration, state: &state, now: start) == 35)
    #expect(CustomFanCurvePolicy.nextTarget(
      temperature: 75, configuration: configuration, state: &state, now: start) == 60)

    // A small decrease remains inside the hysteresis band.
    #expect(CustomFanCurvePolicy.nextTarget(
      temperature: 73, configuration: configuration, state: &state, now: start) == nil)

    // A larger decrease begins the delay, then applies after five seconds.
    #expect(CustomFanCurvePolicy.nextTarget(
      temperature: 70, configuration: configuration, state: &state, now: start) == nil)
    #expect(CustomFanCurvePolicy.nextTarget(
      temperature: 70, configuration: configuration, state: &state,
      now: start.addingTimeInterval(4)) == nil)
    #expect(CustomFanCurvePolicy.nextTarget(
      temperature: 70, configuration: configuration, state: &state,
      now: start.addingTimeInterval(5)) == 50)
  }

  @Test("Configuration persists and invalid stored data falls back safely")
  func persistence() throws {
    let suite = "BreezeCurveTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = CurveConfigurationStore(defaults: defaults)
    var configuration = FanCurveConfiguration.default
    configuration.sensorSource = .gpu
    configuration.points[0].fanPercent = 25

    #expect(store.save(configuration))
    #expect(store.load() == configuration)

    defaults.set(Data("not-json".utf8), forKey: "fanCurveConfiguration.v1")
    #expect(store.load() == .default)
  }
}
