import Foundation

/// Memoises the decoded form of a JSON `Data` blob (audit finding P-01).
///
/// `ParmaEntry.currentRating`/`notes` previously decoded their backing data on
/// every access, which multiplied into thousands of decodes per render once
/// lists sorted or filtered on rating. A reference type is used deliberately:
/// mutating its internals does not trigger Observation, so cache fills during
/// SwiftUI body evaluation cannot cause re-render loops.
///
/// The cache is keyed on the data's hash so externally-replaced backing data
/// (restores, refaults) is still detected.
final class DecodedJSONCache<Value> {
    private var token: Int?
    private var cached: Value?

    func value(for data: Data, decode: (Data) -> Value) -> Value {
        let key = data.hashValue
        if key == token, let cached {
            return cached
        }
        let value = decode(data)
        token = key
        cached = value
        return value
    }

    func invalidate() {
        token = nil
        cached = nil
    }
}
