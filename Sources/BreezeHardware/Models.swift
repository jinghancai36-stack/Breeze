import Foundation

public struct MacHardware: Codable, Equatable, Sendable {
  public let modelIdentifier: String
  public let chipName: String
  public let architecture: String
  public let fanCount: Int
  public let isControlVerified: Bool

  public init(
    modelIdentifier: String,
    chipName: String,
    architecture: String,
    fanCount: Int,
    isControlVerified: Bool
  ) {
    self.modelIdentifier = modelIdentifier
    self.chipName = chipName
    self.architecture = architecture
    self.fanCount = fanCount
    self.isControlVerified = isControlVerified
  }
}

public struct FanState: Codable, Equatable, Identifiable, Sendable {
  public let id: Int
  public let currentRPM: Double
  public let minimumRPM: Double?
  public let maximumRPM: Double?

  public init(id: Int, currentRPM: Double, minimumRPM: Double?, maximumRPM: Double?) {
    self.id = id
    self.currentRPM = currentRPM
    self.minimumRPM = minimumRPM
    self.maximumRPM = maximumRPM
  }
}

public enum SensorCategory: String, Codable, CaseIterable, Sendable {
  case cpu
  case gpu
  case memory
  case system
}

public struct ThermalSensor: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let temperature: Double
  public let category: SensorCategory

  public init(id: String, name: String, temperature: Double, category: SensorCategory) {
    self.id = id
    self.name = name
    self.temperature = temperature
    self.category = category
  }
}

public struct HardwareSnapshot: Codable, Equatable, Sendable {
  public let capturedAt: Date
  public let hardware: MacHardware
  public let fans: [FanState]
  public let sensors: [ThermalSensor]

  public init(
    capturedAt: Date = Date(),
    hardware: MacHardware,
    fans: [FanState],
    sensors: [ThermalSensor]
  ) {
    self.capturedAt = capturedAt
    self.hardware = hardware
    self.fans = fans
    self.sensors = sensors
  }

  public func hottestTemperature(in category: SensorCategory) -> ThermalSensor? {
    sensors
      .filter { $0.category == category }
      .max { $0.temperature < $1.temperature }
  }

  public var batteryTemperature: ThermalSensor? {
    sensors.first { $0.id == "TB1T" }
  }

  public var primaryTemperature: ThermalSensor? {
    hottestTemperature(in: .cpu)
      ?? hottestTemperature(in: .gpu)
      ?? hottestTemperature(in: .memory)
      ?? batteryTemperature
  }
}

public enum BreezeHardwareError: LocalizedError, Equatable, Sendable {
  case appleSMCUnavailable
  case connectionFailed(Int32)
  case invalidKey(String)
  case ioKit(Int32)
  case firmware(UInt8)
  case invalidValue(String)

  public var errorDescription: String? {
    switch self {
    case .appleSMCUnavailable:
      "AppleSMC is unavailable on this Mac."
    case .connectionFailed:
      "Unable to open a read-only AppleSMC connection."
    case .invalidKey(let key):
      "Invalid SMC key: \(key)."
    case .ioKit:
      "Unable to read hardware state through IOKit."
    case .firmware:
      "The requested sensor is unavailable."
    case .invalidValue(let key):
      "The value returned for \(key) is invalid."
    }
  }
}

public enum MonitoringPolicy {
  public static let visibleRefreshInterval: TimeInterval = 1
  public static let backgroundRefreshInterval: TimeInterval = 5

  public static func refreshInterval(isPopoverVisible: Bool) -> TimeInterval {
    isPopoverVisible ? visibleRefreshInterval : backgroundRefreshInterval
  }
}
