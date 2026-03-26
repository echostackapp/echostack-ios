//
//  EventQueue.swift
//  EchoStack iOS SDK
//
//  Local event queue with batched flush. Events stored in UserDefaults.
//  Flush triggers: 30s timer, significant events, app background.
//

import Foundation
import UIKit

/// Represents a queued event waiting to be sent.
struct QueuedEvent: Codable {
    let eventType: String
    let parameters: [String: AnyCodable]
    let eventAt: Date

    init(eventType: String, parameters: [String: Any], eventAt: Date) {
        self.eventType = eventType
        self.parameters = parameters.mapValues { AnyCodable($0) }
        self.eventAt = eventAt
    }
}

final class EventQueue: @unchecked Sendable {

    private let networkClient: NetworkClient
    private let deviceManager: DeviceManager
    private var queue: [QueuedEvent] = []
    private let lock = NSLock()
    private var flushTimer: Timer?
    private let maxQueueSize = 1000

    private let storageKey = "echostack_event_queue"
    private let flushInterval: TimeInterval = 30.0

    init(networkClient: NetworkClient, deviceManager: DeviceManager) {
        self.networkClient = networkClient
        self.deviceManager = deviceManager

        // Load persisted queue
        loadQueue()

        // Start flush timer
        startFlushTimer()

        // Flush on app background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    deinit {
        flushTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    /// Add an event to the queue.
    func enqueue(_ event: QueuedEvent) {
        lock.lock()
        defer { lock.unlock() }

        queue.append(event)

        // Drop oldest if exceeded max
        if queue.count > maxQueueSize {
            let dropCount = queue.count - maxQueueSize
            queue.removeFirst(dropCount)
            Logger.shared.warning("Event queue full. Dropped \(dropCount) oldest events.")
        }

        persistQueue()
    }

    /// Flush queued events to server.
    func flush() async {
        let eventsToSend: [QueuedEvent]

        lock.lock()
        if queue.isEmpty {
            lock.unlock()
            return
        }
        eventsToSend = queue
        lock.unlock()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let eventPayloads: [[String: Any]] = eventsToSend.map { event in
            var params: [String: Any] = [:]
            for (key, value) in event.parameters {
                params[key] = value.value
            }

            return [
                "event_type": event.eventType,
                "parameters": params,
                "event_at": formatter.string(from: event.eventAt),
            ]
        }

        let payload: [String: Any] = [
            "echostack_id": deviceManager.echoStackId,
            "events": eventPayloads,
        ]

        Logger.shared.debug("Flushing \(eventsToSend.count) events...")

        let response = await networkClient.sendEvents(payload: payload)

        if response != nil {
            // Success — clear sent events from queue
            lock.lock()
            let sentCount = eventsToSend.count
            if queue.count >= sentCount {
                queue.removeFirst(sentCount)
            }
            persistQueue()
            lock.unlock()

            Logger.shared.debug("Flushed \(sentCount) events successfully")
        } else {
            Logger.shared.warning("Event flush failed — will retry on next cycle")
        }
    }

    // MARK: - Private

    private func startFlushTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.flushTimer = Timer.scheduledTimer(withTimeInterval: self.flushInterval, repeats: true) { [weak self] _ in
                Task { await self?.flush() }
            }
        }
    }

    @objc private func appWillResignActive() {
        Task { await flush() }
    }

    private func persistQueue() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadQueue() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([QueuedEvent].self, from: data) else {
            return
        }
        queue = loaded
    }
}

// MARK: - AnyCodable (lightweight wrapper for heterogeneous dict values)

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let string = try? container.decode(String.self) { value = string }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let int = value as? Int { try container.encode(int) }
        else if let double = value as? Double { try container.encode(double) }
        else if let string = value as? String { try container.encode(string) }
        else if let bool = value as? Bool { try container.encode(bool) }
        else { try container.encode(String(describing: value)) }
    }
}
