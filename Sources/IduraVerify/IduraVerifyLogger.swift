import Foundation
import os

/// Severity of a log message emitted by `IduraVerify`.
public enum IduraVerifyLogLevel: Sendable {
  case debug
  case info
  case notice
  case error
}

/// Receives log messages emitted by `IduraVerify`.
///
/// Pass a custom implementation to `IduraVerify(logger:)` to route SDK logs into your app's
/// logging pipeline. If no logger is provided, the SDK logs to Apple's unified logging system
/// under the subsystem `eu.idura.verify`.
public protocol IduraVerifyLogger: Sendable {
  func log(level: IduraVerifyLogLevel, message: String)
}

extension IduraVerifyLogger {
  func debug(_ message: @autoclosure () -> String) {
    log(level: .debug, message: message())
  }
  func info(_ message: @autoclosure () -> String) {
    log(level: .info, message: message())
  }
  func notice(_ message: @autoclosure () -> String) {
    log(level: .notice, message: message())
  }
  func error(_ message: @autoclosure () -> String) {
    log(level: .error, message: message())
  }
}

struct OSLogIduraVerifyLogger: IduraVerifyLogger {
  let logger = Logger(subsystem: "eu.idura.verify", category: "IduraVerify")

  func log(level: IduraVerifyLogLevel, message: String) {
    switch level {
    case .debug: logger.debug("\(message, privacy: .public)")
    case .info: logger.info("\(message, privacy: .public)")
    case .notice: logger.notice("\(message, privacy: .public)")
    case .error: logger.error("\(message, privacy: .public)")
    }
  }
}
