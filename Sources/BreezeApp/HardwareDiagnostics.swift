import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if canImport(BreezeHardware)
  import BreezeHardware
#endif

struct HardwareDiagnosticReport: Codable, Equatable {
  struct Application: Codable, Equatable {
    let version: String
    let build: String
  }

  struct OperatingSystem: Codable, Equatable {
    let version: String
    let description: String
  }

  struct Helper: Codable, Equatable {
    let registration: String
    let connectedVersion: String?
  }

  struct AutomaticControl: Codable, Equatable {
    let isVerifiedAutomatic: Bool?
    let fanModes: [Int]?
    let forceTest: Int?
  }

  struct CurvePoint: Codable, Equatable {
    let temperatureCelsius: Int
    let fanPercent: Int
  }

  struct Curve: Codable, Equatable {
    let enabled: Bool
    let sensorSource: String
    let points: [CurvePoint]
    let hysteresisCelsius: Double
    let decreaseDelaySeconds: Double
    let activeMode: String
  }

  let schemaVersion: Int
  let generatedAt: Date
  let privacyNotice: String
  let application: Application
  let operatingSystem: OperatingSystem
  let snapshot: HardwareSnapshot
  let helper: Helper
  let automaticControl: AutomaticControl
  let curve: Curve

  func encodedData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }

  func suggestedFilename() -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let model = snapshot.hardware.modelIdentifier.unicodeScalars.map {
      allowed.contains($0) ? Character(String($0)) : "-"
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "Breeze-Hardware-\(String(model))-\(formatter.string(from: generatedAt)).json"
  }
}

extension AppState {
  func makeHardwareDiagnosticReport(
    generatedAt: Date = Date(),
    applicationVersion: String? = nil,
    buildNumber: String? = nil,
    operatingSystemVersion: OperatingSystemVersion? = nil,
    operatingSystemDescription: String? = nil
  ) -> HardwareDiagnosticReport? {
    guard let snapshot else { return nil }

    let bundle = Bundle.main
    let processInfo = ProcessInfo.processInfo
    let osVersion = operatingSystemVersion ?? processInfo.operatingSystemVersion
    let version =
      applicationVersion
      ?? bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
    let build =
      buildNumber
      ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
      ?? "Local"

    return HardwareDiagnosticReport(
      schemaVersion: 1,
      generatedAt: generatedAt,
      privacyNotice:
        "This report excludes serial numbers, hostnames, user or account names, filesystem paths, logs, passwords, certificates, and signing identities.",
      application: .init(version: version, build: build),
      operatingSystem: .init(
        version: "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)",
        description: operatingSystemDescription ?? processInfo.operatingSystemVersionString),
      snapshot: snapshot,
      helper: .init(
        registration: helperStatus.reportValue,
        connectedVersion: helperVersion),
      automaticControl: .init(
        isVerifiedAutomatic: automaticControlStatus?.isAutomatic,
        fanModes: automaticControlStatus?.fanModes,
        forceTest: automaticControlStatus?.forceTest),
      curve: .init(
        enabled: isFanCurveEnabled,
        sensorSource: fanCurveConfiguration.sensorSource.rawValue,
        points: fanCurveConfiguration.points.map {
          .init(temperatureCelsius: $0.temperature, fanPercent: $0.fanPercent)
        },
        hysteresisCelsius: fanCurveConfiguration.hysteresis,
        decreaseDelaySeconds: fanCurveConfiguration.decreaseDelaySeconds,
        activeMode: activeControlMode.rawValue))
  }
}

extension HelperRegistrationStatus {
  fileprivate var reportValue: String {
    switch self {
    case .notRegistered: "notRegistered"
    case .enabled: "enabled"
    case .requiresApproval: "requiresApproval"
    case .notFound: "notFound"
    }
  }
}

@MainActor
enum HardwareDiagnosticExporter {
  static func export(
    _ report: HardwareDiagnosticReport,
    presentingWindow: NSWindow?,
    completion: @escaping (Result<URL, Error>?) -> Void
  ) {
    let panel = NSSavePanel()
    panel.title = L10n.text("diagnostics.exportTitle", fallback: "Export Hardware Diagnostics")
    panel.nameFieldStringValue = report.suggestedFilename()
    panel.allowedContentTypes = [.json]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false

    let response: (NSApplication.ModalResponse) -> Void = { result in
      guard result == .OK, let destination = panel.url else {
        completion(nil)
        return
      }
      do {
        try report.encodedData().write(to: destination, options: .atomic)
        completion(.success(destination))
      } catch {
        completion(.failure(error))
      }
    }

    if let presentingWindow {
      panel.beginSheetModal(for: presentingWindow, completionHandler: response)
    } else {
      panel.begin(completionHandler: response)
    }
  }
}

struct DiagnosticReportActionsView: View {
  @ObservedObject var state: AppState
  @State private var feedback: ExportFeedback?

  private static let feedbackURL = URL(
    string:
      "https://github.com/jinghancai36-stack/Breeze/issues/new?template=hardware_compatibility.yml"
  )!

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Button {
          exportReport()
        } label: {
          Label(
            L10n.text("diagnostics.export", fallback: "Export Diagnostic Report…"),
            systemImage: "square.and.arrow.up")
        }
        .disabled(state.snapshot == nil)
        .accessibilityIdentifier("exportHardwareDiagnostics")

        Link(destination: Self.feedbackURL) {
          Label(
            L10n.text("diagnostics.openFeedback", fallback: "Open Model Feedback"),
            systemImage: "arrow.up.right.square")
        }
      }

      Text(
        L10n.text(
          "diagnostics.privacy",
          fallback:
            "The JSON report contains model, macOS, fan, sensor, Helper, and curve state only. It excludes serial numbers, usernames, paths, logs, and credentials."
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if let feedback {
        Text(feedback.message)
          .font(.caption)
          .foregroundStyle(feedback.isError ? .red : .secondary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func exportReport() {
    guard let report = state.makeHardwareDiagnosticReport() else {
      feedback = .init(
        message: L10n.text(
          "diagnostics.unavailable", fallback: "Wait for a hardware reading before exporting."),
        isError: true)
      return
    }
    HardwareDiagnosticExporter.export(report, presentingWindow: NSApp.keyWindow) { result in
      switch result {
      case .success(let url):
        feedback = .init(
          message: L10n.format(
            "diagnostics.exported", fallback: "Saved: %@", url.lastPathComponent),
          isError: false)
      case .failure(let error):
        feedback = .init(message: error.localizedDescription, isError: true)
      case nil:
        break
      }
    }
  }
}

private struct ExportFeedback {
  let message: String
  let isError: Bool
}
