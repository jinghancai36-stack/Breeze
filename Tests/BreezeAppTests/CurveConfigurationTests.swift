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

  @Test("Curve points can be safely added and removed within the limits")
  func pointEditing() throws {
    var configuration = FanCurveConfiguration.default

    let addedFifthPoint = configuration.addInterpolatedPoint()
    #expect(addedFifthPoint)
    #expect(configuration.points.count == 5)
    #expect(configuration.isValid)
    #expect(Set(configuration.points.map(\.id)).count == configuration.points.count)

    let addedSixthPoint = configuration.addInterpolatedPoint()
    #expect(addedSixthPoint)
    #expect(configuration.points.count == FanCurveConfiguration.maximumPointCount)
    let addedSeventhPoint = configuration.addInterpolatedPoint()
    #expect(!addedSeventhPoint)

    let removableID = try #require(configuration.points.dropFirst().first?.id)
    let removedPoint = configuration.removePoint(id: removableID)
    #expect(removedPoint)
    #expect(configuration.isValid)

    while configuration.points.count > FanCurveConfiguration.minimumPointCount {
      let nextID = configuration.points[1].id
      let removedNextPoint = configuration.removePoint(id: nextID)
      #expect(removedNextPoint)
    }
    let minimumPointID = configuration.points[0].id
    let removedBelowMinimum = configuration.removePoint(id: minimumPointID)
    #expect(!removedBelowMinimum)
    #expect(configuration.isValid)
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

  @Test("Thermal history persists in order, stays bounded, and can be cleared")
  func thermalHistoryPersistence() throws {
    let suite = "BreezeHistoryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ThermalHistoryStore(defaults: defaults)
    var samples: [ThermalHistorySample] = []
    for index in 0..<305 {
      let offset = Double(index)
      samples.append(
        ThermalHistorySample(
          id: Date(timeIntervalSinceReferenceDate: offset),
          cpuTemperature: 50 + Double(index % 10),
          gpuTemperature: 48 + Double(index % 8),
          fanRPMs: [2_000 + offset, 2_100 + offset]))
    }

    #expect(store.save(samples))
    let restored = store.load()
    #expect(restored.count == ThermalHistoryStore.maximumSamples)
    #expect(restored.first?.id == samples[5].id)
    #expect(restored.last?.id == samples.last?.id)

    store.clear()
    #expect(store.load().isEmpty)
  }

  @Test("Invalid thermal history data falls back safely")
  func invalidThermalHistory() throws {
    let suite = "BreezeHistoryFallbackTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ThermalHistoryStore(defaults: defaults)

    defaults.set(Data("not-json".utf8), forKey: "thermalHistory.v1")
    #expect(store.load().isEmpty)

    let invalid = ThermalHistorySample(
      id: Date(), cpuTemperature: 500, gpuTemperature: nil, fanRPMs: [2_000])
    #expect(store.save([invalid]))
    #expect(store.load().isEmpty)
  }
}
