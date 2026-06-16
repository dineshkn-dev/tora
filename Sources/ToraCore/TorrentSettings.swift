import Foundation

public struct TorrentSessionSettings: Codable, Equatable, Sendable {
    public var enableDHT: Bool
    public var enableLSD: Bool
    public var enableUPnP: Bool
    public var enableNATPMP: Bool
    public var enablePeerExchange: Bool
    public var encryptionPolicy: EncryptionPolicy
    public var listenPortStart: UInt16
    public var listenPortEnd: UInt16
    public var maxConnections: Int
    public var maxUploads: Int
    public var downloadRateLimitBytesPerSecond: Int?
    public var uploadRateLimitBytesPerSecond: Int?
    public var seedRatioLimitPercent: Int?
    public var seedTimeLimitSeconds: Int?
    public var seedTimeRatioLimitPercent: Int?

    public static let secureDefault = TorrentSessionSettings(
        enableDHT: false,
        enableLSD: false,
        enableUPnP: false,
        enableNATPMP: false,
        enablePeerExchange: false,
        encryptionPolicy: .enabled,
        listenPortStart: 49_152,
        listenPortEnd: 65_535,
        maxConnections: 80,
        maxUploads: 20,
        downloadRateLimitBytesPerSecond: nil,
        uploadRateLimitBytesPerSecond: nil,
        seedRatioLimitPercent: 200,
        seedTimeLimitSeconds: nil,
        seedTimeRatioLimitPercent: nil
    )
}

public enum EncryptionPolicy: String, Codable, CaseIterable, Sendable {
    case enabled
    case forced
    case disabled
}
