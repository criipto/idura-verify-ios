// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "IduraVerify",
  platforms: [
    .iOS("17.4"), .macOS("14.4"),
  ],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "IduraVerify",
      targets: ["IduraVerify"],
    )
  ],
  dependencies: [
    .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.62.2"),
    .package(url: "https://github.com/openid/AppAuth-ios", exact: "2.0.0"),
    .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift.git", from: "2.0.0"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.0.0"),
    .package(url: "https://github.com/mhayes853/swift-uuidv7", from: "0.1.0", traits: []),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "IduraVerify",
      dependencies: [
        .product(name: "AppAuth", package: "AppAuth-ios"),
        .product(name: "JWTKit", package: "jwt-kit"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetryConcurrency", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetryProtocolExporterHTTP", package: "opentelemetry-swift"),
        .product(name: "ResourceExtension", package: "opentelemetry-swift"),
        .product(name: "UUIDV7", package: "swift-uuidv7"),
      ],
    ),
    .testTarget(
      name: "IduraVerifyTests",
      dependencies: ["IduraVerify"]
    ),
  ],
)
