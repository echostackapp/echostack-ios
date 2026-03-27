//
//  AdvertisingManager.swift
//  EchoStack iOS SDK
//
//  Manages IDFA collection via AdSupport and ATT (App Tracking Transparency) authorization.
//  Never auto-prompts — the host app controls ATT prompt timing via requestTrackingAuthorization().
//

import Foundation

#if canImport(AdSupport)
import AdSupport
#endif

#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

final class AdvertisingManager: @unchecked Sendable {

    /// Returns the IDFA if tracking is authorized, nil otherwise.
    /// The all-zeros UUID indicates tracking is restricted/denied and is treated as nil.
    var idfa: String? {
        #if canImport(AdSupport)
        guard isTrackingAuthorized else { return nil }

        let identifier = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        // All-zeros means tracking is denied/restricted at the OS level
        guard identifier != "00000000-0000-0000-0000-000000000000" else { return nil }

        return identifier
        #else
        return nil
        #endif
    }

    /// Whether the user has granted ATT authorization.
    var isTrackingAuthorized: Bool {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14, *) {
            return ATTrackingManager.trackingAuthorizationStatus == .authorized
        }
        #endif
        // Pre-iOS 14: ATT doesn't exist; AdSupport is available without consent
        #if canImport(AdSupport)
        return ASIdentifierManager.shared().isAdvertisingTrackingEnabled
        #else
        return false
        #endif
    }

    /// Current ATT authorization status. Returns nil on platforms/OS versions without ATT.
    @available(iOS 14, *)
    var trackingAuthorizationStatus: ATTrackingManager.AuthorizationStatus {
        return ATTrackingManager.trackingAuthorizationStatus
    }

    // MARK: - Request Authorization

    /// Request ATT authorization from the user. The host app controls when to call this
    /// (e.g., after onboarding, before paywall). Never called automatically by the SDK.
    ///
    /// - Parameter completion: Called with `true` if authorized, `false` otherwise.
    ///   Always called on the main thread.
    func requestTrackingAuthorization(completion: @escaping (Bool) -> Void) {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14, *) {
            let currentStatus = ATTrackingManager.trackingAuthorizationStatus

            // Only request if not yet determined — re-requesting after denial is a no-op
            guard currentStatus == .notDetermined else {
                let authorized = currentStatus == .authorized
                Logger.shared.debug("ATT already determined: \(currentStatus.rawValue), authorized=\(authorized)")
                DispatchQueue.main.async {
                    completion(authorized)
                }
                return
            }

            ATTrackingManager.requestTrackingAuthorization { status in
                let authorized = status == .authorized
                Logger.shared.debug("ATT authorization result: \(status.rawValue), authorized=\(authorized)")
                DispatchQueue.main.async {
                    completion(authorized)
                }
            }
            return
        }
        #endif

        // Pre-iOS 14 or AppTrackingTransparency not available
        #if canImport(AdSupport)
        let enabled = ASIdentifierManager.shared().isAdvertisingTrackingEnabled
        Logger.shared.debug("Pre-ATT tracking enabled: \(enabled)")
        DispatchQueue.main.async {
            completion(enabled)
        }
        #else
        DispatchQueue.main.async {
            completion(false)
        }
        #endif
    }
}
