import Foundation

public enum TorrentPathValidationError: LocalizedError, Equatable {
    case emptyPath
    case absolutePath
    case homeRelativePath
    case parentDirectoryReference
    case currentDirectoryReference
    case emptyComponent
    case windowsDrivePath
    case containsControlCharacter
    case escapesDownloadDirectory

    public var errorDescription: String? {
        switch self {
        case .emptyPath: "Torrent path is empty."
        case .absolutePath: "Torrent path must be relative."
        case .homeRelativePath: "Torrent path must not be home-relative."
        case .parentDirectoryReference: "Torrent path must not contain parent-directory references."
        case .currentDirectoryReference: "Torrent path must not contain current-directory references."
        case .emptyComponent: "Torrent path must not contain empty path components."
        case .windowsDrivePath: "Torrent path must not contain a Windows drive prefix."
        case .containsControlCharacter: "Torrent path must not contain control characters."
        case .escapesDownloadDirectory: "Torrent path escapes the selected download directory."
        }
    }
}

public enum TorrentPathValidator {
    public static func validate(_ torrentPath: String, inside downloadDirectory: URL) throws {
        let normalizedPath = torrentPath.replacingOccurrences(of: "\\", with: "/")

        guard !normalizedPath.isEmpty else {
            throw TorrentPathValidationError.emptyPath
        }

        guard !normalizedPath.hasPrefix("/") else {
            throw TorrentPathValidationError.absolutePath
        }

        guard !normalizedPath.hasPrefix("~") else {
            throw TorrentPathValidationError.homeRelativePath
        }

        if normalizedPath.range(of: #"^[A-Za-z]:"#, options: .regularExpression) != nil {
            throw TorrentPathValidationError.windowsDrivePath
        }

        if normalizedPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            throw TorrentPathValidationError.containsControlCharacter
        }

        let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for component in components {
            if component.isEmpty {
                throw TorrentPathValidationError.emptyComponent
            }
            if component == "." {
                throw TorrentPathValidationError.currentDirectoryReference
            }
            if component == ".." {
                throw TorrentPathValidationError.parentDirectoryReference
            }
        }

        let root = downloadDirectory.standardizedFileURL
        let candidate = root.appendingPathComponent(normalizedPath).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let candidatePath = candidate.path

        guard candidatePath == root.path || candidatePath.hasPrefix(rootPath) else {
            throw TorrentPathValidationError.escapesDownloadDirectory
        }
    }
}
