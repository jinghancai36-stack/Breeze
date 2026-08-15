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
  static let minimumPointCount = 2
  static let maximumPointCount = 6
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
    guard (Self.minimumPointCount...Self.maximumPointCount).contains(points.count),
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

  mutating func addInterpolatedPoint() -> Bool {
    guard isValid, points.count < Self.maximumPointCount,
      let first = points.first, let last = points.last
    else { return false }

    struct Candidate {
      let temperature: Int
      let fanPercent: Int
      let span: Int
      let isInterior: Bool
      let insertionIndex: Int
    }

    var candidates: [Candidate] = []
    for index in 0..<(points.count - 1) {
      let lower = points[index]
      let upper = points[index + 1]
      let span = upper.temperature - lower.temperature
      guard span >= Self.minimumPointSpacing * 2 else { continue }
      let temperature = lower.temperature + span / 2
      guard let fanPercent = CustomFanCurvePolicy.interpolatedPercent(
        for: Double(temperature), configuration: self)
      else { continue }
      candidates.append(
        Candidate(
          temperature: temperature, fanPercent: fanPercent, span: span,
          isInterior: true, insertionIndex: index + 1))
    }

    let leadingSpan = first.temperature - Self.minimumTemperature
    if leadingSpan >= Self.minimumPointSpacing {
      let highestTemperature = first.temperature - Self.minimumPointSpacing
      candidates.append(
        Candidate(
          temperature: Self.minimumTemperature
            + (highestTemperature - Self.minimumTemperature) / 2,
          fanPercent: first.fanPercent, span: leadingSpan,
          isInterior: false, insertionIndex: 0))
    }

    let trailingSpan = Self.maximumTemperature - last.temperature
    if trailingSpan >= Self.minimumPointSpacing {
      let lowestTemperature = last.temperature + Self.minimumPointSpacing
      candidates.append(
        Candidate(
          temperature: lowestTemperature
            + (Self.maximumTemperature - lowestTemperature + 1) / 2,
          fanPercent: last.fanPercent, span: trailingSpan,
          isInterior: false, insertionIndex: points.count))
    }

    guard let candidate = candidates.max(by: {
      if $0.span != $1.span { return $0.span < $1.span }
      return !$0.isInterior && $1.isInterior
    }) else { return false }

    let previousPoints = points
    points.insert(
      FanCurvePoint(
        temperature: candidate.temperature,
        fanPercent: candidate.fanPercent),
      at: candidate.insertionIndex)
    guard isValid else {
      points = previousPoints
      return false
    }
    return true
  }

  mutating func removePoint(id: FanCurvePoint.ID) -> Bool {
    guard points.count > Self.minimumPointCount,
      let index = points.firstIndex(where: { $0.id == id })
    else { return false }
    let removed = points.remove(at: index)
    guard isValid else {
      points.insert(removed, at: index)
      return false
    }
    return true
  }

  func temperatureRange(for pointID: FanCurvePoint.ID) -> ClosedRange<Int>? {
    guard let index = points.firstIndex(where: { $0.id == pointID }) else { return nil }
    let minimum = index == 0
      ? Self.minimumTemperature
      : points[index - 1].temperature + Self.minimumPointSpacing
    let maximum = index == points.count - 1
      ? Self.maximumTemperature
      : points[index + 1].temperature - Self.minimumPointSpacing
    guard minimum <= maximum else { return nil }
    return minimum...maximum
  }

  func fanPercentRange(for pointID: FanCurvePoint.ID) -> ClosedRange<Int>? {
    guard let index = points.firstIndex(where: { $0.id == pointID }) else { return nil }
    let minimum = index == 0 ? Self.minimumFanPercent : points[index - 1].fanPercent
    let maximum = index == points.count - 1
      ? Self.maximumFanPercent : points[index + 1].fanPercent
    guard minimum <= maximum else { return nil }
    return minimum...maximum
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

struct ThermalHistorySample: Codable, Identifiable, Equatable, Sendable {
  let id: Date
  let cpuTemperature: Double?
  let gpuTemperature: Double?
  let fanRPMs: [Double]

  var isValid: Bool {
    let temperatures = [cpuTemperature, gpuTemperature].compactMap { $0 }
    return id.timeIntervalSinceReferenceDate.isFinite
      && temperatures.allSatisfy { $0.isFinite && (0...130).contains($0) }
      && fanRPMs.count <= 8
      && fanRPMs.allSatisfy { $0.isFinite && (0...20_000).contains($0) }
  }
}

struct ThermalHistoryStore {
  static let maximumSamples = 300
  private static let key = "thermalHistory.v1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> [ThermalHistorySample] {
    guard let data = defaults.data(forKey: Self.key),
      let decoded = try? JSONDecoder().decode([ThermalHistorySample].self, from: data)
    else { return [] }
    return Array(
      decoded.filter(\.isValid).sorted { $0.id < $1.id }.suffix(Self.maximumSamples))
  }

  @discardableResult
  func save(_ samples: [ThermalHistorySample]) -> Bool {
    let bounded = Array(
      samples.filter(\.isValid).sorted { $0.id < $1.id }.suffix(Self.maximumSamples))
    guard let data = try? JSONEncoder().encode(bounded) else { return false }
    defaults.set(data, forKey: Self.key)
    return true
  }

  func clear() {
    defaults.removeObject(forKey: Self.key)
  }
}
