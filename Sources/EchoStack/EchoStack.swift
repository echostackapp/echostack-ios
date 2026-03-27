//
//  EchoStack.swift
//  EchoStack iOS SDK
//
//  Public singleton entry point. Mirrors Appstack SDK API for easy migration.
//

import Foundation

/// Log level for SDK internal logging.
public enum EchoStackLogLevel: Int {
    case none = 0
    case error = 1
    case warning = 2
    case debug = 3
}

/// Predefined event types matching EchoStack backend conventions.
public enum EventType: String {
    case install
    case trialStart = "trial_start"
    case trialQualified = "trial_qualified"
    case purchase
    case subscribe
    case adImpression = "ad_impression"
    case adClick = "ad_click"
    case login
    case signUp = "sign_up"
    case register
    case addToCart = "add_to_cart"
    case addToWishlist = "add_to_wishlist"
    case initiateCheckout = "initiate_checkout"
    case levelStart = "level_start"
    case levelComplete = "level_complete"
    case tutorialComplete = "tutorial_complete"
    case search
    case viewItem = "view_item"
    case viewContent = "view_content"
    case share
    case custom
}

/// EchoStack iOS SDK — mobile attribution for ad networks.
///
/// Usage:
/// ```swift
/// // In AppDelegate.didFinishLaunchingWithOptions:
/// EchoStack.shared.configure(apiKey: "es_live_...")
///
/// // Send events:
/// await EchoStack.shared.sendEvent(.purchase, parameters: ["revenue": 29.99, "currency": "USD"])
/// ```
public final class EchoStack: @unchecked Sendable {

    /// Singleton instance.
    public static let shared = EchoStack()

    // MARK: - Internal managers

    private var configuration: Configuration?
    private var deviceManager: DeviceManager?
    private var networkClient: NetworkClient?
    private var attributionManager: AttributionManager?
    private var eventQueue: EventQueue?
    private var advertisingManager: AdvertisingManager?

    private var isConfigured = false
    private var _isSdkDisabled = false

    private let lock = NSLock()

    private init() {}

    // MARK: - Public API

    /// Initialize the SDK with your API key. Call once in AppDelegate.didFinishLaunchingWithOptions.
    ///
    /// - Parameters:
    ///   - apiKey: Your EchoStack API key (starts with "es_live_").
    ///   - serverURL: Override server URL (default: https://api.echostack.app).
    ///   - logLevel: SDK log level (default: .none for production).
    public func configure(
        apiKey: String,
        serverURL: String = "https://api.echostack.app",
        logLevel: EchoStackLogLevel = .none
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard !isConfigured else {
            Logger.shared.warning("EchoStack already configured. Ignoring duplicate configure() call.")
            return
        }

        guard apiKey.hasPrefix("es_live_") || apiKey.hasPrefix("es_test_") else {
            Logger.shared.error("Invalid API key format. Must start with 'es_live_' or 'es_test_'.")
            _isSdkDisabled = true
            return
        }

        Logger.shared.level = logLevel
        Logger.shared.debug("Configuring EchoStack SDK...")

        let config = Configuration(apiKey: apiKey, serverURL: serverURL, logLevel: logLevel)
        self.configuration = config

        let advertising = AdvertisingManager()
        self.advertisingManager = advertising

        let device = DeviceManager(advertisingManager: advertising)
        self.deviceManager = device

        let network = NetworkClient(configuration: config)
        self.networkClient = network

        let attribution = AttributionManager(
            deviceManager: device,
            networkClient: network,
            configuration: config,
            advertisingManager: advertising
        )
        self.attributionManager = attribution

        let queue = EventQueue(networkClient: network, deviceManager: device)
        self.eventQueue = queue

        isConfigured = true

        // Send install ping asynchronously
        Task {
            await attribution.sendInstallPing()
        }

        Logger.shared.debug("EchoStack SDK configured. Device ID: \(device.echoStackId)")
    }

    /// Get the unique device installation ID (persisted in Keychain).
    public func getEchoStackId() -> String? {
        return deviceManager?.echoStackId
    }

    /// Get attribution parameters after matching completes. Returns nil if not yet available.
    public func getAttributionParams() -> [String: Any]? {
        return attributionManager?.cachedAttribution
    }

    /// Check if the SDK is disabled (invalid key, fatal error, etc.).
    public func isSdkDisabled() -> Bool {
        return _isSdkDisabled
    }

    // MARK: - Apple Ads Attribution

    /// Enable Apple Ads attribution via the AdServices framework.
    /// Fetches an attribution token on iOS 14.3+ and includes it in the install ping payload.
    /// Safe to call even if AdServices is unavailable — fails silently.
    public func enableAppleAdsAttribution() {
        guard isConfigured, !_isSdkDisabled else {
            Logger.shared.warning("SDK not configured or disabled. Cannot enable Apple Ads attribution.")
            return
        }

        attributionManager?.enableAppleAdsAttribution()
        Logger.shared.debug("Apple Ads attribution enabled")
    }

    // MARK: - IDFA / App Tracking Transparency

    /// Returns the IDFA (Identifier for Advertisers) if ATT is authorized, nil otherwise.
    /// Call `requestTrackingAuthorization` first to prompt the user.
    public func getIDFA() -> String? {
        return advertisingManager?.idfa
    }

    /// Request App Tracking Transparency authorization from the user.
    /// The host app should call this at an appropriate time (e.g., after onboarding).
    /// The SDK never auto-prompts.
    ///
    /// - Parameter completion: Called on the main thread with `true` if authorized.
    public func requestTrackingAuthorization(completion: @escaping (Bool) -> Void) {
        guard let advertising = advertisingManager else {
            Logger.shared.warning("SDK not configured. Cannot request tracking authorization.")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }

        advertising.requestTrackingAuthorization { authorized in
            if authorized {
                Logger.shared.debug("Tracking authorized — IDFA: \(advertising.idfa ?? "nil")")
            }
            completion(authorized)
        }
    }

    /// Send an in-app event. Events are queued locally and flushed in batches.
    ///
    /// - Parameters:
    ///   - eventType: Predefined or custom event type.
    ///   - parameters: Optional event parameters (revenue, currency, custom fields).
    public func sendEvent(_ eventType: EventType, parameters: [String: Any]? = nil) {
        guard isConfigured, !_isSdkDisabled else {
            Logger.shared.warning("SDK not configured or disabled. Event '\(eventType.rawValue)' dropped.")
            return
        }

        let event = QueuedEvent(
            eventType: eventType.rawValue,
            parameters: parameters ?? [:],
            eventAt: Date()
        )

        eventQueue?.enqueue(event)

        // Significant events trigger immediate flush
        let significantEvents: Set<String> = [EventType.purchase.rawValue, EventType.subscribe.rawValue]
        if significantEvents.contains(eventType.rawValue) {
            Task {
                await eventQueue?.flush()
            }
        }
    }

    /// Send a custom event with a string type name.
    public func sendEvent(_ eventType: String, parameters: [String: Any]? = nil) {
        guard isConfigured, !_isSdkDisabled else { return }

        let event = QueuedEvent(
            eventType: eventType,
            parameters: parameters ?? [:],
            eventAt: Date()
        )
        eventQueue?.enqueue(event)
    }

    /// Disable the SDK (called internally on 401 or fatal errors).
    internal func disable() {
        _isSdkDisabled = true
        Logger.shared.error("EchoStack SDK disabled.")
    }
}
