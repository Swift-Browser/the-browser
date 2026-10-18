// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "MedusaImportCore",
  platforms: [.macOS(.v14)],
  products: [.library(name: "MedusaImportCore", targets: ["MedusaImportCore"])],
  targets: [
    .target(name: "MedusaImportCore", path: "ios/Core", linkerSettings: [.linkedLibrary("sqlite3")]),
    .testTarget(
      name: "MedusaImportCoreTests",
      dependencies: ["MedusaImportCore"],
      path: "tests"
    ),
  ]
)
