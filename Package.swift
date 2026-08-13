// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Breeze",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "BreezeIPC", targets: ["BreezeIPC"]),
    .library(name: "BreezeHardware", targets: ["BreezeHardware"]),
    .executable(name: "breeze-hardware", targets: ["BreezeCLI"]),
    .executable(name: "Breeze", targets: ["BreezeApp"]),
  ],
  targets: [
    .target(
      name: "BreezeIPC",
      linkerSettings: [.linkedFramework("Security")]
    ),
    .target(
      name: "BreezeHardware",
      linkerSettings: [.linkedFramework("IOKit")]
    ),
    .executableTarget(
      name: "BreezeCLI",
      dependencies: ["BreezeHardware"]
    ),
    .executableTarget(
      name: "BreezeApp",
      dependencies: ["BreezeHardware", "BreezeIPC"]
    ),
    .executableTarget(
      name: "BreezeHelper",
      dependencies: ["BreezeIPC"],
      linkerSettings: [.linkedFramework("IOKit")]
    ),
    .testTarget(
      name: "BreezeHardwareTests",
      dependencies: ["BreezeHardware"]
    ),
    .testTarget(
      name: "BreezeAppTests",
      dependencies: ["BreezeApp", "BreezeHardware", "BreezeIPC", "BreezeHelper"]
    ),
  ]
)
