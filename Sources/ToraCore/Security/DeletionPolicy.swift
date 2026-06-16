import Foundation

public struct DeletionPolicy: Sendable {
    private let allowedRoot: URL

    public init(allowedRoot: URL) {
        self.allowedRoot = allowedRoot.standardizedFileURL
    }

    public func validateDeletionRoot(_ url: URL) throws {
        guard url.isFileURL else {
            throw DeletionPolicyError.notAFileURL
        }

        let rootPath = allowedRoot.path.hasSuffix("/") ? allowedRoot.path : allowedRoot.path + "/"
        let candidate = url.standardizedFileURL.path

        guard candidate == allowedRoot.path || candidate.hasPrefix(rootPath) else {
            throw DeletionPolicyError.outsideAllowedRoot
        }
    }
}

public enum DeletionPolicyError: LocalizedError, Equatable {
    case notAFileURL
    case outsideAllowedRoot

    public var errorDescription: String? {
        switch self {
        case .notAFileURL:
            "Deletion target must be a local file URL."
        case .outsideAllowedRoot:
            "Refusing to delete data outside Tora's dedicated download directory."
        }
    }
}
