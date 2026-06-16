import SwiftUI
import ToraCore
import UniformTypeIdentifiers

@MainActor
public final class ToraUIState: ObservableObject {
    public let torrentService: TorrentServiceProtocol
    public let defaultDownloadDirectory: URL

    @Published public var torrents: [TorrentSnapshot] = []
    @Published public var selectedTorrentID: TorrentID?
    @Published public var settings: TorrentSessionSettings
    @Published public var lastError: String?

    private let saveSettings: @Sendable (TorrentSessionSettings) async throws -> Void

    public init(
        torrentService: TorrentServiceProtocol,
        defaultDownloadDirectory: URL,
        settings: TorrentSessionSettings,
        saveSettings: @escaping @Sendable (TorrentSessionSettings) async throws -> Void
    ) {
        self.torrentService = torrentService
        self.defaultDownloadDirectory = defaultDownloadDirectory
        self.settings = settings
        self.saveSettings = saveSettings
    }

    public func refresh() async {
        for event in await torrentService.drainEvents() {
            if case .failed(_, let message) = event {
                lastError = message
            }
        }
        torrents = await torrentService.torrents()
    }

    public var selectedTorrent: TorrentSnapshot? {
        torrents.first { $0.id == selectedTorrentID }
    }

    public func persistSettings() async {
        do {
            try await saveSettings(settings)
        } catch {
            lastError = error.localizedDescription
        }
    }
}

