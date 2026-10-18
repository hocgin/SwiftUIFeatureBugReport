//
//  DeveloperPortalView.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import SwiftUI

enum PortalQueue: String, CaseIterable, Hashable {

    case open
    case reported
    case images
    case all

    var localised: String {

        switch self {

        case .open: return L10n.t("feedback.portal.queue.open")
        case .reported: return L10n.t("feedback.portal.queue.reported")
        case .images: return L10n.t("feedback.portal.queue.images")
        case .all: return L10n.t("feedback.portal.queue.all")
        }
    }

    var symbolName: String {

        switch self {

        case .open: return "tray"
        case .reported: return "flag"
        case .images: return "photo"
        case .all: return "list.bullet"
        }
    }
}


/// Developer-facing triage.
///
/// Shipping this view in every build is not a security hole: `FeedbackContainer.isDeveloper` decides
/// whether it is *offered*, and the `dev` security role decides whether its writes are *accepted*.
public struct DeveloperPortalView: View {

    @State private var store: FeedbackStore

    @State private var queue: PortalQueue = .open
    @State private var versionFilter: String?
    // Selected by ID, not by value: the struct is replaced wholesale on every reload,
    // so a value-based selection would silently drop each time the board refreshes.
    @State private var selection: CKRecord.ID?
    @State private var searchText = ""

    /// The request the delete confirmation is asking about. Held here rather than on the row so the
    /// dialog survives the list re-sorting underneath it.
    @State private var pendingDeletion: FeedbackRequest?

    private let embedsNavigationStack: Bool

    public init(configuration: FeedbackConfiguration, embedsNavigationStack: Bool = true) {

        self.init(store: FeedbackStore(configuration: configuration), embedsNavigationStack: embedsNavigationStack)
    }

    public init(store: FeedbackStore, embedsNavigationStack: Bool = true) {

        self.store = store
        self.embedsNavigationStack = embedsNavigationStack
    }

    public var body: some View {

        container
            .task {

                if !store.requests.hasLoadedOnce { await store.start() }

                // An `if` rather than the `guard` this replaced: the portal is usually reached from
                // the board's toolbar, so the board has already loaded and a `guard` would return
                // before ever reaching the line below. Placed after `start` so identity has resolved
                // and `isDeveloper` is answerable.
                await store.askForDeveloperNotificationsIfNeeded()
            }
            .confirmationDialog(L10n.t("feedback.portal.deleteConfirmTitle"),
                                isPresented: Binding(get: { pendingDeletion != nil },
                                                     set: { if !$0 { pendingDeletion = nil } }),
                                titleVisibility: .visible,
                                presenting: pendingDeletion) { request in

                Button(L10n.t("feedback.common.delete"), role: .destructive) {

                    Task {

                        await store.moderation.delete(request)

                        if selection == request.id { selection = nil }

                        pendingDeletion = nil
                    }
                }

                Button(L10n.t("feedback.common.cancel"), role: .cancel) { pendingDeletion = nil }

            } message: { request in

                Text(L10n.t("feedback.portal.deleteConfirmMessage \(request.title)"))
            }
    }

