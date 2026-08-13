import Darwin
import Foundation
import IOKit

private enum RestoreSMCCommand: UInt8 {
  case readBytes = 5
  case writeBytes = 6
  case readKeyInfo = 9
}

private struct RestoreSMCParamStruct {
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

/// The helper's deliberately narrow AppleSMC connection. Its typed surface
/// accepts only the two verified fans, their fixed mode/target keys, and the
/// automatic-restore keys; raw SMC operations remain private.
final class SMCRestoreConnection: ManualFanHardware {
  let modelIdentifier: String
  var isPrivileged: Bool { geteuid() == 0 }

  private let connection: io_connect_t

  init() throws {
    modelIdentifier = Self.sysctlString("hw.model") ?? "unknown"
    connection = try Self.openConnection()
  }

  deinit {
    IOServiceClose(connection)
  }

  func fanCount() throws -> Int {
    Int(try readRawByte("FNum"))
  }

  func readByte(_ key: AutomaticControlKey) throws -> UInt8 {
    try readRawByte(key.smcName)
  }

  func readForceTest() throws -> UInt8? {
    do {
      return try readRawByte(AutomaticControlKey.forceTest.smcName)
    } catch AutomaticControlError.firmware(132) {
      // The force-test latch is absent on the verified M1 Pro firmware.
      return nil
    }
  }

  func writeZero(_ key: AutomaticControlKey) throws {
    try writeRaw(key.smcName, bytes: [0])
  }

  func currentRPM(for fan: VerifiedFan) throws -> Float {
    try readRawFloat(fanKey(fan, suffix: "Ac"))
  }

  func minimumRPM(for fan: VerifiedFan) throws -> Float {
    try readRawFloat(fanKey(fan, suffix: "Mn"))
  }

  func maximumRPM(for fan: VerifiedFan) throws -> Float {
    try readRawFloat(fanKey(fan, suffix: "Mx"))
  }

  func targetRPM(for fan: VerifiedFan) throws -> Float {
    try readRawFloat(fanKey(fan, suffix: "Tg"))
  }

  func mode(for fan: VerifiedFan) throws -> UInt8 {
    try readRawByte(fanKey(fan, suffix: "Md"))
  }

  func writeManualMode(for fan: VerifiedFan) throws {
    try writeRaw(fanKey(fan, suffix: "Md"), bytes: [1])
  }

  func writeAutomaticMode(for fan: VerifiedFan) throws {
    try writeRaw(fanKey(fan, suffix: "Md"), bytes: [0])
  }

  func writeTargetRPM(_ rpm: Float, for fan: VerifiedFan) throws {
    var rpm = rpm
    let bytes = withUnsafeBytes(of: &rpm) { Array($0) }
    try writeRaw(fanKey(fan, suffix: "Tg"), bytes: bytes)
  }

  func writeTargetRPMInWorker(_ rpm: Float, for fan: VerifiedFan) throws {
    guard isPrivileged else { throw AutomaticControlError.notPrivileged }
    guard let executable = Bundle.main.executableURL else {
      throw ManualFanError.workerFailed("Helper executable is unavailable.")
    }
    let task = Process()
    task.executableURL = executable
    task.arguments = ["--internal-target-worker", "\(fan.rawValue)", "\(rpm)"]
    let errorPipe = Pipe()
    task.standardOutput = Pipe()
    task.standardError = errorPipe
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == EXIT_SUCCESS else {
      let detail = String(
        data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
      )?.trimmingCharacters(in: .whitespacesAndNewlines)
      throw ManualFanError.workerFailed(detail?.isEmpty == false ? detail! : "exit \(task.terminationStatus)")
    }
  }

  func resetTargetRPM(for fan: VerifiedFan) throws {
    try writeRaw(fanKey(fan, suffix: "Tg"), bytes: [0, 0, 0, 0])
  }

  private func readRawByte(_ name: String) throws -> UInt8 {
    let info = try keyInfo(name)
    guard info.dataSize == 1 else { throw AutomaticControlError.invalidValue(name) }
    var input = RestoreSMCParamStruct()
    input.key = try Self.fourCharCode(name)
    input.keyInfo.dataSize = info.dataSize
    input.data8 = RestoreSMCCommand.readBytes.rawValue
    let output = try call(input)
    guard output.result == 0 else { throw AutomaticControlError.firmware(output.result) }
    return withUnsafeBytes(of: output.bytes) { $0[0] }
  }

  private func readRawFloat(_ name: String) throws -> Float {
    let info = try keyInfo(name)
    guard info.dataSize == 4 else { throw AutomaticControlError.invalidValue(name) }
    var input = RestoreSMCParamStruct()
    input.key = try Self.fourCharCode(name)
    input.keyInfo.dataSize = info.dataSize
    input.data8 = RestoreSMCCommand.readBytes.rawValue
    let output = try call(input)
    guard output.result == 0 else { throw AutomaticControlError.firmware(output.result) }
    return withUnsafeBytes(of: output.bytes) { $0.loadUnaligned(as: Float.self) }
  }

  private func writeRaw(_ name: String, bytes: [UInt8]) throws {
    let info = try keyInfo(name)
    guard info.dataSize == bytes.count, bytes.count <= 32 else {
      throw AutomaticControlError.invalidValue(name)
    }
    var input = RestoreSMCParamStruct()
    input.key = try Self.fourCharCode(name)
    input.keyInfo.dataSize = info.dataSize
    input.data8 = RestoreSMCCommand.writeBytes.rawValue
    withUnsafeMutableBytes(of: &input.bytes) { buffer in
      buffer.copyBytes(from: bytes)
    }
    let output = try call(input)
    guard output.result == 0 else { throw AutomaticControlError.firmware(output.result) }
  }

  private func fanKey(_ fan: VerifiedFan, suffix: String) -> String {
    "F\(fan.rawValue)\(suffix)"
  }

  private func keyInfo(_ name: String) throws -> RestoreSMCParamStruct.KeyInfo {
    var input = RestoreSMCParamStruct()
    input.key = try Self.fourCharCode(name)
    input.data8 = RestoreSMCCommand.readKeyInfo.rawValue
    let output = try call(input)
    guard output.result == 0 else { throw AutomaticControlError.firmware(output.result) }
    return output.keyInfo
  }

  private func call(_ input: RestoreSMCParamStruct) throws -> RestoreSMCParamStruct {
    var input = input
    var output = RestoreSMCParamStruct()
    var outputSize = MemoryLayout<RestoreSMCParamStruct>.stride
    let result = IOConnectCallStructMethod(
      connection, 2, &input, MemoryLayout<RestoreSMCParamStruct>.stride, &output, &outputSize)
    guard result == kIOReturnSuccess else { throw AutomaticControlError.ioKit(result) }
    return output
  }

  private static func fourCharCode(_ string: String) throws -> UInt32 {
    guard string.utf8.count == 4 else { throw AutomaticControlError.invalidKey(string) }
    return string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
  }

  private static func openConnection() throws -> io_connect_t {
    guard let matching = IOServiceMatching("AppleSMC") else {
      throw AutomaticControlError.appleSMCUnavailable
    }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard service != 0 else { throw AutomaticControlError.appleSMCUnavailable }
    defer { IOObjectRelease(service) }

    var opened: io_connect_t = 0
    let result = IOServiceOpen(service, mach_task_self_, 0, &opened)
    guard result == kIOReturnSuccess else { throw AutomaticControlError.ioKit(result) }
    return opened
  }

  private static func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
  }
}
