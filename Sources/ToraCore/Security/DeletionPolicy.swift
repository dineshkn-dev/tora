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

        try rejectSymbolicLinkComponents(from: allowedRoot, to: url.standardizedFileURL)
    }

    private func rejectSymbolicLinkComponents(from root: URL, to candidate: URL) throws {
        var current = root
        if isSymbolicLink(current) {
            throw DeletionPolicyError.symbolicLink
        }

        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return }

        for component in candidateComponents.dropFirst(rootComponents.count) {
            current.appendPathComponent(component)
            if isSymbolicLink(current) {
                throw DeletionPolicyError.symbolicLink
            }
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}

public enum DeletionPolicyError: LocalizedError, Equatable {
    case notAFileURL
    case outsideAllowedRoot
    case symbolicLink

    public var errorDescription: String? {
        switch self {
        case .notAFileURL:
            "Deletion target must be a local file URL."
        case .outsideAllowedRoot:
            "Refusing to delete data outside Tora's dedicated download directory."
        case .symbolicLink:
            "Refusing to delete downloaded data through a symbolic link."
        }
    }
}
