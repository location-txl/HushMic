// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "HushMic",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "HushMic", targets: ["HushMic"])
  ],
  targets: [
    .executableTarget(
      name: "HushMic",
      exclude: ["Resources"],
      linkerSettings: [
        .linkedFramework("ApplicationServices"),
        .linkedFramework("CoreServices"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("ServiceManagement")
      ]
    )
  ]
)
