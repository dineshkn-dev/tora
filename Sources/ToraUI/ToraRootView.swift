import SwiftUI
import AppKit
import ToraCore
import UniformTypeIdentifiers

public struct PasteMagnetAction {
    private let action: () -> Void

    public init(_ action: @escaping () -> Void) {
        self.action = action
    }

    public func callAsFunction() {
        action()
    }
}

public extension FocusedValues {
    var toraPasteMagnetAction: PasteMagnetAction? {
        get { self[PasteMagnetActionKey.self] }
        set { self[PasteMagnetActionKey.self] = newValue }
    }
}

private struct PasteMagnetActionKey: FocusedValueKey {
    typealias Value = PasteMagnetAction
}

@MainActor
public final class ToraUIState: ObservableObject {
    public let torrentService: TorrentServiceProtocol
    public let defaultDownloadDirectory: URL

    @Published public var torrents: [TorrentSnapshot] = []
    @Published public var selectedTorrentID: TorrentID?
    @Published public var settings: TorrentSessionSettings
    @Published public var lastError: String?
    @Published public var receivedMetadata: [TorrentID: PendingTorrent] = [:]

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
            } else if case .metadataReceived(let id, let pending) = event {
                receivedMetadata[id] = pending
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
            try await torrentService.updateSettings(settings)
        } catch {
            lastError = error.localizedDescription
        }
    }
}

public struct ToraRootView: View {
    @EnvironmentObject private var uiState: ToraUIState
    @State private var showsAddTorrent = false
    @State private var searchText = ""
    @State private var filter = TorrentFilter.all
    @State private var inspectorTab = TorrentInspectorTab.general

    public init() {}

    public var body: some View {
        NavigationSplitView {
            TorrentCategorySidebar(
                filter: $filter,
                showsAddTorrent: $showsAddTorrent
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
        } detail: {
            TorrentShellView(
                showsAddTorrent: $showsAddTorrent,
                searchText: $searchText,
                filter: $filter,
                inspectorTab: $inspectorTab
            )
        }
        .navigationTitle("Tora")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await uiState.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    showsAddTorrent = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .keyboardShortcut("n")
            }
        }
        .sheet(isPresented: $showsAddTorrent) {
            AddTorrentView(isPresented: $showsAddTorrent)
                .environmentObject(uiState)
        }
        .frame(minWidth: 1120, minHeight: 720)
        .task {
            while !Task.isCancelled {
                await uiState.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private enum TorrentFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case downloading = "Downloading"
    case seeding = "Seeding"
    case completed = "Completed"
    case paused = "Paused"
    case active = "Active"
    case metadata = "Metadata"
    case error = "Errors"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .downloading: "arrow.down.circle"
        case .seeding: "arrow.up.circle"
        case .completed: "checkmark.circle"
        case .paused: "pause.circle"
        case .active: "bolt.circle"
        case .metadata: "magnifyingglass.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    func matches(_ torrent: TorrentSnapshot) -> Bool {
        switch self {
        case .all:
            true
        case .downloading:
            torrent.state == .downloading
        case .seeding:
            torrent.state == .seeding
        case .completed:
            torrent.state == .finished || torrent.progress >= 1
        case .paused:
            torrent.state == .paused
        case .active:
            torrent.downloadRate > 0 || torrent.uploadRate > 0
        case .metadata:
            !torrent.hasMetadata || torrent.state == .downloadingMetadata
        case .error:
            torrent.state == .error
        }
    }
}

private enum TorrentInspectorTab: String, CaseIterable, Identifiable {
    case general = "General"
    case files = "Files"
    case trackers = "Trackers"
    case peers = "Peers"
    case log = "Log"

