import Foundation

public enum SMCDataFormat {
  /// Apple Silicon sensors can report low sentinel-like values while a block is power-gated.
  /// Temperatures below 10 °C are not credible for the supported, running MacBook baseline.
  public static func isPlausibleTemperature(_ value: Double) -> Bool {
    value.isFinite && (10...125).contains(value)
  }

  public static func fanRPM(from bytes: [UInt8], size: UInt32) -> Double? {
    if size == 4, bytes.count >= 4 {
      let value = bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
      return value.isFinite ? Double(value) : nil
    }
    guard bytes.count >= 2 else { return nil }
    return Double(uint16(from: bytes)) / 4.0
  }

  public static func temperature(from bytes: [UInt8], type: String) -> Double? {
    if type == "flt ", bytes.count >= 4 {
      let value = bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
      return value.isFinite ? Double(value) : nil
    }
    if type == "sp78", bytes.count >= 2 {
      let raw = Int16(bitPattern: uint16(from: bytes))
      return Double(raw) / 256.0
    }
    if bytes.count >= 4 {
      let value = bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
      return value.isFinite ? Double(value) : nil
    }
    return nil
  }

  public static func uint8(from bytes: [UInt8]) -> UInt8? {
    bytes.first
  }

  public static func uint16(from bytes: [UInt8]) -> UInt16 {
    guard bytes.count >= 2 else { return 0 }
    return bytes.withUnsafeBytes {
      UInt16(bigEndian: $0.loadUnaligned(as: UInt16.self))
    }
  }
}
