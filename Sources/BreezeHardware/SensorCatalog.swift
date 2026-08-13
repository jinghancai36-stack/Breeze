import Foundation

struct SensorDefinition: Sendable {
  let key: String
  let name: String
  let category: SensorCategory
}

enum SensorCatalog {
  // M1/M1 Pro/M1 Max keys. Unknown models are allowed to probe these read-only.
  static let m1: [SensorDefinition] = [
    .init(key: "Tp09", name: "CPU E-core 1", category: .cpu),
    .init(key: "Tp0T", name: "CPU E-core 2", category: .cpu),
    .init(key: "Tp01", name: "CPU P-core 1", category: .cpu),
    .init(key: "Tp05", name: "CPU P-core 2", category: .cpu),
    .init(key: "Tp0D", name: "CPU P-core 3", category: .cpu),
    .init(key: "Tp0H", name: "CPU P-core 4", category: .cpu),
    .init(key: "Tp0L", name: "CPU P-core 5", category: .cpu),
    .init(key: "Tp0P", name: "CPU P-core 6", category: .cpu),
    .init(key: "Tg05", name: "GPU 1", category: .gpu),
    .init(key: "Tg0D", name: "GPU 2", category: .gpu),
    .init(key: "Tg0L", name: "GPU 3", category: .gpu),
    .init(key: "Tg0T", name: "GPU 4", category: .gpu),
    .init(key: "Tm02", name: "Memory 1", category: .memory),
    .init(key: "Tm06", name: "Memory 2", category: .memory),
  ]

  static let fallback: [SensorDefinition] = [
    .init(key: "TC0D", name: "CPU diode", category: .cpu),
    .init(key: "TC0P", name: "CPU proximity", category: .cpu),
    .init(key: "TG0D", name: "GPU diode", category: .gpu),
    .init(key: "TG0P", name: "GPU proximity", category: .gpu),
    .init(key: "TB1T", name: "Battery", category: .system),
  ]

  static func definitions(for model: String) -> [SensorDefinition] {
    if model.hasPrefix("MacBookPro18") || model.hasPrefix("MacBookAir10")
      || model.hasPrefix("Mac12")
    {
      return m1 + fallback
    }
    return fallback + m1
  }
}
