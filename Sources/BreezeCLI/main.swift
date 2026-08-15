import BreezeHardware
import Foundation

enum Command: String {
  case info
  case fans
  case temperatures
  case watch
  case soak
  case report
  case help
}

@main
enum BreezeCLI {
  static func main() async {
    let command = Command(rawValue: CommandLine.arguments.dropFirst().first ?? "help") ?? .help
    do {
      let monitor = try HardwareMonitor()
      switch command {
      case .info:
        printHardware(try monitor.detectHardware())
      case .fans:
        printFans(try monitor.discoverFans())
      case .temperatures:
        printTemperatures(try monitor.readTemperatures())
      case .report:
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(monitor.snapshot())
        print(String(decoding: data, as: UTF8.self))
      case .watch:
        try await watch(monitor)
      case .soak:
        let duration = Int(CommandLine.arguments.dropFirst(2).first ?? "1800") ?? 1_800
        try await soak(monitor, duration: max(1, duration))
      case .help:
        printUsage()
      }
    } catch {
      FileHandle.standardError.write(Data("Breeze: \(error.localizedDescription)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
  }

  private static func soak(_ monitor: HardwareMonitor, duration: Int) async throws {
    let startedAt = Date()
    var samples = 0
    var minimumFanCount = Int.max
    var minimumSensorCount = Int.max

    print("Starting read-only soak test for \(duration) seconds…")
    while samples < duration, !Task.isCancelled {
      let snapshot = try monitor.snapshot()
      guard snapshot.hardware.fanCount == snapshot.fans.count else {
        throw BreezeHardwareError.invalidValue("fan count")
      }
      minimumFanCount = min(minimumFanCount, snapshot.fans.count)
      minimumSensorCount = min(minimumSensorCount, snapshot.sensors.count)
      samples += 1

      if samples == 1 || samples.isMultiple(of: 60) || samples == duration {
        print(
          "[\(samples)/\(duration)] fans=\(snapshot.fans.count) sensors=\(snapshot.sensors.count)")
      }
      if samples < duration {
        try await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }

    let elapsed = Date().timeIntervalSince(startedAt)
    print(
      "Soak passed: \(samples) samples in \(String(format: "%.1f", elapsed))s; minimum fans=\(minimumFanCount), minimum sensors=\(minimumSensorCount)"
    )
  }

  private static func watch(_ monitor: HardwareMonitor) async throws {
    while !Task.isCancelled {
      print("\u{001B}[2J\u{001B}[H", terminator: "")
      let snapshot = try monitor.snapshot()
      printHardware(snapshot.hardware)
      print("")
      printFans(snapshot.fans)
      print("")
      printTemperatures(snapshot.sensors)
      try await Task.sleep(nanoseconds: 1_000_000_000)
    }
  }

  private static func printHardware(_ hardware: MacHardware) {
    print("Model: \(hardware.modelIdentifier)")
    print("Chip: \(hardware.chipName)")
    print("Architecture: \(hardware.architecture)")
    print("Fans: \(hardware.fanCount)")
    print(
      "Control capability: "
        + (hardware.isControlVerified
          ? "verified for the signed Breeze app/Helper"
          : "Monitor Only on this hardware")
    )
    print("This diagnostic CLI remains read-only.")
  }

  private static func printFans(_ fans: [FanState]) {
    guard !fans.isEmpty else {
      print("No controllable fans detected.")
      return
    }
    for fan in fans {
      print("Fan \(fan.id): \(format(fan.currentRPM)) RPM")
      print("  Reported min: \(fan.minimumRPM.map(format) ?? "Unknown") RPM")
      print("  Reported max: \(fan.maximumRPM.map(format) ?? "Unknown") RPM")
    }
  }

  private static func printTemperatures(_ sensors: [ThermalSensor]) {
    guard !sensors.isEmpty else {
      print("No supported thermal sensors detected.")
      return
    }
    for sensor in sensors {
      print("\(sensor.name) [\(sensor.id)]: \(String(format: "%.1f", sensor.temperature)) °C")
    }
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.0f", value)
  }

  private static func printUsage() {
    print(
      """
      breeze-hardware — read-only Apple Silicon hardware probe

      Usage:
        breeze-hardware info
        breeze-hardware fans
        breeze-hardware temperatures
        breeze-hardware watch
        breeze-hardware soak [seconds]  # defaults to 1800 (30 minutes)
        breeze-hardware report

      This read-only diagnostic CLI contains no SMC write path.
      Fan control is available only through the signed Breeze app and Helper.
      """)
  }
}
