import Foundation

/// A dictionary-shaped cache with a hard insertion-order cap, so per-session caches (waveform peaks, lyrics)
/// stay bounded. Keys evict oldest-first past `limit`: true FIFO, not LRU. Re-setting a key does not refresh its
/// rank, because the keys are per-track and a hot key would otherwise pin cold tracks.
/// Not thread-safe by design: it lives inside @MainActor types (PlaybackController).
struct KeyedFIFOCache<Value> {
    private var storage: [String: Value] = [:]
    private var order: [String] = []
    private let limit: Int

    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    subscript(key: String) -> Value? {
        get { storage[key] }
        set {
            if let newValue {
                if storage[key] == nil {
                    order.append(key)
                    if order.count > limit {
                        storage.removeValue(forKey: order.removeFirst())
                    }
                }
                storage[key] = newValue
            } else {
                storage.removeValue(forKey: key)
                order.removeAll { $0 == key }
            }
        }
    }
}
