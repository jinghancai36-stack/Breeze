import Foundation

#if canImport(BreezeHardware)
  import BreezeHardware
#endif

enum FanCurveStage: Int, CaseIterable, Equatable, Sendable {
  case automatic
  case quiet
  case balanced
  case cool
  case max
}

enum FanCurvePolicy {
  static let balancedEntryTemperature = 60.0
  static let coolEntryTemperature = 75.0
  static let maxEntryTemperature = 88.0

  static let automaticReturnTemperature = 52.0
  static let balancedReturnTemperature = 68.0
  static let coolReturnTemperature = 82.0

  static func controlTemperature(for snapshot: HardwareSnapshot) -> Double? {
    [
      snapshot.hottestTemperature(in: .cpu)?.temperature,
      snapshot.hottestTemperature(in: .gpu)?.temperature,
    ]
    .compactMap { $0 }
    .max()
  }

  static func stage(for temperature: Double, previous: FanCurveStage) -> FanCurveStage {
    switch previous {
    case .automatic:
      if temperature >= maxEntryTemperature { return .max }
      if temperature >= coolEntryTemperature { return .cool }
      if temperature >= balancedEntryTemperature { return .balanced }
      return .quiet
    case .quiet:
      if temperature >= maxEntryTemperature { return .max }
      if temperature >= coolEntryTemperature { return .cool }
      if temperature >= balancedEntryTemperature { return .balanced }
      return .quiet
    case .balanced:
      if temperature >= maxEntryTemperature { return .max }
      if temperature >= coolEntryTemperature { return .cool }
      if temperature <= automaticReturnTemperature { return .quiet }
      return .balanced
    case .cool:
      if temperature >= maxEntryTemperature { return .max }
      if temperature < balancedReturnTemperature {
        return temperature <= automaticReturnTemperature ? .quiet : .balanced
      }
      return .cool
    case .max:
      if temperature < coolReturnTemperature {
        if temperature < balancedReturnTemperature {
          return temperature <= automaticReturnTemperature ? .quiet : .balanced
        }
        return .cool
      }
      return .max
    }
  }
}
