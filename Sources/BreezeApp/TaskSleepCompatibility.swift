import Foundation

enum TaskSleepCompatibility {
  static func sleep(for interval: TimeInterval) async throws {
    let nanoseconds = UInt64(max(interval, 0) * 1_000_000_000)
    try await Task.sleep(nanoseconds: nanoseconds)
  }

  static func sleep(seconds: Int) async throws {
    try await Task.sleep(nanoseconds: UInt64(max(seconds, 0)) * 1_000_000_000)
  }

  static func sleep(milliseconds: UInt64) async throws {
    try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
  }
}
