import SwiftUI
import AppKit
import Sparkle
import ToraCore
import ToraPersistence
import ToraUI

@main
struct ToraApp: App {
    @StateObject private var appState = AppState()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: Self.canStartUpdater,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private static var canStartUpdater: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String
            && Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String
    }

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
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
        Settings {
            SettingsView()
                .environmentObject(appState.uiState)
        }
    }
}

private struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates...", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
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
                pathPolicy: DownloadPathPolicy(allowedRoot: directories.defaultDownloadDirectory),
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
