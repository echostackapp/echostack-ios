//
//  Configuration.swift
//  EchoStack iOS SDK
//

import Foundation

struct Configuration {
    let apiKey: String
    let serverURL: String
    let logLevel: EchoStackLogLevel

    var installURL: URL {
        URL(string: "\(serverURL)/v1/sdk/install")!
    }

    var eventsURL: URL {
        URL(string: "\(serverURL)/v1/sdk/events")!
    }
}
