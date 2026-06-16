import Foundation

public struct AppDirectories: Sendable {
    public let applicationSupport: URL
    public let sessionData: URL
    public let resumeData: URL
    public let metadata: URL
    public let logs: URL
    public let defaultDownloadDirectory: URL

    public init(fileManager: FileManager = .default) {
        let appSupportBase = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)

        self.applicationSupport = appSupportBase.appendingPathComponent("Tora", isDirectory: true)
        self.sessionData = applicationSupport.appendingPathComponent("Session", isDirectory: true)
        self.resumeData = applicationSupport.appendingPathComponent("ResumeData", isDirectory: true)
        self.metadata = applicationSupport.appendingPathComponent("Metadata", isDirectory: true)
        self.logs = applicationSupport.appendingPathComponent("Logs", isDirectory: true)

        let downloadsBase = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        self.defaultDownloadDirectory = downloadsBase.appendingPathComponent("Tora", isDirectory: true)
    }

    public func createRequiredDirectories(fileManager: FileManager = .default) throws {
        for directory in [applicationSupport, sessionData, resumeData, metadata, logs, defaultDownloadDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
