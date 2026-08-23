import BreezeHardware
import Foundation
import Testing

@testable import BreezeApp

@Suite("Hardware diagnostic report")
struct HardwareDiagnosticsTests {
  @Test("Report contains useful model evidence without personal identifiers")
  @MainActor
  func sanitizedReport() throws {
    let state = AppState(
      previewSnapshot: HardwareSnapshot(
        capturedAt: Date(timeIntervalSince1970: 10),
        hardware: MacHardware(
          modelIdentifier: "MacBookPro18,3",
          chipName: "Apple M1 Pro",
          architecture: "arm64",
          fanCount: 2,
          isControlVerified: true),
        fans: [
          FanState(id: 0, currentRPM: 2_321, minimumRPM: 1_200, maximumRPM: 5_779),
          FanState(id: 1, currentRPM: 2_472, minimumRPM: 1_200, maximumRPM: 6_241),
        ],
        sensors: [
          ThermalSensor(id: "Tp01", name: "CPU", temperature: 70.6, category: .cpu)
        ]))

    let report = try #require(
      state.makeHardwareDiagnosticReport(
        generatedAt: Date(timeIntervalSince1970: 0),
        applicationVersion: "0.11.0",
        buildNumber: "18",
        operatingSystemVersion: .init(majorVersion: 12, minorVersion: 0, patchVersion: 1),
        operatingSystemDescription: "macOS 12.0.1 (test build)"))

    #expect(report.schemaVersion == 1)
    #expect(report.application.version == "0.11.0")
    #expect(report.operatingSystem.version == "12.0.1")
    #expect(report.snapshot.hardware.modelIdentifier == "MacBookPro18,3")
    #expect(report.snapshot.fans.count == 2)
    #expect(report.snapshot.sensors.first?.id == "Tp01")
    #expect(report.helper.registration == "enabled")
    #expect(report.curve.mode == "automatic")
    #expect(report.curve.points.map(\.temperatureCelsius) == [45, 90])

    let json = String(decoding: try report.encodedData(), as: UTF8.self)
    #expect(json.contains("\"privacyNotice\""))
    #expect(json.contains("\"currentRPM\" : 2321"))
    #expect(!json.contains("\"serialNumber\" :"))
    #expect(!json.contains("\"hostName\" :"))
    #expect(!json.contains("\"userName\" :"))
    #expect(!json.contains("/Users/"))
  }

  @Test("Suggested filename is stable and filesystem safe")
  @MainActor
  func suggestedFilename() throws {
    let state = AppState(
      previewSnapshot: HardwareSnapshot(
        hardware: MacHardware(
          modelIdentifier: "MacBookPro18,3",
          chipName: "Apple M1 Pro",
          architecture: "arm64",
          fanCount: 2,
          isControlVerified: true),
        fans: [],
        sensors: []))
    let report = try #require(
      state.makeHardwareDiagnosticReport(
        generatedAt: Date(timeIntervalSince1970: 0),
        operatingSystemVersion: .init(majorVersion: 12, minorVersion: 0, patchVersion: 0),
        operatingSystemDescription: "macOS 12"))

    #expect(report.suggestedFilename() == "Breeze-Hardware-MacBookPro18-3-19700101-000000.json")
  }
}
