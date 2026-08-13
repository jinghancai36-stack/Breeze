import Testing

@testable import BreezeHardware

@Suite("SMC data formats")
struct SMCDataFormatTests {
  @Test("Apple Silicon fan RPM is a native-endian float")
  func floatFanRPM() {
    var value: Float = 1_824.5
    let bytes = withUnsafeBytes(of: &value) { Array($0) }
    #expect(SMCDataFormat.fanRPM(from: bytes, size: 4) == 1_824.5)
  }

  @Test("Legacy fpe2 fan RPM is big endian")
  func fixedPointFanRPM() {
    #expect(SMCDataFormat.fanRPM(from: [0x1c, 0x80], size: 2) == 1_824)
  }

  @Test("sp78 temperature is signed big endian")
  func signedTemperature() {
    #expect(SMCDataFormat.temperature(from: [0x36, 0x80], type: "sp78") == 54.5)
  }

  @Test("Malformed values are rejected")
  func malformedValues() {
    #expect(SMCDataFormat.fanRPM(from: [], size: 4) == nil)
    #expect(SMCDataFormat.temperature(from: [], type: "flt ") == nil)
  }

  @Test("Power-gated and dangerous temperature values are rejected")
  func implausibleTemperatures() {
    #expect(!SMCDataFormat.isPlausibleTemperature(9.2))
    #expect(SMCDataFormat.isPlausibleTemperature(54))
    #expect(!SMCDataFormat.isPlausibleTemperature(126))
    #expect(!SMCDataFormat.isPlausibleTemperature(.infinity))
  }
}