    @ViewBuilder private var container: some View {

#if os(macOS)
        // Never a `NavigationSplitView` of its own, regardless of `embedsNavigationStack` - the only
        // known caller embeds this in another split view's detail column (via `FeedbackBoardView`'s
        // toolbar menu), and nesting one split view inside another's detail is not supported. A plain
        // `HStack` gets the same side-by-side look without being one, so it nests cleanly. See the
        // matching fix and its longer explanation on `FeedbackBoardView.container`.
        HStack(spacing: 0) {

            queueList
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)

            Divider()

            Group {

                if let selected = selectedRequest {

                    // Its own `NavigationStack` so its toolbar and refresh action stay scoped to this
                    // pane rather than merging into the queue list's.
                    NavigationStack { PortalRequestView(store: store, request: selected) }
                        .id(selected.id)
                }
                else {

                    FeedbackEmptyState(symbol: "hammer",
                                       title: L10n.t("feedback.common.nothingSelected"),
                                       message: L10n.t("feedback.common.pickFromList"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
#else
        
        if embedsNavigationStack {

            NavigationStack { queueList }
        }
        else {

            queueList
        }
#endif
    }

    @ViewBuilder private var queueList: some View {

#if os(macOS)
        // Plain content, not `.searchable`/`.feedbackRefreshable` - nested this deep inside a host's
        // own split view detail column, macOS has been seen merging and re-rendering those per-column
        // toolbar contributions, producing duplicate search fields and refresh buttons. See the
        // matching fix on `FeedbackBoardView.board`.
        VStack(spacing: 0) {
            
            VStack(spacing: 8) {
                
                HStack(spacing: 10) {

                    HStack(spacing: 4) {

                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField(L10n.t("feedback.common.search"), text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    Spacer(minLength: 8)

                    versionMenu

                    Button(action: { Task { await store.load() } }) {

                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.t("feedback.common.refresh"))
                }
                
                listFilter
            }
            .padding([.horizontal, .top], 12)

            portalList
        }
        .ownedNavigationTitle(L10n.t("feedback.portal.shortTitle"), ownsStack: embedsNavigationStack)
#else
        portalList
            .navigationTitle(L10n.t("feedback.portal.shortTitle"))
            .searchable(text: $searchText, prompt: Text(L10n.t("feedback.common.search")))
            .feedbackRefreshable { await store.load() }
            .toolbar {

                if !availableVersions.isEmpty {

                    ToolbarItem(placement: toolbarTrailingPlacement) { versionMenu }
                }
            }
#endif
    }

    @ViewBuilder private var portalList: some View {

        // No `selection:` on the Mac - rows are buttons that set `selection` themselves (§ row(for:)).
#if os(macOS)
        List { portalRows }
#else
        List(selection: $selection) { portalRows }
#endif
    }
    
    @ViewBuilder private var listFilter: some View {
        
        // No visible "Queue" label - the row has zero insets so the control can span it, and a
        // leading label ate into that width and pushed the segments off-centre. Open/Reported/
        // Images/All read as a queue switch on sight, exactly as the board's filter does.
        Picker("", selection: $queue) {

            ForEach(PortalQueue.allCases, id: \.self) {

                Label($0.localised, systemImage: $0.symbolName).tag($0)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityLabel(L10n.t("feedback.portal.queueAccessibility"))
        .frame(maxWidth: .infinity, minHeight: 50)
    }

    @ViewBuilder private var portalRows: some View {

#if os(iOS)
        Section {
            
            listFilter
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .compactSectionSpacing()
#endif

        if let error = store.moderation.error {

            Section { FeedbackErrorBanner(error: error, retry: nil) }
        }

        if queued.isEmpty {

            Section {

                FeedbackEmptyState(symbol: queue.symbolName,
                                   title: L10n.t("feedback.portal.emptyTitle"),
                                   message: L10n.t("feedback.portal.emptyMessage"))
            }
        }
        else {

            Section {

                ForEach(queued) { request in row(for: request) }

            } header: { Text(L10n.t("feedback.portal.requestCount \(queued.count)")) }
        }
    }

    /// Lives in the header rather than as a list row - it is a filter over the list, and as a row it
    /// pushed the requests themselves below the fold before a single one had been read.
    @ViewBuilder private var versionMenu: some View {

        if !availableVersions.isEmpty {

            Picker(L10n.t("feedback.metadata.appVersion"), selection: $versionFilter) {

                Text(L10n.t("feedback.portal.allVersions")).tag(String?.none)

                ForEach(availableVersions, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden()
            .accessibilityLabel(L10n.t("feedback.portal.versionFilterAccessibility"))
            .help(L10n.t("feedback.portal.versionFilterAccessibility"))
#if os(macOS)
            .fixedSize()
#endif
        }
    }


    @ViewBuilder private func row(for request: FeedbackRequest) -> some View {

        let content = VStack(alignment: .leading, spacing: 4) {

            HStack {

                Text(request.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                Spacer(minLength: 8)

                TypeBadge(type: request.type)
            }

            HStack(spacing: 6) {

                StatusBadge(status: request.status)

                if store.reports.reportCount(for: request.id) > 0 {

                    Label(store.reports.reportCount(for: request.id).formatted(.number), systemImage: "flag.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                if request.imageState == .pending {

                    Label(L10n.t("feedback.common.image"), systemImage: "photo")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if request.moderation == .hidden {

                    Label(L10n.t("feedback.badge.hidden"), systemImage: "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(L10n.t("feedback.portal.voteCountVersion \(store.votes.tally(for: request.id)) \(request.environment.versionLabel)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

#if os(macOS)
        // A button, not a selectable row - `List(selection:)` draws its own highlight and focus ring,
        // which is the mismatched shape that showed up behind a selected row.
        //
        // Styled as the same card the board uses, deliberately: triage and the public board show the
        // same requests, and a row that looks different in the portal reads as a different kind of
        // thing. See `FeedbackBoardView.row(for:)`, which this mirrors.
        Button(action: { selection = request.id }) {

            content
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selection == request.id ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                                                    : AnyShapeStyle(.quaternary),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay {

                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: selection == request.id ? 1.5 : 0)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(selection == request.id ? [.isSelected] : [])
        .rowActions { rowMenu(for: request) }
#else
        NavigationLink { PortalRequestView(store: store, request: request) }
            label: { content }
            .rowActions { rowMenu(for: request) }
#endif
    }

    @ViewBuilder private func rowMenu(for request: FeedbackRequest) -> some View {

        if request.moderation == .hidden {

            Button(action: { Task { await store.moderation.unhide(request) } },
                   label: { Label(L10n.t("feedback.common.unhide"), systemImage: "eye") })
        }
        else {

            Button(role: .destructive, action: { Task { await store.moderation.hide(request) } },
                   label: { Label(L10n.t("feedback.common.hide"), systemImage: "eye.slash") })
        }

        Button(action: { Task { await store.moderation.approve(request) } },
               label: { Label(L10n.t("feedback.common.clearReports"), systemImage: "checkmark.shield") })

        Divider()

        // Confirmed rather than immediate: this cascades, and there is no undo. Hiding is the
        // reversible option and sits above it for that reason.
        Button(role: .destructive, action: { pendingDeletion = request },
               label: { Label(L10n.t("feedback.common.delete"), systemImage: "trash") })
    }

    private var selectedRequest: FeedbackRequest? {

        guard let selection else { return nil }

        return store.requests.requests.first { $0.id == selection }
    }

    // MARK: - Queues

    /// The portal sees hidden and over-threshold requests too - the client-side visibility rule is for
    /// users, not for the person who has to moderate.
    private var queued: [FeedbackRequest] {

        store.requests.requests
            .filter { request in

                guard versionFilter == nil || request.environment.appVersion == versionFilter else { return false }

                // Client-side over the already-loaded board - no extra query, and it can match the
                // author ID, which is what you have when a deletion request arrives by email.
                let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

                if !needle.isEmpty {

                    let haystack = [request.title, request.body, request.creatorID].joined(separator: " ").lowercased()

                    guard haystack.contains(needle) else { return false }
                }

                switch queue {

                // Named for exactly what it filters on, so the tab and the behaviour cannot drift apart.
                case .open: return request.status == .open && request.moderation != .hidden
                case .reported: return store.reports.reportCount(for: request.id) > 0
                case .images: return request.imageState == .pending
                case .all: return true
                }
            }
            .sorted { store.votes.tally(for: $0.id) > store.votes.tally(for: $1.id) }
    }

    private var availableVersions: [String] {

        Array(Set(store.requests.requests.map(\.environment.appVersion)))
            .filter { !$0.isEmpty }
            .sorted(by: >)
    }
}
