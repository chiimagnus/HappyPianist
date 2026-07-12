import Foundation

// ponytail: embedded in AVP; extract only when another Swift target needs it.

public struct PythonRandom {
    private static let n = 624
    private static let m = 397

    private static let matrixA: UInt32 = 0x9908_B0DF
    private static let upperMask: UInt32 = 0x8000_0000
    private static let lowerMask: UInt32 = 0x7FFF_FFFF

    private var state: [UInt32]
    private var index: Int

    public init(seed: UInt64) {
        state = Array(repeating: 0, count: Self.n)
        index = Self.n + 1
        reseed(seed)
    }

    public mutating func reseed(_ seed: UInt64) {
        // CPython random_seed(): split absolute value of the integer seed into 32-bit words
        // (little-endian) and feed into init_by_array().
        let bits = seed == 0 ? 0 : (UInt64.bitWidth - seed.leadingZeroBitCount)
        let keyUsed = bits == 0 ? 1 : ((bits - 1) / 32 + 1)

        var key: [UInt32] = []
        key.reserveCapacity(keyUsed)
        for i in 0 ..< keyUsed {
            let word = UInt32(truncatingIfNeeded: seed >> UInt64(i * 32))
            key.append(word)
        }

        initByArray(key)
    }

    public mutating func random() -> Double {
        // CPython _random.Random.random(): genrand_uint32() >> 5 and >> 6
        let a = nextUInt32() >> 5
        let b = nextUInt32() >> 6
        return (Double(a) * 67_108_864.0 + Double(b)) * (1.0 / 9_007_199_254_740_992.0)
    }


    public mutating func randint(_ a: Int, _ b: Int) -> Int {
        precondition(a <= b, "empty range for randint()")
        let width = UInt64(b - a) + 1
        return a + Int(randBelow(width))
    }

    public mutating func choice<T>(_ array: [T]) -> T {
        precondition(array.isEmpty == false, "cannot choose from an empty sequence")
        let idx = Int(randBelow(UInt64(array.count)))
        return array[idx]
    }

    public mutating func randBelow(_ n: UInt64) -> UInt64 {
        precondition(n > 0, "n must be positive")

        let bitLength = UInt64.bitWidth - n.leadingZeroBitCount
        while true {
            let r = getRandBits(bitLength)
            if r < n {
                return r
            }
        }
    }

    public mutating func getRandBits(_ k: Int) -> UInt64 {
        precondition(k >= 0, "number of bits must be non-negative")
        if k == 0 { return 0 }
        precondition(k <= 64, "getRandBits currently supports up to 64 bits")

        if k <= 32 {
            return UInt64(nextUInt32() >> UInt32(32 - k))
        }

        // Assemble from 32-bit words, least significant to most significant, then mask.
        let low = UInt64(nextUInt32())
        let high = UInt64(nextUInt32())
        let combined = (high << 32) | low
        return combined >> UInt64(64 - k)
    }

    private mutating func initGenRand(_ s: UInt32) {
        state[0] = s
        if Self.n <= 1 {
            index = Self.n
            return
        }

        for i in 1 ..< Self.n {
            let prev = state[i - 1]
            let x = prev ^ (prev >> 30)
            state[i] = 1_812_433_253 &* x &+ UInt32(i)
        }
        index = Self.n
    }

    private mutating func initByArray(_ initKey: [UInt32]) {
        precondition(initKey.isEmpty == false)

        initGenRand(19_650_218)
        var i = 1
        var j = 0
        var k = max(Self.n, initKey.count)

        while k > 0 {
            let x = state[i - 1] ^ (state[i - 1] >> 30)
            state[i] = (state[i] ^ (x &* 1_664_525)) &+ initKey[j] &+ UInt32(j)

            i += 1
            j += 1
            if i >= Self.n {
                state[0] = state[Self.n - 1]
                i = 1
            }
            if j >= initKey.count { j = 0 }
            k -= 1
        }

        k = Self.n - 1
        while k > 0 {
            let x = state[i - 1] ^ (state[i - 1] >> 30)
            state[i] = (state[i] ^ (x &* 1_566_083_941)) &- UInt32(i)

            i += 1
            if i >= Self.n {
                state[0] = state[Self.n - 1]
                i = 1
            }

            k -= 1
        }

        state[0] = 0x8000_0000
    }

    private mutating func nextUInt32() -> UInt32 {
        if index >= Self.n {
            twist()
        }

        var y = state[index]
        index += 1

        y ^= (y >> 11)
        y ^= (y << 7) & 0x9D2C_5680
        y ^= (y << 15) & 0xEFC6_0000
        y ^= (y >> 18)
        return y
    }

    private mutating func twist() {
        let mag01: [UInt32] = [0, Self.matrixA]

        for kk in 0 ..< (Self.n - Self.m) {
            let y = (state[kk] & Self.upperMask) | (state[kk + 1] & Self.lowerMask)
            state[kk] = state[kk + Self.m] ^ (y >> 1) ^ mag01[Int(y & 1)]
        }

        for kk in (Self.n - Self.m) ..< (Self.n - 1) {
            let y = (state[kk] & Self.upperMask) | (state[kk + 1] & Self.lowerMask)
            state[kk] = state[kk + (Self.m - Self.n)] ^ (y >> 1) ^ mag01[Int(y & 1)]
        }

        let y = (state[Self.n - 1] & Self.upperMask) | (state[0] & Self.lowerMask)
        state[Self.n - 1] = state[Self.m - 1] ^ (y >> 1) ^ mag01[Int(y & 1)]
        index = 0
    }
}
