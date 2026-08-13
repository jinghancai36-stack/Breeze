import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginController {
  private(set) var isEnabled = false
  private(set) var requiresApproval = false
  private(set) var errorMessage: String?

  init() {
    refresh()
  }

  func refresh() {
    let status = SMAppService.mainApp.status
    isEnabled = status == .enabled
    requiresApproval = status == .requiresApproval
  }

  func setEnabled(_ enabled: Bool) {
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
    SMAppService.openSystemSettingsLoginItems()
  }
}
