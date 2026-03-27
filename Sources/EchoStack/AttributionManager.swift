//
//  AttributionManager.swift
//  EchoStack iOS SDK
//
//  Handles install ping, caches attribution result, manages SKAN conversion values.
//
//  NOTE: Deterministic attribution (click ID matching via fbclid/gclid/ttclid) happens
//  entirely server-side. The redirect service captures click IDs when users tap ad links,
//  stores them in Redis/PostgreSQL, and the matching engine correlates them with install
//  pings using the device fingerprint. The SDK's role is to provide the device fingerprint
//  and (optionally) the Apple attribution token — it does not perform matching on-device.
//

import Foundation
import StoreKit

#if canImport(AdServices)
import AdServices
#endif

final class AttributionManager: @unchecked Sendable {

    private let deviceManager: DeviceManager
    private let networkClient: NetworkClient
    private let configuration: Configuration

    /// Cached attribution result, available after install ping completes.
    private(set) var cachedAttribution: [String: Any]?

    /// SKAN conversion value mapping from server.
    private var conversionValueMapping: [String: Int] = [:]

    private let cacheKey = "echostack_attribution_cache"
    private let mappingKey = "echostack_cv_mapping"

    init(deviceManager: DeviceManager, networkClient: NetworkClient, configuration: Configuration) {
        self.deviceManager = deviceManager
        self.networkClient = networkClient
        self.configuration = configuration

        // Load cached attribution from UserDefaults
        if let cached = UserDefaults.standard.dictionary(forKey: cacheKey) {
            self.cachedAttribution = cached
        }

        // Load cached CV mapping
        if let mapping = UserDefaults.standard.dictionary(forKey: mappingKey) as? [String: Int] {
            self.conversionValueMapping = mapping
        }
    }

    // MARK: - Install Ping

    /// Send install ping to server. Called on every cold start; server handles dedup.
    func sendInstallPing() async {
        let fingerprint = deviceManager.collectFingerprint()

        var payload: [String: Any] = [
            "echostack_id": deviceManager.echoStackId,
            "fingerprint": fingerprint,
        ]

        // Include Apple attribution token if available
        if let token = await fetchAppleAttributionToken() {
            payload["apple_attribution_token"] = token
        }

        Logger.shared.debug("Sending install ping...")

        guard let response = await networkClient.sendInstallPing(payload: payload) else {
            Logger.shared.warning("Install ping failed — will retry on next cold start")
            return
        }

        // Cache attribution
        if let attribution = response["attribution"] as? [String: Any] {
            cachedAttribution = attribution
            UserDefaults.standard.set(attribution, forKey: cacheKey)
            Logger.shared.debug("Attribution received: \(attribution["match_type"] ?? "unknown")")
        }

        // Cache conversion value mapping
        if let mapping = response["conversion_value_mapping"] as? [String: Int] {
            conversionValueMapping = mapping
            UserDefaults.standard.set(mapping, forKey: mappingKey)
        }
    }

    // MARK: - SKAdNetwork

    /// Update SKAdNetwork conversion value for a given event type.
    func updateConversionValue(for eventType: String) {
        guard let value = conversionValueMapping[eventType] else { return }

        if #available(iOS 16.1, *) {
            // SKAN 4.0 — fine + coarse value
            SKAdNetwork.updatePostbackConversionValue(value, coarseValue: .high, lockWindow: false) { error in
                if let error = error {
                    Logger.shared.error("SKAN 4.0 update failed: \(error.localizedDescription)")
                }
            }
        } else if #available(iOS 15.4, *) {
            SKAdNetwork.updatePostbackConversionValue(value) { error in
                if let error = error {
                    Logger.shared.error("SKAN update failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Apple Attribution Token (AdServices)

    /// Fetch the Apple Search Ads attribution token via the AdServices framework (iOS 14.3+).
    /// The token is sent to the backend as `apple_attribution_token` in the install ping.
    /// The backend exchanges this token with Apple's Attribution API to get campaign-level data.
    ///
    /// We do NOT read from the clipboard — that approach is deprecated, creates bad UX
    /// (iOS shows a paste permission prompt), and is unnecessary with AdServices available.
    private func fetchAppleAttributionToken() async -> String? {
        #if canImport(AdServices)
        guard #available(iOS 14.3, *) else { return nil }

        do {
            let token = try AAAttribution.attributionToken()
            Logger.shared.debug("Obtained Apple attribution token (\(token.prefix(20))...)")
            return token
        } catch {
            Logger.shared.debug("AdServices attribution token unavailable: \(error.localizedDescription)")
            return nil
        }
        #else
        Logger.shared.debug("AdServices framework not available on this platform")
        return nil
        #endif
    }
}
