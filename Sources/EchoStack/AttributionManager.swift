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
//  and IDFA (when authorized) — it does not perform matching on-device.
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
    private let advertisingManager: AdvertisingManager?

    /// Cached attribution result, available after install ping completes.
    private(set) var cachedAttribution: [String: Any]?

    /// SKAN conversion value mapping from server.
    private var conversionValueMapping: [String: Int] = [:]

    /// Apple Ads attribution token fetched via AdServices.
    private(set) var appleAttributionToken: String?

    /// Whether Apple Ads attribution has been enabled.
    private var appleAdsEnabled = false

    private let cacheKey = "echostack_attribution_cache"
    private let mappingKey = "echostack_cv_mapping"

    init(
        deviceManager: DeviceManager,
        networkClient: NetworkClient,
        configuration: Configuration,
        advertisingManager: AdvertisingManager? = nil
    ) {
        self.deviceManager = deviceManager
        self.networkClient = networkClient
        self.configuration = configuration
        self.advertisingManager = advertisingManager

        // Load cached attribution from UserDefaults
        if let cached = UserDefaults.standard.dictionary(forKey: cacheKey) {
            self.cachedAttribution = cached
        }

        // Load cached CV mapping
        if let mapping = UserDefaults.standard.dictionary(forKey: mappingKey) as? [String: Int] {
            self.conversionValueMapping = mapping
        }
    }

    // MARK: - Apple Ads Attribution (AdServices)

    /// Enable Apple Ads attribution. Fetches the AdServices attribution token on iOS 14.3+.
    func enableAppleAdsAttribution() {
        appleAdsEnabled = true
        fetchAppleAttributionToken()
    }

    /// Fetch Apple Ads attribution token via AdServices framework.
    /// Fails silently when AdServices is unavailable or the call errors.
    private func fetchAppleAttributionToken() {
        #if canImport(AdServices)
        if #available(iOS 14.3, *) {
            do {
                let token = try AAAttribution.attributionToken()
                appleAttributionToken = token
                Logger.shared.debug("Apple Ads attribution token fetched (\(token.prefix(16))...)")
            } catch {
                Logger.shared.warning("Failed to fetch Apple Ads attribution token: \(error.localizedDescription)")
            }
        } else {
            Logger.shared.debug("AdServices requires iOS 14.3+ — skipping Apple Ads attribution")
        }
        #else
        Logger.shared.debug("AdServices framework not available — skipping Apple Ads attribution")
        #endif
    }

    // MARK: - Install Ping

    /// Send install ping to server. Called on every cold start; server handles dedup.
    func sendInstallPing() async {
        // If Apple Ads is enabled but token not yet fetched, try once more before sending
        if appleAdsEnabled && appleAttributionToken == nil {
            fetchAppleAttributionToken()
        }

        let fingerprint = deviceManager.collectFingerprint()

        var payload: [String: Any] = [
            "echostack_id": deviceManager.echoStackId,
            "fingerprint": fingerprint,
        ]

        // Include IDFA when ATT is authorized (already in fingerprint, also top-level for convenience)
        if let idfa = advertisingManager?.idfa {
            payload["idfa"] = idfa
            Logger.shared.debug("Including IDFA in install ping")
        }

        // Include Apple Ads attribution token when available
        if let token = appleAttributionToken {
            payload["apple_attribution_token"] = token
            Logger.shared.debug("Including Apple Ads attribution token in install ping")
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

}
