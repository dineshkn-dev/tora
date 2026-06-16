import Foundation

public struct DownloadPathPolicy: Sendable {
    public init() {}

    public func validateDownloadDirectory(_ url: URL) throws {
        guard url.isFileURL else {
            throw DownloadPathPolicyError.notAFileURL
        }

        guard !url.path.isEmpty else {
            throw DownloadPathPolicyError.emptyPath
        }
    }
}

public enum DownloadPathPolicyError: LocalizedError, Equatable {
    case notAFileURL
    case emptyPath

    public var errorDescription: String? {
        switch self {
        case .notAFileURL: "Download directory must be a local file URL."
        case .emptyPath: "Download directory path is empty."
        }
    }
}
