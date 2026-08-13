import Foundation
import IOKit

enum SMCCommand: UInt8 {
  case readBytes = 5
  case readKeyInfo = 9
}

struct SMCParamStruct {
  typealias Bytes32 = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
  )

  struct Version {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
  }

  struct PLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
  }

  struct KeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
  }

  var key: UInt32 = 0
  var vers = Version()
  var pLimitData = PLimitData()
  var keyInfo = KeyInfo()
  var padding: UInt16 = 0
  var result: UInt8 = 0
  var status: UInt8 = 0
  var data8: UInt8 = 0
  var data32: UInt32 = 0
  var bytes: Bytes32 = (
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  )
}

struct SMCValue: Sendable {
  let bytes: [UInt8]
  let size: UInt32
  let type: String
}

/// Read-only wrapper around the AppleSMC user client.
/// This type intentionally exposes no write command or write API.
final class SMCConnection: @unchecked Sendable {
  private let connection: io_connect_t

  init() throws {
    guard let matching = IOServiceMatching("AppleSMC") else {
      throw BreezeHardwareError.appleSMCUnavailable
    }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard service != 0 else {
      throw BreezeHardwareError.appleSMCUnavailable
    }
    defer { IOObjectRelease(service) }

    var opened: io_connect_t = 0
    let result = IOServiceOpen(service, mach_task_self_, 0, &opened)
    guard result == kIOReturnSuccess else {
      throw BreezeHardwareError.connectionFailed(result)
    }
    connection = opened
  }

  deinit {
    IOServiceClose(connection)
  }

  func read(_ key: String) throws -> SMCValue {
    var infoInput = SMCParamStruct()
    infoInput.key = try Self.fourCharCode(key)
    infoInput.data8 = SMCCommand.readKeyInfo.rawValue
    let infoOutput = try call(infoInput)
    guard infoOutput.result == 0 else {
      throw BreezeHardwareError.firmware(infoOutput.result)
    }

    let size = infoOutput.keyInfo.dataSize
    guard size <= 32 else {
      throw BreezeHardwareError.invalidValue(key)
    }

    var readInput = SMCParamStruct()
    readInput.key = infoInput.key
    readInput.keyInfo.dataSize = size
    readInput.data8 = SMCCommand.readBytes.rawValue
    let readOutput = try call(readInput)
    guard readOutput.result == 0 else {
      throw BreezeHardwareError.firmware(readOutput.result)
    }

    let bytes = withUnsafeBytes(of: readOutput.bytes) {
      Array($0.prefix(Int(size)))
    }
    return SMCValue(
      bytes: bytes,
      size: size,
      type: Self.fourCharString(infoOutput.keyInfo.dataType)
    )
  }

  private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
    var input = input
    var output = SMCParamStruct()
    var outputSize = MemoryLayout<SMCParamStruct>.stride
    let result = IOConnectCallStructMethod(
      connection,
      2,
      &input,
      MemoryLayout<SMCParamStruct>.stride,
      &output,
      &outputSize
    )
    guard result == kIOReturnSuccess else {
      throw BreezeHardwareError.ioKit(result)
    }
    return output
  }

  private static func fourCharCode(_ string: String) throws -> UInt32 {
    guard string.utf8.count == 4 else {
      throw BreezeHardwareError.invalidKey(string)
    }
    return string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
  }

  private static func fourCharString(_ value: UInt32) -> String {
    let bytes = [
      UInt8((value >> 24) & 0xff),
      UInt8((value >> 16) & 0xff),
      UInt8((value >> 8) & 0xff),
      UInt8(value & 0xff),
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
  }
}
