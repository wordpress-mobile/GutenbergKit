import Foundation

/// A wrapper type that safely decodes values, ignoring decoding failures instead of throwing errors.
///
/// `SafeDecodable` is useful when decoding arrays where some elements might be malformed
/// or fail validation. Instead of failing the entire decoding operation, it captures individual
/// failures and allows you to filter them out.
struct SafeDecodable<Base: Decodable>: Decodable {
    let result: Result<Base, Error>
    var value: Base? { try? result.get() }

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            self.result = .success(try container.decode(Base.self))
        } catch {
            assertionFailure("Decoding error: \(error)") // Should never happen
            self.result = .failure(error)
        }
    }
}

extension KeyedDecodingContainer {
    func decodeSafely<T: Decodable>(_ type: [T].Type, forKey key: Key) throws -> [T] {
        let safeArray = try decode([SafeDecodable<T>].self, forKey: key)
        return safeArray.compactMap { $0.value }
    }

    func decodeSafelyIfPresent<T: Decodable>(_ type: [T].Type, forKey key: Key) throws -> [T]? {
        guard let safeArray = try decodeIfPresent([SafeDecodable<T>].self, forKey: key) else {
            return nil
        }
        return safeArray.compactMap { $0.value }
    }
}
