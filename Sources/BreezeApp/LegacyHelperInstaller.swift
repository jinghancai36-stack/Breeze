import Darwin
import Foundation

#if canImport(BreezeIPC)
  import BreezeIPC
#endif

struct LegacyHelperInstaller {
  private static let helperURL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/BreezeHelper")
  private static let plistURL = URL(
    fileURLWithPath: "/Library/LaunchDaemons/\(BreezeHelperConstants.launchDaemonPlistName)")

  var status: HelperRegistrationStatus {
    guard FileManager.default.isExecutableFile(atPath: Self.helperURL.path),
      FileManager.default.fileExists(atPath: Self.plistURL.path)
    else { return .notRegistered }
    return Self.launchctl(["print", "system/\(BreezeHelperConstants.machServiceName)"])
      ? .enabled : .notRegistered
  }

  func register() throws {
    try runAuthorizedWorker("--helper-legacy-install-worker")
  }

  func unregister() throws {
    try runAuthorizedWorker("--helper-legacy-uninstall-worker")
  }

  private func runAuthorizedWorker(_ command: String) throws {
    guard let executablePath = Bundle.main.executablePath else {
      throw LegacyHelperInstallerError.missingAppExecutable
    }

    let script = """
      on run argv
        set appPath to item 1 of argv
        set workerCommand to item 2 of argv
        do shell script quoted form of appPath & " " & quoted form of workerCommand with administrator privileges
      end run
      """
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script, "--", executablePath, command]
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      throw LegacyHelperInstallerError.workerLaunchFailed
    }
    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
    let message = String(decoding: output, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let errorMessage = String(decoding: errorOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard process.terminationStatus == 0 else {
      if errorMessage.localizedCaseInsensitiveContains("User canceled") {
        throw LegacyHelperInstallerError.authorizationCancelled
      }
      throw LegacyHelperInstallerError.workerFailed(
        errorMessage.isEmpty ? "Administrator installation failed." : errorMessage)
    }
    guard message.hasPrefix("OK:") else {
      throw LegacyHelperInstallerError.workerFailed(message.isEmpty ? "No response" : message)
    }
  }

  fileprivate static func launchctl(_ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus == 0
    } catch {
      return false
    }
  }
}

enum LegacyHelperWorker {
  private static let label = BreezeHelperConstants.machServiceName
  private static let destinationHelper = URL(
    fileURLWithPath: "/Library/PrivilegedHelperTools/BreezeHelper")
  private static let destinationPlist = URL(
    fileURLWithPath: "/Library/LaunchDaemons/\(BreezeHelperConstants.launchDaemonPlistName)")

  static func install() -> (message: String, success: Bool) {
    guard geteuid() == 0 else {
      return ("ERROR: Legacy installer must run as root.", false)
    }
    guard BreezeHelperConstants.peerSigningRequirement(identifier: "com.cai.Breeze") != nil else {
      return ("ERROR: Monterey fan control requires a signed Breeze development build.", false)
    }
    let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
      .resolvingSymlinksInPath().deletingLastPathComponent()
    let sourceHelper = executableDirectory.appendingPathComponent("BreezeHelper")
    guard FileManager.default.isExecutableFile(atPath: sourceHelper.path) else {
      return ("ERROR: The app bundle does not contain BreezeHelper.", false)
    }

    do {
      let fileManager = FileManager.default
      try fileManager.createDirectory(
        at: destinationHelper.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      if fileManager.fileExists(atPath: destinationHelper.path) {
        try fileManager.removeItem(at: destinationHelper)
      }
      try fileManager.copyItem(at: sourceHelper, to: destinationHelper)
      guard chmod(destinationHelper.path, 0o755) == 0,
        chown(destinationHelper.path, 0, 0) == 0
      else { throw LegacyHelperInstallerError.permissionsFailed }

      let plist: [String: Any] = [
        "Label": label,
        "ProgramArguments": [destinationHelper.path],
        "MachServices": [label: true],
        "ProcessType": "Interactive",
        "RunAtLoad": true,
        "KeepAlive": true,
      ]
      let data = try PropertyListSerialization.data(
        fromPropertyList: plist, format: .xml, options: 0)
      try data.write(to: destinationPlist, options: .atomic)
      guard chmod(destinationPlist.path, 0o644) == 0,
        chown(destinationPlist.path, 0, 0) == 0
      else { throw LegacyHelperInstallerError.permissionsFailed }

      _ = LegacyHelperInstaller.launchctl(["bootout", "system/\(label)"])
      guard LegacyHelperInstaller.launchctl(["bootstrap", "system", destinationPlist.path]) else {
        throw LegacyHelperInstallerError.bootstrapFailed
      }
      return ("OK: Breeze Helper installed for macOS Monterey.", true)
    } catch {
      return ("ERROR: \(error.localizedDescription)", false)
    }
  }

  static func uninstall() -> (message: String, success: Bool) {
    guard geteuid() == 0 else {
      return ("ERROR: Legacy uninstaller must run as root.", false)
    }
    _ = LegacyHelperInstaller.launchctl(["bootout", "system/\(label)"])
    do {
      let fileManager = FileManager.default
      if fileManager.fileExists(atPath: destinationPlist.path) {
        try fileManager.removeItem(at: destinationPlist)
      }
      if fileManager.fileExists(atPath: destinationHelper.path) {
        try fileManager.removeItem(at: destinationHelper)
      }
      return ("OK: Breeze Helper removed from macOS Monterey.", true)
    } catch {
      return ("ERROR: \(error.localizedDescription)", false)
    }
  }
}

enum LegacyHelperInstallerError: LocalizedError {
  case missingAppExecutable
  case authorizationCancelled
  case workerLaunchFailed
  case workerFailed(String)
  case permissionsFailed
  case bootstrapFailed

  var errorDescription: String? {
    switch self {
    case .missingAppExecutable: return "Breeze could not locate its executable."
    case .authorizationCancelled: return "Administrator authorization was cancelled."
    case .workerLaunchFailed: return "The privileged Monterey installer could not start."
    case .workerFailed(let message): return message
    case .permissionsFailed: return "The Helper files could not be secured with root ownership."
    case .bootstrapFailed: return "launchd could not start Breeze Helper."
    }
  }
}
