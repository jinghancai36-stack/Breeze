import Darwin
import Foundation

public protocol HardwareMonitoring: Sendable {
  func detectHardware() throws -> MacHardware
  func discoverFans() throws -> [FanState]
  func readTemperatures() throws -> [ThermalSensor]
  func snapshot() throws -> HardwareSnapshot
}

public enum ControlCapability {
  public static func isVerified(modelIdentifier: String, fanCount: Int) -> Bool {
    modelIdentifier == "MacBookPro18,3" && fanCount == 2
  }
}

public final class HardwareMonitor: HardwareMonitoring, @unchecked Sendable {
  private let smc: SMCConnection

  public init() throws {
    smc = try SMCConnection()
  }

  public func detectHardware() throws -> MacHardware {
    let model = Self.sysctlString("hw.model")
    let fanCount = try readFanCount()
    return MacHardware(
      modelIdentifier: model,
      chipName: Self.sysctlString("machdep.cpu.brand_string"),
      architecture: Self.sysctlString("hw.machine"),
      fanCount: fanCount,
      isControlVerified: ControlCapability.isVerified(
        modelIdentifier: model,
        fanCount: fanCount
      )
    )
  }

  public func discoverFans() throws -> [FanState] {
    let count = try readFanCount()
    return try (0..<count).map { index in
      let actual = try readRPM(key: "F\(index)Ac")
      let minimum = try? readRPM(key: "F\(index)Mn")
      let maximum = try? readRPM(key: "F\(index)Mx")
      return FanState(
        id: index,
        currentRPM: actual,
        minimumRPM: minimum,
        maximumRPM: maximum
      )
    }
  }

  public func readTemperatures() throws -> [ThermalSensor] {
    let model = Self.sysctlString("hw.model")
    var readings: [ThermalSensor] = []
    var seen = Set<String>()

    for definition in SensorCatalog.definitions(for: model)
    where seen.insert(definition.key).inserted {
      guard let value = try? smc.read(definition.key),
        let temperature = SMCDataFormat.temperature(from: value.bytes, type: value.type),
        SMCDataFormat.isPlausibleTemperature(temperature)
      else { continue }

      readings.append(
        ThermalSensor(
          id: definition.key,
          name: definition.name,
          temperature: temperature,
          category: definition.category
        )
      )
    }
    return readings
  }

  public func snapshot() throws -> HardwareSnapshot {
    let hardware = try detectHardware()
    return HardwareSnapshot(
      hardware: hardware,
      fans: try discoverFans(),
      sensors: try readTemperatures()
    )
  }

  private func readFanCount() throws -> Int {
    let value = try smc.read("FNum")
    guard let count = SMCDataFormat.uint8(from: value.bytes) else {
      throw BreezeHardwareError.invalidValue("FNum")
    }
    return Int(count)
  }

  private func readRPM(key: String) throws -> Double {
    let value = try smc.read(key)
    guard let rpm = SMCDataFormat.fanRPM(from: value.bytes, size: value.size),
      rpm.isFinite,
      rpm >= 0,
      rpm < 20_000
    else {
      throw BreezeHardwareError.invalidValue(key)
    }
    return rpm
  }

  private static func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "Unknown" }
    var bytes = [UInt8](repeating: 0, count: size)
    guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "Unknown" }
    return String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? "Unknown"
  }
}
