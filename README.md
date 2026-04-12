# DeployRamp Swift SDK

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Swift SDK for [DeployRamp](https://deployramp.com) — AI-native feature flag management with gradual rollouts, real-time updates, and automatic error-monitored rollbacks.

**Platforms:** macOS 12+, iOS 15+, tvOS 15+, watchOS 8+

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies**, then enter:

```
https://github.com/deployramp/deployramp-swift
```

Or add to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/deployramp/deployramp-swift", from: "0.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "DeployRamp", package: "deployramp-swift"),
    ]),
],
```

## Quick Start

```swift
import DeployRamp

// Initialize once at app startup (async)
try await DeployRamp.initialize(Config(
    publicToken: "drp_pub_your_token",
    traits: ["plan": "pro", "region": "us-east"]
))

// Evaluate a feature flag
if DeployRamp.flag("new-checkout-flow") {
    await processNewCheckout()
} else {
    await processOldCheckout()
}

// Report errors — DeployRamp uses these to auto-roll back bad deploys
do {
    try await processCheckout()
} catch {
    DeployRamp.report(error, flagName: "new-checkout-flow")
}

DeployRamp.close()
```

## Trait-Based Targeting

```swift
try await DeployRamp.initialize(Config(publicToken: "drp_pub_your_token"))

// Update traits after login
DeployRamp.setTraits(["plan": "enterprise", "cohort": "beta"])

// Override traits for a single evaluation
let enabled = DeployRamp.flag("beta-feature", traitOverrides: ["cohort": "alpha"])
```

## Measure Performance

```swift
let result = DeployRamp.measure(
    name: "fast-algorithm",
    enabled: { newAlgorithm(data) },
    disabled: { oldAlgorithm(data) }
)
```

## API Reference

| Function | Description |
|---|---|
| `initialize(_ config: Config) async throws` | Initialize the SDK, fetch flags, open WebSocket |
| `flag(_ name: String, traitOverrides?: [String: String]) -> Bool` | Evaluate a feature flag |
| `setTraits(_ traits: [String: String])` | Update user traits for all subsequent evaluations |
| `measure(name:enabled:disabled:traitOverrides:) -> T` | Run branch and record timing |
| `report(_ error: Error, flagName?, traitOverrides?)` | Report error for rollback monitoring |
| `close()` | Flush pending events and disconnect |

## Links

- [deployramp.com](https://deployramp.com)
- [GitHub](https://github.com/deployramp/deployramp-swift)

## License

MIT
