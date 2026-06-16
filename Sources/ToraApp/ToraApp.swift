import SwiftUI
import AppKit
import ToraCore
import ToraPersistence
import ToraUI

@main
struct ToraApp: App {
    @StateObject private var appState = AppState()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ToraRootView()
                .environmentObject(appState.uiState)
                .task {
                    await appState.start()
                }
        }
        Settings {
            SettingsView()
                .environmentObject(appState.uiState)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    let directories: AppDirectories
    let torrentService: TorrentServiceProtocol
    let uiState: ToraUIState
    let metadataStore: MetadataStore
    let settingsStore: SettingsStore

    init() {
        self.directories = AppDirectories()
        self.metadataStore = MetadataStore(directory: directories.metadata)
        self.settingsStore = SettingsStore(directory: directories.metadata)
        let settings = (try? settingsStore.load()) ?? .secureDefault
        
        if ProcessInfo.processInfo.environment["TORA_DEMO"] != nil {
            self.torrentService = DemoTorrentService()
        } else {
            self.torrentService = (try? TorrentService(
                settings: settings,
                metadataStore: metadataStore,
                deletionPolicy: DeletionPolicy(allowedRoot: directories.defaultDownloadDirectory),
                resumeDataDirectory: directories.resumeData,
                sessionStateURL: SessionDataStore(directory: directories.sessionData).sessionStateURL
            )) ?? MockTorrentService()
        }
        self.uiState = ToraUIState(
            torrentService: torrentService,
            defaultDownloadDirectory: directories.defaultDownloadDirectory,
            settings: settings,
            saveSettings: { [settingsStore] settings in
                try settingsStore.save(settings)
            }
        )
    }

    func start() async {
        try? directories.createRequiredDirectories()
        try? await torrentService.start()
        await uiState.refresh()
    }
}
