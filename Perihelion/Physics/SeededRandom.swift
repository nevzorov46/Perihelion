/// Mulberry32. Integer-only, so a seed produces the same sky on every device.
struct SeededRandom {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed
    }

    init(_ string: String) {
        self.init(seed: Self.hash(string))
    }

    mutating func next() -> Double {
        state &+= 0x6D2B_79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }

    mutating func range(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * next()
    }

    mutating func sign() -> Double {
        next() < 0.5 ? -1 : 1
    }

    /// FNV-1a over UTF-8 with a murmur3 finaliser.
    static func hash(_ string: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for byte in string.utf8 {
            h ^= UInt32(byte)
            h = h &* 16_777_619
        }
        h ^= h >> 16; h = h &* 0x85EB_CA6B
        h ^= h >> 13; h = h &* 0xC2B2_AE35
        h ^= h >> 16
        return h
    }
}