    var id: String { rawValue }
}

private struct TorrentCategorySidebar: View {
    @EnvironmentObject private var uiState: ToraUIState
    @Binding var filter: TorrentFilter
    @Binding var showsAddTorrent: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tora")
                            .font(.title2.weight(.semibold))
                        Text("\(uiState.torrents.count) torrents")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    SidebarStat(title: "Down", value: rate(uiState.torrents.map(\.downloadRate).reduce(0, +)))
                    SidebarStat(title: "Up", value: rate(uiState.torrents.map(\.uploadRate).reduce(0, +)))
                }
            }
            .padding(16)

            List(selection: $filter) {
                Section("Library") {
                    ForEach(TorrentFilter.allCases) { item in
                        Label {
                            HStack {
                                Text(item.rawValue)
                                Spacer()
                                Text("\(uiState.torrents.filter(item.matches).count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: item.icon)
                        }
                        .tag(item)
                        .contextMenu {
                            Button {
                                filter = item
                            } label: {
                                Label("Show \(item.rawValue)", systemImage: item.icon)
                            }
                            Button {
                                showsAddTorrent = true
                            } label: {
                                Label("Add Torrent", systemImage: "plus")
                            }
                            Button {
                                Task { await uiState.refresh() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                }

                Section("Automation") {
                    Label("RSS", systemImage: "dot.radiowaves.left.and.right")
                    Label("Scheduler", systemImage: "calendar.badge.clock")
                    Label("Labels", systemImage: "tag")
                }
                .foregroundStyle(.secondary)

                Section("Network") {
                    NetworkFlagRow(title: "DHT", isOn: uiState.settings.enableDHT)
                    NetworkFlagRow(title: "LSD", isOn: uiState.settings.enableLSD)
                    NetworkFlagRow(title: "PEX", isOn: uiState.settings.enablePeerExchange)
                }
            }
            .listStyle(.sidebar)

            Spacer(minLength: 0)

            Button {
                showsAddTorrent = true
            } label: {
                Label("Add Torrent", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(14)
            .contextMenu {
                Button {
                    showsAddTorrent = true
                } label: {
                    Label("Add Torrent", systemImage: "plus")
                }
                Button {
                    Task { await uiState.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .background(.bar)
    }
}

private struct NetworkFlagRow: View {
    let title: String
    let isOn: Bool

    var body: some View {
        HStack {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOn ? .green : .secondary)
            Text(title)
            Spacer()
            Text(isOn ? "On" : "Off")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TorrentShellView: View {
    @EnvironmentObject private var uiState: ToraUIState
    @Binding var showsAddTorrent: Bool
    @Binding var searchText: String
    @Binding var filter: TorrentFilter
    @Binding var inspectorTab: TorrentInspectorTab
    @State private var confirmsDeleteData = false

    private var visibleTorrents: [TorrentSnapshot] {
        uiState.torrents
            .filter(filter.matches)
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted {
                if $0.state == $1.state {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return stateRank($0.state) < stateRank($1.state)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            TorrentSummaryBar()
            Divider()
            toolbar
            Divider()
            TorrentTable(
                torrents: visibleTorrents,
                showsAddTorrent: $showsAddTorrent,
                selectTorrent: selectTorrent,
                startTorrent: { torrent in Task { await resume(torrent) } },
                pauseTorrent: { torrent in Task { await pause(torrent) } },
                removeTorrent: { torrent in Task { await remove(torrent, mode: .removeTorrentOnly) } },
                confirmDeleteData: { torrent in
                    selectTorrent(torrent)
                    confirmsDeleteData = true
                }
            )
            Divider()
            TorrentInspector(tab: $inspectorTab)
        }
        .safeAreaInset(edge: .bottom) {
            if let lastError = uiState.lastError {
                ErrorBanner(message: lastError) {
                    uiState.lastError = nil
                }
            }
        }
        .confirmationDialog(
            "Remove torrent and delete downloaded data?",
            isPresented: $confirmsDeleteData,
            titleVisibility: .visible
        ) {
            Button("Delete Data", role: .destructive) {
                Task { await removeSelected(.removeTorrentAndDownloadedData) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { showsAddTorrent = true } label: {
                Label("Add", systemImage: "plus")
            }
            .keyboardShortcut("n")

            Button { Task { await resumeSelected() } } label: {
                Label(selectedStartTitle, systemImage: "play.fill")
            }
            .disabled(!canStartSelected)

            Button { Task { await pauseSelected() } } label: {
                Label(selectedPauseTitle, systemImage: selectedPauseIcon)
            }
            .disabled(!canPauseSelected)

            Button(role: .destructive) { Task { await removeSelected(.removeTorrentOnly) } } label: {
                Label("Remove", systemImage: "trash")
            }
            .disabled(uiState.selectedTorrent == nil)

            Menu {
                Button(role: .destructive) {
                    confirmsDeleteData = true
                } label: {
                    Label("Remove and Delete Data", systemImage: "trash.slash")
                }
                .disabled(uiState.selectedTorrent == nil)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .disabled(uiState.selectedTorrent == nil)

            Spacer()

            Picker("Filter", selection: $filter) {
                ForEach(TorrentFilter.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon).tag(item)
                }
            }
            .labelsHidden()
            .frame(width: 170)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 240)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .buttonStyle(.bordered)
    }

    private var canStartSelected: Bool {
        uiState.selectedTorrent.map(canStart) ?? false
    }

    private var canPauseSelected: Bool {
        uiState.selectedTorrent.map(canPause) ?? false
    }

    private var selectedStartTitle: String {
        uiState.selectedTorrent.map(startTitle) ?? "Start"
    }

    private var selectedPauseTitle: String {
        uiState.selectedTorrent.map(pauseTitle) ?? "Pause"
    }

    private var selectedPauseIcon: String {
        guard uiState.selectedTorrent?.state == .seeding else { return "pause.fill" }
        return "stop.fill"
    }

    private func resumeSelected() async {
        guard let torrent = uiState.selectedTorrent else { return }
        await resume(torrent)
    }

    private func pauseSelected() async {
        guard let torrent = uiState.selectedTorrent else { return }
        await pause(torrent)
    }

    private func removeSelected(_ mode: RemoveMode) async {
        guard let torrent = uiState.selectedTorrent else { return }
        await remove(torrent, mode: mode)
    }

    private func selectTorrent(_ torrent: TorrentSnapshot) {
        uiState.selectedTorrentID = torrent.id
    }

    private func resume(_ torrent: TorrentSnapshot) async {
        do {
            try await uiState.torrentService.resumeTorrent(torrent.id)
            uiState.lastError = nil
            await uiState.refresh()
        } catch {
            uiState.lastError = error.localizedDescription
        }
    }

    private func pause(_ torrent: TorrentSnapshot) async {
        do {
            try await uiState.torrentService.pauseTorrent(torrent.id)
            uiState.lastError = nil
            await uiState.refresh()
        } catch {
            uiState.lastError = error.localizedDescription
        }
    }

    private func remove(_ torrent: TorrentSnapshot, mode: RemoveMode) async {
        do {
            try await uiState.torrentService.removeTorrent(torrent.id, mode: mode)
            if uiState.selectedTorrentID == torrent.id {
                uiState.selectedTorrentID = nil
            }
            uiState.lastError = nil
            await uiState.refresh()
        } catch {
            uiState.lastError = error.localizedDescription
        }
    }
}

private struct TorrentSummaryBar: View {
    @EnvironmentObject private var uiState: ToraUIState

    var body: some View {
        HStack(spacing: 12) {
            SummaryCell(title: "Torrents", value: "\(uiState.torrents.count)", icon: "tray.full")
            SummaryCell(title: "Active", value: "\(uiState.torrents.filter { $0.downloadRate > 0 || $0.uploadRate > 0 }.count)", icon: "bolt.circle")
            SummaryCell(title: "Seeding", value: "\(uiState.torrents.filter { $0.state == .seeding }.count)", icon: "arrow.up.circle")
            SummaryCell(title: "Down", value: rate(uiState.torrents.map(\.downloadRate).reduce(0, +)), icon: "arrow.down")
            SummaryCell(title: "Up", value: rate(uiState.torrents.map(\.uploadRate).reduce(0, +)), icon: "arrow.up")
            SummaryCell(title: "Done", value: bytes(uiState.torrents.map(\.totalDone).reduce(0, +)), icon: "checkmark.circle")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SummaryCell: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 128, alignment: .leading)
    }
}

private struct TorrentTable: View {
    @EnvironmentObject private var uiState: ToraUIState
    let torrents: [TorrentSnapshot]
    @Binding var showsAddTorrent: Bool
    let selectTorrent: (TorrentSnapshot) -> Void
    let startTorrent: (TorrentSnapshot) -> Void
    let pauseTorrent: (TorrentSnapshot) -> Void
    let removeTorrent: (TorrentSnapshot) -> Void
    let confirmDeleteData: (TorrentSnapshot) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TorrentTableHeader()
            if torrents.isEmpty {
                EmptyTorrentTable {
                    showsAddTorrent = true
                }
            } else {
                List(selection: $uiState.selectedTorrentID) {
                    ForEach(torrents, id: \.id) { torrent in
                        TorrentTableRow(torrent: torrent)
                            .tag(torrent.id)
                            .contextMenu {
                                TorrentContextMenu(
                                    torrent: torrent,
                                    start: {
                                        selectTorrent(torrent)
                                        startTorrent(torrent)
                                    },
                                    pause: {
                                        selectTorrent(torrent)
                                        pauseTorrent(torrent)
                                    },
                                    refresh: {
                                        selectTorrent(torrent)
                                        Task { await uiState.refresh() }
                                    },
                                    remove: {
                                        selectTorrent(torrent)
                                        removeTorrent(torrent)
                                    },
                                    deleteData: {
                                        confirmDeleteData(torrent)
                                    }
                                )
                            }
                    }
                }
                .listStyle(.plain)
                .contextMenu {
                    Button {
                        showsAddTorrent = true
                    } label: {
                        Label("Add Torrent", systemImage: "plus")
                    }
                    Button {
                        Task { await uiState.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .frame(minHeight: 280)
    }
}

private struct TorrentContextMenu: View {
    let torrent: TorrentSnapshot
    let start: () -> Void
    let pause: () -> Void
    let refresh: () -> Void
    let remove: () -> Void
    let deleteData: () -> Void

    var body: some View {
        Button(action: start) {
            Label(startTitle(torrent), systemImage: "play.fill")
        }
        .disabled(!canStart(torrent))
        Button(action: pause) {
            Label(pauseTitle(torrent), systemImage: torrent.state == .seeding ? "stop.fill" : "pause.fill")
        }
        .disabled(!canPause(torrent))
        Button(action: refresh) {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        Divider()
        Button {
            copyToPasteboard(torrent.name)
        } label: {
            Label("Copy Name", systemImage: "doc.on.doc")
        }
        Button {
            copyToPasteboard(torrent.id.rawValue)
        } label: {
            Label("Copy Info Hash", systemImage: "number")
        }
        Divider()
        Button(role: .destructive, action: remove) {
            Label("Remove", systemImage: "trash")
        }
        Button(role: .destructive, action: deleteData) {
            Label("Remove and Delete Data", systemImage: "trash.slash")
        }
    }
}

private struct TorrentTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Status").frame(width: 116, alignment: .leading)
            Text("Progress").frame(width: 130, alignment: .leading)
            Text("Down").frame(width: 90, alignment: .trailing)
            Text("Up").frame(width: 90, alignment: .trailing)
            Text("Size").frame(width: 100, alignment: .trailing)
            Text("ETA").frame(width: 80, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct TorrentTableRow: View {
    let torrent: TorrentSnapshot

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: stateIcon)
                    .foregroundStyle(stateColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(torrent.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(torrent.id.rawValue)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(statusTitle)
                .frame(width: 116, alignment: .leading)

            HStack(spacing: 8) {
                ProgressView(value: torrent.progress)
                    .frame(width: 78)
                Text("\(Int(torrent.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 38, alignment: .trailing)
            }
            .frame(width: 130, alignment: .leading)

            Text(rate(torrent.downloadRate)).frame(width: 90, alignment: .trailing)
            Text(rate(torrent.uploadRate)).frame(width: 90, alignment: .trailing)
            Text(bytes(torrent.totalWanted)).frame(width: 100, alignment: .trailing)
            Text(etaText).frame(width: 80, alignment: .trailing)
        }
        .font(.callout)
        .padding(.vertical, 6)
    }

    private var statusTitle: String {
        if !torrent.hasMetadata { return "Metadata" }
        if torrent.state == .seeding {
            return "Seeding \(seedRatio(torrent.seedRatio))"
        }
        return torrent.state.rawValue.capitalized
    }

    private var etaText: String {
        if torrent.state == .seeding {
            return duration(Double(torrent.seedingSeconds))
        }
        guard torrent.downloadRate > 0, torrent.totalWanted > torrent.totalDone else { return "∞" }
        return duration(Double(torrent.totalWanted - torrent.totalDone) / Double(torrent.downloadRate))
    }

    private var stateIcon: String {
        switch torrent.state {
        case .paused: "pause.circle"
        case .downloading, .downloadingMetadata: "arrow.down.circle"
        case .seeding: "arrow.up.circle"
        case .finished: "checkmark.circle"
        case .checking: "magnifyingglass.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    private var stateColor: Color {
        switch torrent.state {
        case .error: .red
        case .finished, .seeding: .green
        case .paused: .secondary
        default: .accentColor
        }
    }
}

private struct EmptyTorrentTable: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No torrents")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .contextMenu {
            Button(action: add) {
                Label("Add Torrent", systemImage: "plus")
            }
        }
    }
}

private struct TorrentInspector: View {
    @EnvironmentObject private var uiState: ToraUIState
    @Binding var tab: TorrentInspectorTab

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $tab) {
                ForEach(TorrentInspectorTab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            Group {
                if let torrent = uiState.selectedTorrent {
                    switch tab {
                    case .general:
                        GeneralInspector(torrent: torrent)
                    case .files:
                        FilesInspector(torrent: torrent)
                    case .trackers:
                        TrackersInspector(torrent: torrent)
                    case .peers:
                        KeyValueInspector(rows: [
                            ("State", torrent.state.rawValue),
                            ("Download", rate(torrent.downloadRate)),
                            ("Upload", rate(torrent.uploadRate))
                        ])
                    case .log:
                        KeyValueInspector(rows: [
                            ("ID", torrent.id.rawValue),
                            ("Last Error", uiState.lastError ?? "None"),
                            ("Download Directory", uiState.defaultDownloadDirectory.path)
                        ])
                    }
                } else {
                    Text("Select a torrent")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contextMenu {
                            Button {
                                Task { await uiState.refresh() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                }
            }
            .frame(height: 190)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct GeneralInspector: View {
    let torrent: TorrentSnapshot

    var body: some View {
        KeyValueInspector(rows: [
            ("Name", torrent.name),
            ("State", torrent.hasMetadata ? torrent.state.rawValue : "metadata"),
            ("Progress", "\(Int(torrent.progress * 100))%"),
            ("Downloaded", "\(bytes(torrent.totalDone)) of \(bytes(torrent.totalWanted))"),
            ("Uploaded", bytes(torrent.totalUploaded)),
            ("Seed Ratio", seedRatio(torrent.seedRatio)),
            ("Seeding Time", duration(Double(torrent.seedingSeconds))),
            ("Download Rate", rate(torrent.downloadRate)),
            ("Upload Rate", rate(torrent.uploadRate)),
            ("Info Hash", torrent.id.rawValue)
        ])
    }
}

private struct FilesInspector: View {
    @EnvironmentObject private var uiState: ToraUIState
    let torrent: TorrentSnapshot

    var body: some View {
        if let pending = uiState.receivedMetadata[torrent.id], !pending.files.isEmpty {
            List(pending.files, id: \.index) { file in
                HStack {
                    Text(file.path).lineLimit(1)
                    Spacer()
                    Text(bytes(file.size)).foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button {
                        copyToPasteboard(file.path)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }
                    Button {
                        copyToPasteboard(bytes(file.size))
                    } label: {
                        Label("Copy Size", systemImage: "number")
                    }
                }
            }
            .listStyle(.plain)
        } else {
            KeyValueInspector(rows: [
                ("Files", torrent.hasMetadata ? "Available after metadata refresh" : "Waiting for metadata"),
                ("Selected Size", bytes(torrent.totalWanted))
            ])
        }
    }
}

private struct TrackersInspector: View {
    let torrent: TorrentSnapshot

    var body: some View {
        KeyValueInspector(rows: [
            ("Source", torrent.hasMetadata ? "Torrent metadata" : "Magnet metadata"),
            ("Tracker Status", "Managed by libtorrent"),
            ("DHT", "Controlled in Settings")
        ])
    }
}

private struct KeyValueInspector: View {
    let rows: [(String, String)]

    var body: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                ForEach(rows, id: \.0) { row in
                    GridRow {
                        Text(row.0)
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .leading)
                        Text(row.1)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .contextMenu {
                                Button {
                                    copyToPasteboard(row.1)
                                } label: {
                                    Label("Copy Value", systemImage: "doc.on.doc")
                                }
                            }
                    }
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
            Text(message).lineLimit(2)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .font(.callout)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
        .padding()
    }
}

private struct CommandVPasteMonitor: NSViewRepresentable {
    let paste: () -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.paste = paste
    }

    func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(paste: paste)
    }

    final class Coordinator {
        var paste: () -> Void
        private var monitor: Any?

        init(paste: @escaping () -> Void) {
            self.paste = paste
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let isCommandV = flags == .command && event.charactersIgnoringModifiers?.lowercased() == "v"
                guard isCommandV else { return event }
                self.paste()
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            uninstall()
        }
    }
}

private struct MagnetTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onPaste: () -> Void
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> PastingTextField {
        let field = PastingTextField()
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.isEditable = true
        field.isSelectable = true
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.onPaste = onPaste
        field.onSubmit = onSubmit

        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: PastingTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.onPaste = onPaste
        nsView.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }
    }

    final class PastingTextField: NSTextField {
        var onPaste: (() -> Void)?
        var onSubmit: (() -> Void)?

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
                onPaste?()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        override func textDidEndEditing(_ notification: Notification) {
            super.textDidEndEditing(notification)
            if let movement = notification.userInfo?["NSTextMovement"] as? Int,
               movement == NSReturnTextMovement {
                onSubmit?()
            }
        }
    }
}

public struct TorrentSidebar: View {
    @EnvironmentObject private var uiState: ToraUIState
    @Binding private var showsAddTorrent: Bool

    public init(showsAddTorrent: Binding<Bool>) {
        self._showsAddTorrent = showsAddTorrent
    }

    public var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            if uiState.torrents.isEmpty {
                EmptySidebarView {
                    showsAddTorrent = true
                }
            } else {
                List(selection: $uiState.selectedTorrentID) {
                    ForEach(uiState.torrents, id: \.id) { torrent in
                        TorrentRow(torrent: torrent)
                            .tag(torrent.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(.bar)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tora")
                        .font(.title2.weight(.semibold))
                    Text("\(uiState.torrents.count) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showsAddTorrent = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Add torrent")
            }

            HStack(spacing: 8) {
                SidebarStat(title: "Down", value: rate(uiState.torrents.map(\.downloadRate).reduce(0, +)))
                SidebarStat(title: "Up", value: rate(uiState.torrents.map(\.uploadRate).reduce(0, +)))
            }
        }
        .padding(16)
    }
}

private struct SidebarStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmptySidebarView: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("No torrents")
                    .font(.headline)
                Text("Add a torrent file or magnet link.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                add()
            } label: {
                Label("Add Torrent", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TorrentRow: View {
    let torrent: TorrentSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(torrent.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(torrent.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: torrent.progress)
                .controlSize(.small)
            HStack {
                Label(rate(torrent.downloadRate), systemImage: "arrow.down")
                Spacer()
                Label(rate(torrent.uploadRate), systemImage: "arrow.up")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

public struct TorrentDetailView: View {
    @EnvironmentObject private var uiState: ToraUIState
    @Binding private var showsAddTorrent: Bool
    @State private var confirmsDeleteData = false

    public init(showsAddTorrent: Binding<Bool>) {
        self._showsAddTorrent = showsAddTorrent
    }

    public var body: some View {
        Group {
            if let torrent = uiState.selectedTorrent {
                DetailContent(torrent: torrent, confirmsDeleteData: $confirmsDeleteData)
            } else {
                EmptyDetailView {
                    showsAddTorrent = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .safeAreaInset(edge: .bottom) {
            if let lastError = uiState.lastError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(lastError)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        uiState.lastError = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                .padding()
            }
        }
    }
}

private struct DetailContent: View {
    @EnvironmentObject private var uiState: ToraUIState
    let torrent: TorrentSnapshot
    @Binding var confirmsDeleteData: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    progressSection
                    if !torrent.hasMetadata {
                        metadataSection
                    }
                    metricsSection
                    locationSection
                }
                .padding(24)
                .frame(maxWidth: 860, alignment: .leading)
            }
        }
        .confirmationDialog(
            "Remove torrent and delete downloaded data?",
            isPresented: $confirmsDeleteData,
            titleVisibility: .visible
        ) {
            Button("Delete Data", role: .destructive) {
                Task {
                    do {
                        try await uiState.torrentService.removeTorrent(torrent.id, mode: .removeTorrentAndDownloadedData)
                        uiState.selectedTorrentID = nil
                        uiState.lastError = nil
                        await uiState.refresh()
                    } catch {
                        uiState.lastError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: stateIcon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(stateColor)
                .frame(width: 44, height: 44)
                .background(stateColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(torrent.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(torrent.state.rawValue)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !torrent.hasMetadata {
                Button {
                    Task {
                        do {
                            try await uiState.torrentService.fetchMetadata(torrent.id)
                            uiState.lastError = nil
                            await uiState.refresh()
                        } catch {
                            uiState.lastError = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Fetch Metadata", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
            }

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

            Menu {
                Button(role: .destructive) {
                    Task {
                        do {
                            try await uiState.torrentService.removeTorrent(torrent.id, mode: .removeTorrentOnly)
                            uiState.selectedTorrentID = nil
                            uiState.lastError = nil
                            await uiState.refresh()
                        } catch {
                            uiState.lastError = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Remove Torrent", systemImage: "trash")
                }
                Button(role: .destructive) {
                    confirmsDeleteData = true
                } label: {
                    Label("Remove and Delete Data", systemImage: "trash.slash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
        }
        .padding(24)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Progress")
                    .font(.headline)
                Spacer()
                Text("\(Int(torrent.progress * 100))%")
                    .font(.headline.monospacedDigit())
            }
            ProgressView(value: torrent.progress)
            HStack {
                Text(bytes(torrent.totalDone))
                Text("of")
                    .foregroundStyle(.secondary)
                Text(bytes(torrent.totalWanted))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Metadata needed", systemImage: "info.circle")
                .font(.headline)
            Text("This magnet has not discovered its file list yet. Click Fetch Metadata to connect only for metadata without downloading payload data. If it stays idle, enable DHT in Settings or use a magnet link that includes trackers.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !uiState.settings.enableDHT {
                HStack {
                    Label("DHT is currently off. Most magnet links need DHT unless they include trackers.", systemImage: "network.slash")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Enable DHT") {
                        Task {
                            uiState.settings.enableDHT = true
                            await uiState.persistSettings()
                            do {
                                try await uiState.torrentService.fetchMetadata(torrent.id)
                                uiState.lastError = nil
                                await uiState.refresh()
                            } catch {
                                uiState.lastError = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var metricsSection: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                MetricTile(title: "Download", value: rate(torrent.downloadRate), icon: "arrow.down")
                MetricTile(title: "Upload", value: rate(torrent.uploadRate), icon: "arrow.up")
                MetricTile(title: "Done", value: bytes(torrent.totalDone), icon: "checkmark.circle")
            }
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Downloads")
                .font(.headline)
            Text(uiState.defaultDownloadDirectory.path)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var stateIcon: String {
        switch torrent.state {
        case .paused: "pause.circle"
        case .downloading, .downloadingMetadata: "arrow.down.circle"
        case .seeding: "arrow.up.circle"
        case .finished: "checkmark.circle"
        case .checking: "magnifyingglass.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    private var stateColor: Color {
        switch torrent.state {
        case .error: .red
        case .finished, .seeding: .green
        case .paused: .secondary
        default: .accentColor
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 150, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmptyDetailView: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Ready to Download")
                    .font(.title2.weight(.semibold))
                Text("Add a torrent file or magnet link. Tora validates paths before anything starts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Button {
                add()
            } label: {
                Label("Add Torrent", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

public struct AddTorrentView: View {
    @EnvironmentObject private var uiState: ToraUIState
    @Binding private var isPresented: Bool
    @FocusState private var magnetFieldIsFocused: Bool
    @State private var magnetLink = ""
    @State private var pendingTorrent: PendingTorrent?
    @State private var metadataTorrentID: TorrentID?
    @State private var selectedFileIndexes = Set<Int>()
    @State private var downloadDirectory: URL?
    @State private var startPaused = false
    @State private var errorMessage: String?
    @State private var isFetchingMetadata = false
    @State private var autoInspectTask: Task<Void, Never>?
    @State private var lastAutoInspectedMagnet = ""

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Torrent")
                        .font(.title2.weight(.semibold))
                    Text(headerSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isFetchingMetadata {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(24)

            Divider()

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Button {
                                    inspectTorrentFile()
                                } label: {
                                    Label("Open File", systemImage: "doc.badge.plus")
                                }
                                .controlSize(.large)

                                MagnetTextField(
                                    text: $magnetLink,
                                    placeholder: "Paste magnet link",
                                    onPaste: pasteMagnetLink,
                                    onSubmit: {
                                        Task { await inspectMagnetAndFetchMetadata() }
                                    }
                                )
                                .frame(height: 32)

                                Button {
                                    pasteMagnetLink()
                                } label: {
                                    Label("Paste", systemImage: "doc.on.clipboard")
                                }
                                .controlSize(.large)
                                .help("Paste and inspect a magnet link")
                            }

                            HStack {
                                Button {
                                    Task { await inspectMagnetAndFetchMetadata() }
                                } label: {
                                    Label(isFetchingMetadata ? "Fetching Metadata" : "Inspect Magnet", systemImage: "magnifyingglass")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(magnetLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isFetchingMetadata)

                                if pendingTorrent?.files.isEmpty == true {
                                    Text("Metadata only. Payload files stay blocked until you choose files.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .padding(10)
                    } label: {
                        Label("Source", systemImage: "link")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                Text(effectiveDownloadDirectory.path)
                                    .font(.callout.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Choose...") {
                                    chooseDownloadDirectory()
                                }
                            }

                            Toggle("Start torrent after adding", isOn: Binding(
                                get: { !startPaused },
                                set: { startPaused = !$0 }
                            ))
                            .toggleStyle(.checkbox)
                        }
                        .padding(10)
                    } label: {
                        Label("Save To", systemImage: "folder")
                    }

                    if let errorMessage {
                        ErrorInlineView(message: errorMessage) {
                            self.errorMessage = nil
                        }
                    }
                }
                .frame(width: 420)

                if let pendingTorrent {
                    PendingTorrentPanel(
                        pendingTorrent: pendingTorrent,
                        selectedFileIndexes: $selectedFileIndexes,
                        isFetchingMetadata: isFetchingMetadata,
                        fetchMetadata: { Task { await fetchMetadata() } }
                    )
                } else {
                    AddTorrentPlaceholder()
                }
            }
            .padding(24)

            Spacer(minLength: 0)
            Divider()

            HStack {
                Text(footerSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Cancel") {
                    close()
                }
                Button("Add Paused") {
                    Task { await addTorrent(startPaused: true) }
                }
                .disabled(!canAddTorrent)
                if pendingTorrent?.files.isEmpty == true {
                    Button("Fetch Metadata") {
                        Task { await fetchMetadata() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pendingTorrent == nil || isFetchingMetadata)
                } else {
                    Button(startPaused ? "Add" : "Add and Start") {
                        Task { await addTorrent(startPaused: startPaused) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAddTorrent)
                }
            }
            .padding(18)
        }
        .frame(width: 980, height: 650)
        .onAppear {
            downloadDirectory = uiState.defaultDownloadDirectory
            magnetFieldIsFocused = true
        }
        .background(CommandVPasteMonitor {
            pasteMagnetLink()
        })
        .focusedSceneValue(\.toraPasteMagnetAction, PasteMagnetAction {
            pasteMagnetLink()
        })
        .onChange(of: magnetLink) { _, newValue in
            scheduleAutoInspect(for: newValue)
        }
        .onDisappear {
            autoInspectTask?.cancel()
        }
    }

    private func close() {
        isPresented = false
    }

    private var effectiveDownloadDirectory: URL {
        downloadDirectory ?? uiState.defaultDownloadDirectory
    }

    private var canAddTorrent: Bool {
        guard let pendingTorrent, !isFetchingMetadata else { return false }
        return !pendingTorrent.files.isEmpty && !selectedFileIndexes.isEmpty
    }

    private var selectedSize: Int64 {
        guard let pendingTorrent else { return 0 }
        return pendingTorrent.files
            .filter { selectedFileIndexes.contains($0.index) }
            .map(\.size)
            .reduce(0, +)
    }

    private var headerSubtitle: String {
        guard let pendingTorrent else {
            return "Open a torrent file or paste a magnet link, then review before anything downloads."
        }
        if pendingTorrent.files.isEmpty {
            return "Fetching metadata so you can choose files before payload download starts."
        }
        return "Review \(pendingTorrent.files.count) files and choose what Tora should download."
    }

    private var footerSummary: String {
        guard let pendingTorrent else {
            return "Nothing will download until a source is inspected."
        }
        if pendingTorrent.files.isEmpty {
            return "Waiting for metadata. Save location: \(effectiveDownloadDirectory.path)"
        }
        return "\(selectedFileIndexes.count) of \(pendingTorrent.files.count) files selected, \(bytes(selectedSize))"
    }

    private func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = effectiveDownloadDirectory
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        downloadDirectory = url
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
                metadataTorrentID = nil
                downloadDirectory = effectiveDownloadDirectory
                selectedFileIndexes = Set(inspected.files.map(\.index))
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func inspectMagnet() async {
        magnetLink = magnetLink.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let inspected = try await uiState.torrentService.inspectMagnet(magnetLink)
            pendingTorrent = inspected
            metadataTorrentID = nil
            selectedFileIndexes = []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func inspectMagnetAndFetchMetadata(cancelScheduled: Bool = true) async {
        if cancelScheduled {
            autoInspectTask?.cancel()
        }
        await inspectMagnet()
        if pendingTorrent != nil {
            await fetchMetadata()
        }
    }

    private func scheduleAutoInspect(for rawValue: String) {
        autoInspectTask?.cancel()

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("magnet:?") else { return }
        guard trimmed != lastAutoInspectedMagnet else { return }
        guard !isFetchingMetadata else { return }

        autoInspectTask = Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let current = magnetLink.trimmingCharacters(in: .whitespacesAndNewlines)
                guard current == trimmed else { return }
                lastAutoInspectedMagnet = trimmed
            }
            await inspectMagnetAndFetchMetadata(cancelScheduled: false)
        }
    }

    private func pasteMagnetLink() {
        guard let clipboard = NSPasteboard.general.string(forType: .string) else {
            errorMessage = "Clipboard does not contain text."
            return
        }

        let pasted = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pasted.isEmpty else {
            errorMessage = "Clipboard text is empty."
            return
        }

        magnetLink = pasted
        magnetFieldIsFocused = true
        errorMessage = nil
    }

    private func addTorrent(startPaused: Bool) async {
        guard let pendingTorrent else { return }
        let selected = pendingTorrent.files.isEmpty ? Set<Int>() : selectedFileIndexes
        do {
            if let metadataTorrentID {
                try await uiState.torrentService.setFileSelectionAndStart(
                    metadataTorrentID,
                    selectedFileIndexes: selected,
                    startPaused: startPaused
                )
            } else {
                _ = try await uiState.torrentService.addTorrent(
                    pendingTorrent,
                    options: AddTorrentOptions(
                        downloadDirectory: effectiveDownloadDirectory,
                        selectedFileIndexes: selected,
                        startPaused: startPaused
                    )
                )
            }
            await uiState.refresh()
            close()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchMetadata() async {
        guard let pendingTorrent else { return }
        do {
            isFetchingMetadata = true
            defer { isFetchingMetadata = false }
            if !uiState.settings.enableDHT {
                errorMessage = TorrentServiceError.dhtRequiredForMagnetMetadata.localizedDescription
                return
            }
            let id: TorrentID
            if let metadataTorrentID {
                id = metadataTorrentID
                try await uiState.torrentService.fetchMetadata(id)
            } else {
                id = try await uiState.torrentService.addTorrent(
                    pendingTorrent,
                    options: AddTorrentOptions(
                        downloadDirectory: effectiveDownloadDirectory,
                        selectedFileIndexes: [],
                        startPaused: false,
                        fetchMetadataOnly: true
                    )
                )
                metadataTorrentID = id
                uiState.selectedTorrentID = id
            }

            for _ in 0..<180 {
                await uiState.refresh()
                let source = TorrentSource.magnet(magnetLink)
                if let metadata = try await uiState.torrentService.metadataForTorrent(id, source: source)
                    ?? uiState.receivedMetadata[id] {
                    let updated = PendingTorrent(
                        name: metadata.name,
                        infoHash: metadata.infoHash,
                        files: metadata.files,
                        source: source
                    )
                    self.pendingTorrent = updated
                    self.metadataTorrentID = nil
                    self.selectedFileIndexes = Set(updated.files.map(\.index))
                    self.errorMessage = nil
                    return
                }
                try await Task.sleep(for: .milliseconds(500))
            }
            errorMessage = "Metadata is still pending. This usually means no reachable peers yet. Keep this window open, wait longer, or use a magnet with trackers."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PendingTorrentPanel: View {
    let pendingTorrent: PendingTorrent
    @Binding var selectedFileIndexes: Set<Int>
    let isFetchingMetadata: Bool
    let fetchMetadata: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                if pendingTorrent.files.isEmpty {
                    metadataState
                } else {
                    fileToolbar
                    fileList
                }
            }
            .padding(10)
        } label: {
            Label("Contents", systemImage: "list.bullet.rectangle")
        }
        .frame(maxWidth: .infinity, minHeight: 430, maxHeight: .infinity)
        .contextMenu {
            if pendingTorrent.files.isEmpty {
                Button(action: fetchMetadata) {
                    Label("Fetch Metadata", systemImage: "magnifyingglass")
                }
                .disabled(isFetchingMetadata)
            } else {
                Button {
                    selectedFileIndexes = Set(pendingTorrent.files.map(\.index))
                } label: {
                    Label("Select All Files", systemImage: "checkmark.circle")
                }
                Button {
                    selectedFileIndexes.removeAll()
                } label: {
                    Label("Select No Files", systemImage: "circle")
                }
                Button {
                    let all = Set(pendingTorrent.files.map(\.index))
                    selectedFileIndexes = all.subtracting(selectedFileIndexes)
                } label: {
                    Label("Invert Selection", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Divider()
            Button {
                copyToPasteboard(pendingTorrent.name)
            } label: {
                Label("Copy Torrent Name", systemImage: "doc.on.doc")
            }
            if let infoHash = pendingTorrent.infoHash, !infoHash.isEmpty {
                Button {
                    copyToPasteboard(infoHash)
                } label: {
                    Label("Copy Info Hash", systemImage: "number")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pendingTorrent.name)
                .font(.headline)
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Label(summary, systemImage: "doc")
                if let infoHash = pendingTorrent.infoHash, !infoHash.isEmpty {
                    Label(shortHash(infoHash), systemImage: "number")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var metadataState: some View {
        VStack(spacing: 16) {
            Image(systemName: isFetchingMetadata ? "magnifyingglass" : "pause.circle")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text(isFetchingMetadata ? "Fetching Metadata" : "Metadata Required")
                    .font(.headline)
                Text(isFetchingMetadata
                     ? "Tora is connecting only long enough to discover the file list. Payload files are not downloading."
                     : "This magnet has no file list yet. Fetch metadata first, then choose exactly which files to download.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Button {
                fetchMetadata()
            } label: {
                Label(isFetchingMetadata ? "Fetching..." : "Fetch Metadata", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isFetchingMetadata)
        }
        .frame(maxWidth: .infinity, minHeight: 330)
    }

    private var fileToolbar: some View {
        HStack(spacing: 10) {
            Button("All") {
                selectedFileIndexes = Set(pendingTorrent.files.map(\.index))
            }
            Button("None") {
                selectedFileIndexes.removeAll()
            }
            Button("Invert") {
                let all = Set(pendingTorrent.files.map(\.index))
                selectedFileIndexes = all.subtracting(selectedFileIndexes)
            }
            Spacer()
            Text("\(selectedFileIndexes.count) selected - \(bytes(selectedSize))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Size")
                    .frame(width: 96, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.thinMaterial)

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
                    HStack(spacing: 10) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text(file.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(bytes(file.size))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .trailing)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.vertical, 2)
                .contextMenu {
                    Button {
                        if selectedFileIndexes.contains(file.index) {
                            selectedFileIndexes.remove(file.index)
                        } else {
                            selectedFileIndexes.insert(file.index)
                        }
                    } label: {
                        Label(
                            selectedFileIndexes.contains(file.index) ? "Deselect File" : "Select File",
                            systemImage: selectedFileIndexes.contains(file.index) ? "minus.circle" : "checkmark.circle"
                        )
                    }
                    Divider()
                    Button {
                        copyToPasteboard(file.path)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }
                    Button {
                        copyToPasteboard(bytes(file.size))
                    } label: {
                        Label("Copy Size", systemImage: "number")
                    }
                }
            }
            .listStyle(.plain)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.8), lineWidth: 1)
        }
    }

    private var selectedSize: Int64 {
        pendingTorrent.files
            .filter { selectedFileIndexes.contains($0.index) }
            .map(\.size)
            .reduce(0, +)
    }

    private var summary: String {
        if pendingTorrent.files.isEmpty {
            return "Magnet link"
        }
        let total = pendingTorrent.files.map(\.size).reduce(0, +)
        return "\(pendingTorrent.files.count) files - \(bytes(total))"
    }

    private func shortHash(_ hash: String) -> String {
        hash.count > 12 ? String(hash.prefix(12)) : hash
    }
}

private struct AddTorrentPlaceholder: View {
    var body: some View {
        GroupBox {
            VStack(spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    Text("No Torrent Selected")
                        .font(.headline)
                    Text("Open a .torrent file or paste a magnet link. Tora will inspect it before anything starts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 430)
            .padding(10)
        } label: {
            Label("Contents", systemImage: "list.bullet.rectangle")
        }
        .frame(maxWidth: .infinity)
        .contextMenu {
            Button {
                copyToPasteboard("No torrent selected")
            } label: {
                Label("Copy Status", systemImage: "doc.on.doc")
            }
        }
    }
}

private struct ErrorInlineView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

public struct FileSelectionView: View {
    public init() {}

    public var body: some View {
        EmptyView()
    }
}

public struct SettingsView: View {
    @EnvironmentObject private var uiState: ToraUIState

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Network")
                        .font(.title2.weight(.semibold))
                    Text("Network discovery and seeding policies are explicit and apply immediately after Save.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                    GridRow {
                        Toggle("DHT", isOn: $uiState.settings.enableDHT)
                        Toggle("LSD", isOn: $uiState.settings.enableLSD)
                    }
                    GridRow {
                        Toggle("UPnP", isOn: $uiState.settings.enableUPnP)
                        Toggle("NAT-PMP", isOn: $uiState.settings.enableNATPMP)
                    }
                    GridRow {
                        Toggle("Peer Exchange", isOn: $uiState.settings.enablePeerExchange)
                        Picker("Encryption", selection: $uiState.settings.encryptionPolicy) {
                            Text("Enabled").tag(EncryptionPolicy.enabled)
                            Text("Forced").tag(EncryptionPolicy.forced)
                            Text("Disabled").tag(EncryptionPolicy.disabled)
                        }
                        .frame(width: 220)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Seeding")
                        .font(.headline)
                    Text("Limits mark torrents as seed-goal met for queue priority. They do not delete files or auto-open anything.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        GridRow {
                            Text("Share ratio")
                                .foregroundStyle(.secondary)
                            TextField("Unlimited", text: optionalPercentBinding(\.seedRatioLimitPercent))
                                .frame(width: 110)
                            Text("%")
                                .foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("Seed time")
                                .foregroundStyle(.secondary)
                            TextField("Unlimited", text: optionalMinutesBinding(\.seedTimeLimitSeconds))
                                .frame(width: 110)
                            Text("minutes")
                                .foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("Seed time ratio")
                                .foregroundStyle(.secondary)
                            TextField("Unlimited", text: optionalPercentBinding(\.seedTimeRatioLimitPercent))
                                .frame(width: 110)
                            Text("%")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Spacer()
                    Button("Save") {
                        Task { await uiState.persistSettings() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 440)
    }

    private func optionalPercentBinding(_ keyPath: WritableKeyPath<TorrentSessionSettings, Int?>) -> Binding<String> {
        Binding(
            get: {
                uiState.settings[keyPath: keyPath].map(String.init) ?? ""
            },
            set: { value in
                uiState.settings[keyPath: keyPath] = sanitizedPositiveInt(value)
            }
        )
    }

    private func optionalMinutesBinding(_ keyPath: WritableKeyPath<TorrentSessionSettings, Int?>) -> Binding<String> {
        Binding(
            get: {
                guard let seconds = uiState.settings[keyPath: keyPath] else { return "" }
                return String(max(1, seconds / 60))
            },
            set: { value in
                uiState.settings[keyPath: keyPath] = sanitizedPositiveInt(value).map { $0 * 60 }
            }
        )
    }

    private func sanitizedPositiveInt(_ value: String) -> Int? {
        let digits = value.filter(\.isNumber)
        guard let parsed = Int(digits), parsed > 0 else { return nil }
        return parsed
    }
}

private func bytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

private func rate(_ value: Int64) -> String {
    "\(bytes(value))/s"
}

private func seedRatio(_ value: Double) -> String {
    String(format: "%.2fx", value)
}

private func copyToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}

private func canStart(_ torrent: TorrentSnapshot) -> Bool {
    switch torrent.state {
    case .paused, .finished, .error:
        true
    case .checking, .downloadingMetadata, .downloading, .seeding:
        false
    }
}

private func canPause(_ torrent: TorrentSnapshot) -> Bool {
    switch torrent.state {
    case .checking, .downloadingMetadata, .downloading, .seeding:
        true
    case .paused, .finished, .error:
        false
    }
}

private func startTitle(_ torrent: TorrentSnapshot) -> String {
    switch torrent.state {
    case .paused where torrent.progress >= 1:
        "Resume Seeding"
    case .paused:
        "Resume"
    case .finished:
        "Start Seeding"
    case .error:
        "Retry"
    default:
        "Start"
    }
}

private func pauseTitle(_ torrent: TorrentSnapshot) -> String {
    torrent.state == .seeding ? "Stop Seeding" : "Pause"
}

private func duration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "∞" }
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    if minutes > 0 {
        return "\(minutes)m \(secs)s"
    }
    return "\(secs)s"
}

private func stateRank(_ state: TorrentState) -> Int {
    switch state {
    case .downloading: 0
    case .downloadingMetadata: 1
    case .seeding: 2
    case .checking: 3
    case .paused: 4
    case .finished: 5
    case .error: 6
    }
}
