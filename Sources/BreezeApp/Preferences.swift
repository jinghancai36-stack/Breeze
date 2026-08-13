import Foundation

enum MenuBarDisplay: String, CaseIterable, Identifiable {
  case icon
  case temperature
  case rpm
  case temperatureAndRPM

  var id: String { rawValue }

  var title: String {
    switch self {
    case .icon: "Fan Icon"
    case .temperature: "Temperature"
    case .rpm: "RPM"
    case .temperatureAndRPM: "Temperature + RPM"
    }
  }
}

enum PreferenceKey {
  static let menuBarDisplay = "menuBarDisplay"
}
