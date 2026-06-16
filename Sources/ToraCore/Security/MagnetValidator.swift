import Foundation

public struct MagnetValidator: Sendable {
    public init() {}

    public func validate(_ magnet: String) throws {
        guard !magnet.isEmpty else {
            throw MagnetValidationError.empty
        }

        guard magnet.count <= 8_192 else {
            throw MagnetValidationError.tooLarge
        }

        guard magnet.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw MagnetValidationError.containsControlCharacter
        }

        guard let components = URLComponents(string: magnet), components.scheme == "magnet" else {
            throw MagnetValidationError.invalidScheme
        }

        let queryItems = components.queryItems ?? []
        let exactTopics = queryItems.filter { $0.name == "xt" }.compactMap(\.value)
        guard exactTopics.contains(where: { $0.hasPrefix("urn:btih:") || $0.hasPrefix("urn:btmh:") }) else {
            throw MagnetValidationError.missingBitTorrentTopic
        }
    }
}

public enum MagnetValidationError: LocalizedError, Equatable {
    case empty
    case tooLarge
    case containsControlCharacter
    case invalidScheme
    case missingBitTorrentTopic

    public var errorDescription: String? {
        switch self {
        case .empty: "Magnet link is empty."
        case .tooLarge: "Magnet link is too large."
        case .containsControlCharacter: "Magnet link contains control characters."
        case .invalidScheme: "Magnet link must use the magnet scheme."
        case .missingBitTorrentTopic: "Magnet link is missing a BitTorrent exact topic."
        }
    }
}