public struct ToraRootView: View {
    @EnvironmentObject private var uiState: ToraUIState
    @State private var showsAddTorrent = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            TorrentListView(showsAddTorrent: $showsAddTorrent)
        } detail: {
            TorrentDetailView()
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(isPresented: $showsAddTorrent) {
            AddTorrentView()
                .environmentObject(uiState)
        }
        .task {
            while !Task.isCancelled {
                await uiState.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

public struct TorrentListView: View {
    @EnvironmentObject private var uiState: ToraUIState
    @Binding private var showsAddTorrent: Bool

    public init(showsAddTorrent: Binding<Bool>) {
        self._showsAddTorrent = showsAddTorrent
    }

    public var body: some View {
        List {
            if uiState.torrents.isEmpty {
                ContentUnavailableView("No Torrents", systemImage: "arrow.down.circle", description: Text("Add a torrent file or magnet link to begin."))
            } else {
                ForEach(uiState.torrents, id: \.id) { torrent in
                    Button {
                        uiState.selectedTorrentID = torrent.id
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(torrent.name)
                                .font(.headline)
                                .lineLimit(1)
                            ProgressView(value: torrent.progress)
                            Text("\(torrent.state.rawValue) - \(Int(torrent.progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .toolbar {
            Button {
                showsAddTorrent = true
            } label: {
                Label("Add Torrent", systemImage: "plus")
            }

            Button {
                Task {
                    guard let id = uiState.selectedTorrentID else { return }
                    try? await uiState.torrentService.pauseTorrent(id)
                    await uiState.refresh()
                }
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .disabled(uiState.selectedTorrentID == nil)
        }
    }
}

public struct TorrentDetailView: View {
    @EnvironmentObject private var uiState: ToraUIState
    @State private var confirmsDeleteData = false

    public init() {}

    public var body: some View {
        if let torrent = uiState.selectedTorrent {
            Form {
                Text(torrent.name)
                    .font(.title2)
                ProgressView(value: torrent.progress)
                LabeledContent("State", value: torrent.state.rawValue)
                LabeledContent("Downloaded", value: ByteCountFormatter.string(fromByteCount: torrent.totalDone, countStyle: .file))
                LabeledContent("Wanted", value: ByteCountFormatter.string(fromByteCount: torrent.totalWanted, countStyle: .file))
                LabeledContent("Download rate", value: ByteCountFormatter.string(fromByteCount: torrent.downloadRate, countStyle: .file) + "/s")
                LabeledContent("Upload rate", value: ByteCountFormatter.string(fromByteCount: torrent.uploadRate, countStyle: .file) + "/s")

                HStack {
                    Button {
                        Task {
                            try? await uiState.torrentService.resumeTorrent(torrent.id)
                            await uiState.refresh()
                        }
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }

                    Button {
                        Task {
                            try? await uiState.torrentService.pauseTorrent(torrent.id)
                            await uiState.refresh()
                        }
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }

                    Button(role: .destructive) {
                        Task {
                            try? await uiState.torrentService.removeTorrent(torrent.id, mode: .removeTorrentOnly)
                            uiState.selectedTorrentID = nil
                            await uiState.refresh()
                        }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }

                    Button(role: .destructive) {
                        confirmsDeleteData = true
                    } label: {
                        Label("Remove Data", systemImage: "trash.slash")
                    }
                }
            }
            .padding()
            .confirmationDialog(
                "Remove torrent and delete downloaded data?",
                isPresented: $confirmsDeleteData,
                titleVisibility: .visible
            ) {
                Button("Delete Data", role: .destructive) {
                    Task {
                        try? await uiState.torrentService.removeTorrent(torrent.id, mode: .removeTorrentAndDownloadedData)
                        uiState.selectedTorrentID = nil
                        await uiState.refresh()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        } else {
            ContentUnavailableView("Select a Torrent", systemImage: "list.bullet.rectangle")
        }
    }
}

public struct AddTorrentView: View {
    @EnvironmentObject private var uiState: ToraUIState
    @Environment(\.dismiss) private var dismiss
    @State private var magnetLink = ""
    @State private var pendingTorrent: PendingTorrent?
    @State private var selectedFileIndexes = Set<Int>()
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    inspectTorrentFile()
                } label: {
                    Label("Choose Torrent File", systemImage: "doc.badge.plus")
                }

                TextField("Magnet link", text: $magnetLink)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await inspectMagnet() }
                } label: {
                    Label("Inspect", systemImage: "magnifyingglass")
                }
                .disabled(magnetLink.isEmpty)
            }

            if let pendingTorrent {
                Text(pendingTorrent.name)
                    .font(.headline)

                if pendingTorrent.files.isEmpty {
                    Text("Magnet metadata is not available yet. Add will start paused.")
                        .foregroundStyle(.secondary)
                } else {
                    List(pendingTorrent.files, id: \.index) { file in
                        Toggle(isOn: Binding(
                            get: { selectedFileIndexes.contains(file.index) },
                            set: { isSelected in
                                if isSelected {
                                    selectedFileIndexes.insert(file.index)
                                } else {
                                    selectedFileIndexes.remove(file.index)
                                }
                            }
                        )) {
                            HStack {
                                Text(file.path)
                                    .lineLimit(1)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(minHeight: 220)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Add Paused") {
                    Task { await addTorrent(startPaused: true) }
                }
                .disabled(pendingTorrent == nil)
                Button("Add and Start") {
                    Task { await addTorrent(startPaused: false) }
                }
                .disabled(pendingTorrent == nil || pendingTorrent?.files.isEmpty == true)
            }
        }
        .padding()
        .frame(width: 760, height: 460)
    }

    private func inspectTorrentFile() {
        let panel = NSOpenPanel()
        if let torrentType = UTType(filenameExtension: "torrent") {
            panel.allowedContentTypes = [torrentType]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let inspected = try await uiState.torrentService.inspectTorrentFile(url)
                pendingTorrent = inspected
                selectedFileIndexes = Set(inspected.files.map(\.index))
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func inspectMagnet() async {
        do {
            let inspected = try await uiState.torrentService.inspectMagnet(magnetLink)
            pendingTorrent = inspected
            selectedFileIndexes = []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addTorrent(startPaused: Bool) async {
        guard let pendingTorrent else { return }
        let selected = pendingTorrent.files.isEmpty ? Set<Int>() : selectedFileIndexes
        do {
            _ = try await uiState.torrentService.addTorrent(
                pendingTorrent,
                options: AddTorrentOptions(
                    downloadDirectory: uiState.defaultDownloadDirectory,
                    selectedFileIndexes: selected,
                    startPaused: startPaused
                )
            )
            await uiState.refresh()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct FileSelectionView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView("File Selection", systemImage: "checklist")
    }
}

public struct SettingsView: View {
    @EnvironmentObject private var uiState: ToraUIState

    public init() {}

    public var body: some View {
        Form {
            Toggle("Enable DHT", isOn: $uiState.settings.enableDHT)
            Toggle("Enable LSD", isOn: $uiState.settings.enableLSD)
            Toggle("Enable UPnP", isOn: $uiState.settings.enableUPnP)
            Toggle("Enable NAT-PMP", isOn: $uiState.settings.enableNATPMP)
            Toggle("Enable Peer Exchange", isOn: $uiState.settings.enablePeerExchange)
            Picker("Encryption", selection: $uiState.settings.encryptionPolicy) {
                Text("Enabled").tag(EncryptionPolicy.enabled)
                Text("Forced").tag(EncryptionPolicy.forced)
                Text("Disabled").tag(EncryptionPolicy.disabled)
            }
            Button("Save") {
                Task { await uiState.persistSettings() }
            }
        }
        .padding()
        .frame(width: 420)
    }
}
