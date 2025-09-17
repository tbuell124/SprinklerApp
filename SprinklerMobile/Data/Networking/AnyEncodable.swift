import Foundation

/// Type-erased `Encodable` wrapper so callers can hand arbitrary payloads to the networking layer
/// without forcing generics or sacrificing type safety.
struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ encodable: Encodable) {
        self.encodeClosure = { encoder in
            try encodable.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
