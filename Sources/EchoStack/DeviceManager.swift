//
//  DeviceManager.swift
//  EchoStack iOS SDK
//
//  Manages device ID (Keychain-persisted) and fingerprint collection.
//

import Foundation
import UIKit

final class DeviceManager: @unchecked Sendable {

    /// Unique device ID, persisted in Keychain across app reinstalls.
    let echoStackId: String

    /// Advertising manager for IDFA collection.
    private let advertisingManager: AdvertisingManager?

    init(advertisingManager: AdvertisingManager? = nil) {
        self.echoStackId = Self.loadOrCreateDeviceId()
        self.advertisingManager = advertisingManager
    }

    // MARK: - Device Fingerprint

    /// Collect device fingerprint data for the install ping.
    func collectFingerprint() -> [String: Any] {
        var fingerprint: [String: Any] = [:]

        let device = UIDevice.current
        fingerprint["user_agent"] = Self.buildUserAgent()
        fingerprint["device_model"] = device.model
        fingerprint["os_version"] = device.systemVersion

        let screen = UIScreen.main
        let width = Int(screen.bounds.width * screen.scale)
        let height = Int(screen.bounds.height * screen.scale)
        fingerprint["screen_resolution"] = "\(width)x\(height)"

        fingerprint["language"] = Locale.current.identifier

        if let idfv = device.identifierForVendor?.uuidString {
            fingerprint["idfv"] = idfv
        }

        if let idfa = advertisingManager?.idfa {
            fingerprint["idfa"] = idfa
        }

        return fingerprint
    }

    // MARK: - User-Agent

    private static func buildUserAgent() -> String {
        let device = UIDevice.current
        let model = device.model  // "iPhone", "iPad"
        let systemVersion = device.systemVersion  // "17.4"
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        return "\(appName)/\(appVersion) (\(model); iOS \(systemVersion)) EchoStackSDK/1.0"
    }

    // MARK: - Keychain Device ID

    private static let keychainService = "com.echostack.sdk"
    private static let keychainKey = "echostack_device_id"

    private static func loadOrCreateDeviceId() -> String {
        // Try to read from Keychain
        if let existing = readFromKeychain() {
            return existing
        }

        // Generate new UUID
        let newId = UUID().uuidString.lowercased()

        // Store in Keychain
        saveToKeychain(newId)

        return newId
    }

    private static func readFromKeychain() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private static func saveToKeychain(_ value: String) {
        let data = value.data(using: .utf8)!

        // Delete existing (if any)
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainKey,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainKey,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            Logger.shared.error("Failed to save device ID to Keychain: \(status)")
        }
    }
}
