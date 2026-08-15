import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
  @Published private(set) var isEnabled = false
  @Published private(set) var requiresApproval = false
  @Published private(set) var errorMessage: String?

  init() {
    refresh()
  }

  func refresh() {
    guard #available(macOS 13.0, *) else {
      isEnabled = false
      requiresApproval = false
      return
    }
    let status = SMAppService.mainApp.status
    isEnabled = status == .enabled
    requiresApproval = status == .requiresApproval
  }

  func setEnabled(_ enabled: Bool) {
    guard #available(macOS 13.0, *) else {
      errorMessage = "Launch at Login requires macOS Ventura or newer."
      return
    }
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    refresh()
  }

  func openSystemSettings() {
    if #available(macOS 13.0, *) {
      SMAppService.openSystemSettingsLoginItems()
    }
  }
}
