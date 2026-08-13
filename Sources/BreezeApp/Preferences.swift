import Foundation

enum MenuBarDisplay: String, CaseIterable, Identifiable {
  case icon
  case temperature
  case rpm
  case temperatureAndRPM

  var id: String { rawValue }

  var title: String {
    switch self {
    case .icon: L10n.text("display.fanIcon", fallback: "Fan Icon")
    case .temperature: L10n.text("display.temperature", fallback: "Temperature")
    case .rpm: L10n.text("display.rpm", fallback: "RPM")
    case .temperatureAndRPM: L10n.text("display.temperatureAndRPM", fallback: "Temperature + RPM")
    }
  }

  var showsTemperature: Bool {
    self == .temperature || self == .temperatureAndRPM
  }

  var showsRPM: Bool {
    self == .rpm || self == .temperatureAndRPM
  }
}

enum PreferenceKey {
  static let menuBarDisplay = "menuBarDisplay"
}
