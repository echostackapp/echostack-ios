//
//  Logger.swift
//  EchoStack iOS SDK
//
//  Internal logger with configurable level. No console output in production by default.
//

import Foundation

final class Logger: @unchecked Sendable {

    static let shared = Logger()

    var level: EchoStackLogLevel = .none

    private let prefix = "[EchoStack]"

    private init() {}

    func debug(_ message: String) {
        guard level.rawValue >= EchoStackLogLevel.debug.rawValue else { return }
        print("\(prefix) DEBUG: \(message)")
    }

    func warning(_ message: String) {
        guard level.rawValue >= EchoStackLogLevel.warning.rawValue else { return }
        print("\(prefix) WARNING: \(message)")
    }

    func error(_ message: String) {
        guard level.rawValue >= EchoStackLogLevel.error.rawValue else { return }
        print("\(prefix) ERROR: \(message)")
    }
}
