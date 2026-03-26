//
//  NetworkClient.swift
//  EchoStack iOS SDK
//
//  URLSession wrapper with auth headers, retry logic, and JSON handling.
//

import Foundation

final class NetworkClient: @unchecked Sendable {

    private let configuration: Configuration
    private let session: URLSession
    private let maxRetries = 3
    private let retryDelays: [TimeInterval] = [1.0, 3.0, 9.0]

    init(configuration: Configuration) {
        self.configuration = configuration

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public Methods

    /// Send install ping. Returns parsed response or nil on failure.
    func sendInstallPing(payload: [String: Any]) async -> [String: Any]? {
        return await postJSON(url: configuration.installURL, payload: payload)
    }

    /// Send batched events. Returns parsed response or nil on failure.
    func sendEvents(payload: [String: Any]) async -> [String: Any]? {
        return await postJSON(url: configuration.eventsURL, payload: payload)
    }

    // MARK: - Private

    private func postJSON(url: URL, payload: [String: Any]) async -> [String: Any]? {
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            Logger.shared.error("Failed to serialize JSON payload")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")

        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.shared.error("Invalid response type")
                    continue
                }

                // 401 = invalid API key → disable SDK
                if httpResponse.statusCode == 401 {
                    Logger.shared.error("Invalid API key (401). Disabling SDK.")
                    EchoStack.shared.disable()
                    return nil
                }

                // Success
                if (200..<300).contains(httpResponse.statusCode) {
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    return json
                }

                // 429 / 5xx → retry
                if httpResponse.statusCode == 429 || httpResponse.statusCode >= 500 {
                    Logger.shared.warning("Server error \(httpResponse.statusCode), attempt \(attempt + 1)/\(maxRetries)")
                    if attempt < maxRetries - 1 {
                        try await Task.sleep(nanoseconds: UInt64(retryDelays[attempt] * 1_000_000_000))
                    }
                    continue
                }

                // 4xx (not 401/429) → don't retry
                Logger.shared.error("Request failed with status \(httpResponse.statusCode)")
                return nil

            } catch {
                Logger.shared.error("Network error: \(error.localizedDescription), attempt \(attempt + 1)/\(maxRetries)")
                if attempt < maxRetries - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(retryDelays[attempt] * 1_000_000_000))
                }
            }
        }

        Logger.shared.error("All \(maxRetries) retry attempts exhausted")
        return nil
    }
}
