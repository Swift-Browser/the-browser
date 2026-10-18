// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "MedusaSyncCore",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "MedusaSyncCore", targets: ["MedusaSyncCore"]),
    .executable(name: "legacy-migration", targets: ["LegacyMigrationTool"]),
  ],
  targets: [
    .target(name: "MedusaSyncCore", path: "ios/Core"),
    .executableTarget(name: "LegacyMigrationTool", dependencies: ["MedusaSyncCore"], path: "tools/legacy-migration"),
    .testTarget(name: "MedusaSyncCoreTests", dependencies: ["MedusaSyncCore"], path: "tests", exclude: ["fixtures"]),
  ]
)
