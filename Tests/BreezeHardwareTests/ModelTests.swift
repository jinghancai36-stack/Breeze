import Testing

@testable import BreezeHardware

@Suite("Hardware models")
struct ModelTests {
  @Test("Fan state supports fanless and dual-fan snapshots")
  func fanCounts() {
    let hardware = MacHardware(
      modelIdentifier: "MacBookPro18,3",
      chipName: "Apple M1 Pro",
      architecture: "arm64",
      fanCount: 2,
      isControlVerified: false
    )
    let fans = [
      FanState(id: 0, currentRPM: 1_824, minimumRPM: 0, maximumRPM: 5_776),
      FanState(id: 1, currentRPM: 1_796, minimumRPM: 0, maximumRPM: 5_776),
    ]
    #expect(HardwareSnapshot(hardware: hardware, fans: fans, sensors: []).fans.count == 2)
    #expect(HardwareSnapshot(hardware: hardware, fans: [], sensors: []).fans.isEmpty)
  }

  @Test("Manual control is verified only for the exact tested two-fan model")
  func controlCapability() {
    #expect(ControlCapability.isVerified(modelIdentifier: "MacBookPro18,3", fanCount: 2))
    #expect(!ControlCapability.isVerified(modelIdentifier: "MacBookPro18,3", fanCount: 1))
    #expect(!ControlCapability.isVerified(modelIdentifier: "MacBookPro18,4", fanCount: 2))
    #expect(!ControlCapability.isVerified(modelIdentifier: "Mac99,9", fanCount: 2))
  }

  @Test("Temperature summaries choose the hottest sensor in each category")
  func temperatureSummaries() {
    let hardware = MacHardware(
      modelIdentifier: "MacBookPro18,3",
      chipName: "Apple M1 Pro",
      architecture: "arm64",
      fanCount: 2,
      isControlVerified: false
    )
    let sensors = [
      ThermalSensor(id: "cpu1", name: "CPU 1", temperature: 54, category: .cpu),
      ThermalSensor(id: "cpu2", name: "CPU 2", temperature: 61, category: .cpu),
      ThermalSensor(id: "gpu1", name: "GPU 1", temperature: 58, category: .gpu),
      ThermalSensor(id: "TB1T", name: "Battery", temperature: 35, category: .system),
    ]
    let snapshot = HardwareSnapshot(hardware: hardware, fans: [], sensors: sensors)

    #expect(snapshot.hottestTemperature(in: .cpu)?.id == "cpu2")
    #expect(snapshot.primaryTemperature?.id == "cpu2")
    #expect(snapshot.batteryTemperature?.temperature == 35)
  }

  @Test("Monitoring policy uses fast visible and quiet background refresh")
  func monitoringPolicy() {
    #expect(MonitoringPolicy.refreshInterval(isPopoverVisible: true) == 1)
    #expect(MonitoringPolicy.refreshInterval(isPopoverVisible: false) == 5)
  }
}
