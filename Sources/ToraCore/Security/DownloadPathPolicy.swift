import Foundation

public struct DownloadPathPolicy: Sendable {
    private let allowedRoot: URL?

    public init(allowedRoot: URL? = nil) {
        self.allowedRoot = allowedRoot?.standardizedFileURL
    }

    public func validateDownloadDirectory(_ url: URL) throws {
        guard url.isFileURL else {
            throw DownloadPathPolicyError.notAFileURL
        }

        guard !url.path.isEmpty else {
            throw DownloadPathPolicyError.emptyPath
        }

        let standardizedURL = url.standardizedFileURL
        if isSymbolicLink(standardizedURL) {
            throw DownloadPathPolicyError.symbolicLink
        }

        guard let allowedRoot else { return }

        let rootPath = allowedRoot.path.hasSuffix("/") ? allowedRoot.path : allowedRoot.path + "/"
        let candidate = standardizedURL.path

        guard candidate == allowedRoot.path || candidate.hasPrefix(rootPath) else {
            throw DownloadPathPolicyError.outsideAllowedRoot
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}

public enum DownloadPathPolicyError: LocalizedError, Equatable {
    case notAFileURL
    case emptyPath
    case outsideAllowedRoot
    case symbolicLink

    public var errorDescription: String? {
        switch self {
        case .notAFileURL: "Download directory must be a local file URL."
        case .emptyPath: "Download directory path is empty."
        case .outsideAllowedRoot: "Download directory must be inside Tora's approved download directory."
        case .symbolicLink: "Download directory must not be a symbolic link."
        }
    }
}
