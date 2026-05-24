import CryptoKit
import Foundation

/// Shared seed-resolution logic for improv backends.
///
/// Behavior (must stay stable):
/// - Prefer explicit seed.
/// - Otherwise derive from sessionID using SHA256 (first 8 bytes, big-endian).
/// - Otherwise return 0.
struct ImprovSeedResolver: Sendable {
    init() {}

    func resolveSeed(explicitSeed: UInt64?, sessionID: String?) -> UInt64 {
        if let explicitSeed {
            return explicitSeed
        }
        if let sessionID {
            return deriveSeed(fromSessionID: sessionID)
        }
        return 0
    }

    private func deriveSeed(fromSessionID sessionID: String) -> UInt64 {
        let digest = SHA256.hash(data: Data(sessionID.utf8))
        var seed: UInt64 = 0
        for byte in digest.prefix(8) {
            seed = (seed << 8) | UInt64(byte)
        }
        return seed
    }
}

