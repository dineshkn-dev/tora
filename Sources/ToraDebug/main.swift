import Foundation
import ToraCore

struct DebugError: LocalizedError {
    let errorDescription: String?
}

@main
struct ToraDebug {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            return
        }
        args.removeFirst()

        switch command {
        case "inspect-file":
            guard let path = args.first else { throw DebugError(errorDescription: "Missing torrent file path.") }
            let service = try makeService()
            let pending = try await service.inspectTorrentFile(URL(fileURLWithPath: path))
            printPending(pending)

        case "inspect-magnet":
            guard let magnet = args.first else { throw DebugError(errorDescription: "Missing magnet link.") }
            let service = try makeService()
            let pending = try await service.inspectMagnet(magnet)
            printPending(pending)

        case "prefetch-metadata":
            guard let magnet = args.first else { throw DebugError(errorDescription: "Missing magnet link.") }
            let timeout = args.dropFirst().first.flatMap(Double.init) ?? 120
            try await prefetchMetadata(magnet: magnet, timeout: timeout)

        case "help", "--help", "-h":
            printUsage()

        default:
            throw DebugError(errorDescription: "Unknown command: \(command)")
        }
    }

    private static func makeService() throws -> TorrentService {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ToraDebug", isDirectory: true)
        let downloads = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ToraDebugDownloads", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        var settings = TorrentSessionSettings.secureDefault
        settings.enableDHT = true
        settings.enableLSD = true
        settings.enablePeerExchange = true
        settings.maxConnections = 200

        return try TorrentService(
            settings: settings,
            pathPolicy: DownloadPathPolicy(allowedRoot: downloads),
            deletionPolicy: DeletionPolicy(allowedRoot: downloads),
            resumeDataDirectory: root.appendingPathComponent("ResumeData", isDirectory: true),
            sessionStateURL: root.appendingPathComponent("Session/session_state", isDirectory: false)
        )
    }

    private static func prefetchMetadata(magnet: String, timeout: TimeInterval) async throws {
        let service = try makeService()
        let pending = try await service.inspectMagnet(magnet)
        let downloads = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ToraDebugDownloads", isDirectory: true)
        let id = try await service.addTorrent(
            pending,
            options: AddTorrentOptions(
                downloadDirectory: downloads,
                selectedFileIndexes: [],
                startPaused: false,
                fetchMetadataOnly: true
            )
        )

        let started = Date()
        var lastError: String?
        while Date().timeIntervalSince(started) < timeout {
            for event in await service.drainEvents() {
                switch event {
                case .metadataReceived(let eventID, let metadata) where eventID == id:
                    printPending(metadata)
                    await service.shutdown()
                    return
                case .failed(_, let message):
                    lastError = message
                default:
                    break
                }
            }

            if let metadata = try await service.metadataForTorrent(id, source: .magnet(magnet)) {
                printPending(metadata)
                await service.shutdown()
                return
            }

            try await Task.sleep(for: .milliseconds(500))
        }

        await service.shutdown()
        let suffix = lastError.map { " Last libtorrent error: \($0)" } ?? ""
        throw DebugError(errorDescription: "Timed out waiting for metadata after \(Int(timeout)) seconds.\(suffix)")
    }

    private static func printPending(_ pending: PendingTorrent) {
        let totalBytes = pending.files.map(\.size).reduce(0, +)
        print("name: \(pending.name)")
        print("infoHash: \(pending.infoHash ?? "<none>")")
        print("files: \(pending.files.count)")
        print("totalBytes: \(totalBytes)")
        for file in pending.files.prefix(20) {
            print("- [\(file.index)] \(file.path) (\(file.size) bytes)")
        }
        if pending.files.count > 20 {
            print("- ... \(pending.files.count - 20) more")
        }
    }

    private static func printUsage() {
        print("""
        ToraDebug

        Commands:
          inspect-file <path.torrent>
          inspect-magnet <magnet-link>
          prefetch-metadata <magnet-link> [timeout-seconds]
        """)
    }
}
