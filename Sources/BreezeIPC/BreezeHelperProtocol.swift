import Foundation
import Security

public enum BreezeHelperConstants {
  public static let machServiceName = "com.cai.Breeze.Helper"
  public static let launchDaemonPlistName = "com.cai.Breeze.Helper.plist"
  public static let helperVersion = "0.11.0"

  public static func peerSigningRequirement(identifier: String) -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
      return nil
    }
    var signingInformation: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInformation)
        == errSecSuccess,
      let information = signingInformation as? [String: Any],
      let teamIdentifier = information[kSecCodeInfoTeamIdentifier as String] as? String,
      teamIdentifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
    else { return nil }

    return
      "identifier \"\(identifier)\" and anchor apple generic "
      + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
  }
}

/// The complete privileged boundary for Milestone 7 presets.
///
/// Do not add arbitrary commands, paths, SMC keys, or byte payloads here. Fan
/// Manual operations accept only a fan index and requested integer RPM. The
/// Helper independently validates hardware and clamps to detected bounds.
@objc public protocol BreezeHelperProtocol: NSObjectProtocol {
  func ping(withReply reply: @escaping (Bool) -> Void)
  func getHelperVersion(withReply reply: @escaping (String) -> Void)
  func getAutomaticControlStatus(
    withReply reply: @escaping (Bool, Int, Int, Int, String) -> Void)
  func restoreAutomaticControl(
    withReply reply: @escaping (Bool, Int, Int, Int, String) -> Void)
  func setFanRPM(
    _ fanID: Int,
    rpm: Int,
    withReply reply: @escaping (Bool, Int, Int, Int, Int, Int, Bool, Bool, String) -> Void)
  func setFanAutomatic(
    _ fanID: Int,
    withReply reply: @escaping (Bool, Int, Int, Int, Int, Int, Bool, Bool, String) -> Void)
  func applyQuietPreset(
    withReply reply: @escaping (Bool, Int, Int, Int, Int, Bool, String) -> Void)
  func applyBalancedPreset(
    withReply reply: @escaping (Bool, Int, Int, Int, Int, Bool, String) -> Void)
  func applyCoolPreset(
    withReply reply: @escaping (Bool, Int, Int, Int, Int, Bool, String) -> Void)
  func applyMaxPreset(
    withReply reply: @escaping (Bool, Int, Int, Int, Int, Bool, String) -> Void)
  func applyCurveTarget(
    _ percent: Int,
    withReply reply: @escaping (Bool, Int, Int, Int, Int, Bool, String) -> Void)
  func renewControlLease(withReply reply: @escaping (Bool, Int, String) -> Void)
  func getControlLeaseStatus(withReply reply: @escaping (Bool, Int, String) -> Void)
}
