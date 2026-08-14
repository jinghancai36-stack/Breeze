import Foundation

#if canImport(BreezeHardware)
  import BreezeHardware
#endif

enum CurveSensorSource: String, CaseIterable, Codable, Identifiable, Sendable {
  case cpuGPUPeak
  case cpu
  case gpu

  var id: String { rawValue }
}

struct FanCurvePoint: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var temperature: Int
  var fanPercent: Int

  init(id: UUID = UUID(), temperature: Int, fanPercent: Int) {
    self.id = id
    self.temperature = temperature
    self.fanPercent = fanPercent
  }
}

struct FanCurveConfiguration: Codable, Equatable, Sendable {
  static let minimumTemperature = 35
  static let maximumTemperature = 100
  static let minimumFanPercent = 20
  static let maximumFanPercent = 100
  static let percentageStep = 5
  static let minimumPointSpacing = 3

  var sensorSource: CurveSensorSource
  var points: [FanCurvePoint]
  var hysteresis: Double
  var decreaseDelaySeconds: Double

  static let `default` = FanCurveConfiguration(
    sensorSource: .cpuGPUPeak,
    points: [
      FanCurvePoint(temperature: 50, fanPercent: 20),
      FanCurvePoint(temperature: 60, fanPercent: 35),
      FanCurvePoint(temperature: 75, fanPercent: 60),
      FanCurvePoint(temperature: 88, fanPercent: 100),
    ],
    hysteresis: 3,
    decreaseDelaySeconds: 5
  )

  var isValid: Bool {
    guard (2...6).contains(points.count),
      (0...10).contains(hysteresis),
      (0...30).contains(decreaseDelaySeconds)
    else { return false }

    let sorted = points.sorted { $0.temperature < $1.temperature }
    guard sorted == points else { return false }

    for (index, point) in points.enumerated() {
      guard (Self.minimumTemperature...Self.maximumTemperature).contains(point.temperature),
        (Self.minimumFanPercent...Self.maximumFanPercent).contains(point.fanPercent),
        point.fanPercent.isMultiple(of: Self.percentageStep)
      else { return false }
      if index > 0 {
        let previous = points[index - 1]
        guard point.temperature - previous.temperature >= Self.minimumPointSpacing,
          point.fanPercent >= previous.fanPercent
        else { return false }
      }
    }
    return true
  }
}

struct FanCurveDecisionState: Equatable, Sendable {
  var appliedPercent: Int?
  var appliedTemperature: Double?
  var pendingDecreasePercent: Int?
  var pendingDecreaseSince: Date?

  mutating func reset() {
    self = FanCurveDecisionState()
  }
}

enum CustomFanCurvePolicy {
  static func controlTemperature(
    for snapshot: HardwareSnapshot,
    source: CurveSensorSource
  ) -> Double? {
    let cpu = snapshot.hottestTemperature(in: .cpu)?.temperature
    let gpu = snapshot.hottestTemperature(in: .gpu)?.temperature
    switch source {
    case .cpuGPUPeak: return [cpu, gpu].compactMap { $0 }.max()
    case .cpu: return cpu
    case .gpu: return gpu
    }
  }

  static func interpolatedPercent(
    for temperature: Double,
    configuration: FanCurveConfiguration
  ) -> Int? {
    guard configuration.isValid, let first = configuration.points.first,
      let last = configuration.points.last
    else { return nil }

    if temperature <= Double(first.temperature) { return first.fanPercent }
    if temperature >= Double(last.temperature) { return last.fanPercent }

    for (lower, upper) in zip(configuration.points, configuration.points.dropFirst())
    where temperature <= Double(upper.temperature) {
      let progress =
        (temperature - Double(lower.temperature))
        / Double(upper.temperature - lower.temperature)
      let raw = Double(lower.fanPercent) + progress * Double(upper.fanPercent - lower.fanPercent)
      return quantize(raw)
    }
    return last.fanPercent
  }

  static func nextTarget(
    temperature: Double,
    configuration: FanCurveConfiguration,
    state: inout FanCurveDecisionState,
    now: Date
  ) -> Int? {
    guard let candidate = interpolatedPercent(
      for: temperature, configuration: configuration)
    else { return nil }

    guard let applied = state.appliedPercent else {
      record(candidate, temperature: temperature, state: &state)
      return candidate
    }
    guard candidate != applied else {
      state.pendingDecreasePercent = nil
      state.pendingDecreaseSince = nil
      return nil
    }

    // Rising temperatures are never delayed. Hysteresis and delay only calm
    // downward changes, where a slower response cannot reduce thermal safety.
    if candidate > applied {
      record(candidate, temperature: temperature, state: &state)
      return candidate
    }

    if let appliedTemperature = state.appliedTemperature,
      temperature > appliedTemperature - configuration.hysteresis
    {
      return nil
    }

    if state.pendingDecreasePercent != candidate {
      state.pendingDecreasePercent = candidate
      state.pendingDecreaseSince = now
      if configuration.decreaseDelaySeconds > 0 { return nil }
    }

    guard let since = state.pendingDecreaseSince,
      now.timeIntervalSince(since) >= configuration.decreaseDelaySeconds
    else { return nil }
    record(candidate, temperature: temperature, state: &state)
    return candidate
  }

  private static func quantize(_ percent: Double) -> Int {
    let step = Double(FanCurveConfiguration.percentageStep)
    let rounded = Int((percent / step).rounded() * step)
    return min(
      max(rounded, FanCurveConfiguration.minimumFanPercent),
      FanCurveConfiguration.maximumFanPercent)
  }

  private static func record(
    _ percent: Int,
    temperature: Double,
    state: inout FanCurveDecisionState
  ) {
    state.appliedPercent = percent
    state.appliedTemperature = temperature
    state.pendingDecreasePercent = nil
    state.pendingDecreaseSince = nil
  }
}

struct CurveConfigurationStore {
  private static let key = "fanCurveConfiguration.v1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> FanCurveConfiguration {
    guard let data = defaults.data(forKey: Self.key),
      let configuration = try? JSONDecoder().decode(FanCurveConfiguration.self, from: data),
      configuration.isValid
    else { return .default }
    return configuration
  }

  @discardableResult
  func save(_ configuration: FanCurveConfiguration) -> Bool {
    guard configuration.isValid,
      let data = try? JSONEncoder().encode(configuration)
    else { return false }
    defaults.set(data, forKey: Self.key)
    return true
  }
}

struct ThermalHistorySample: Identifiable, Equatable, Sendable {
  let id: Date
  let cpuTemperature: Double?
  let gpuTemperature: Double?
  let fanRPMs: [Double]
}
