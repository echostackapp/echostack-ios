# EchoStack iOS SDK

Mobile attribution SDK for iOS. Tracks ad clicks to app installs and forwards conversion events to ad networks (Meta, Google, TikTok).

## Installation

### Swift Package Manager

1. In Xcode, go to **File → Add Package Dependencies**
2. Enter: `https://github.com/echostack/echostack-ios.git`
3. Select version `1.0.0` or later

### Requirements

- iOS 14.0+
- Swift 5.9+
- Xcode 15+

## Quick Start

```swift
import EchoStack

// 1. Configure in AppDelegate
EchoStack.shared.configure(apiKey: "es_live_...")

// 2. Track events
EchoStack.shared.sendEvent(.purchase, parameters: [
    "revenue": 29.99,
    "currency": "USD"
])

// 3. Get attribution
if let attribution = EchoStack.shared.getAttributionParams() {
    print("Network: \(attribution["network"])")
}
```

## Features

- **Zero dependencies** — only Apple frameworks
- **Keychain-persisted device ID** — survives app reinstalls
- **Offline-first** — events queued locally, flushed when network available
- **SKAdNetwork** — automatic conversion value updates (v3.0 + v4.0)
- **Thread-safe** — callable from any thread
- **< 200KB** compiled size

## License

MIT
