//
//  PortalRequestView.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import SwiftUI

/// Triage for one request. Everything a developer can do lives here.
struct PortalRequestView: View {

    @State var store: FeedbackStore
    @State var request: FeedbackRequest

    @State private var metadata: [String: String] = [:]
    @State private var newLabel = ""
    @State private var reply = ""
    @State private var shippedMessage = ""
    @State private var resolvedVersion = ""
    @State private var isLoadingDetail = true

    @State private var showingInfo = false
    @State private var showingDelete = false
    @State private var showingBlockAuthor = false
    @State private var showingDeleteAuthorData = false
    @State private var error: FeedbackError?

    var body: some View {

        Form {

            if request.moderation != .visible || store.reports.reportCount(for: request.id) >= store.configuration.reportThreshold {

                Section {

                    ModerationBanner(moderation: request.moderation,
                                     reportCount: store.reports.reportCount(for: request.id),
                                     threshold: store.configuration.reportThreshold)
                }
            }

            Section {

                // The title was this section's header. A header is not selectable on either platform -
                // and it is shortened and capitalised on the way in - so it reads as a row instead,
                // which is what lets the developer lift the wording straight out of the triage screen.
                Text(request.title)
                    .font(.headline)
                    .textSelection(.enabled)

                Text(request.body)
                    .textSelection(.enabled)

                LabeledContent(L10n.t("feedback.common.author")) {

                    Text(request.creatorID)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                LabeledContent(L10n.t("feedback.common.votes"), value: store.votes.tally(for: request.id).formatted(.number))
                LabeledContent(L10n.t("feedback.common.reports"), value: store.reports.reportCount(for: request.id).formatted(.number))

                if let breakdown = reportBreakdown, !breakdown.isEmpty {

                    LabeledContent(L10n.t("feedback.portal.request.reportedAs"), value: breakdown)
                }
            }

            Section {

                #if os(macOS)
                // A sheet, not a push. This view sits in a pane of the host's own split view, and the
                // push was escaping the pane's stack to replace the entire host detail column - queue
                // list and all - leaving no way back to the portal.
                Button(action: { showingInfo = true }) {

                    // Full width, so the whole row stays the target the pushed link used to be.
                    Label(L10n.t("feedback.portal.request.info"), systemImage: "info.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                #else
                NavigationLink {

                    RequestInfoView(request: request, metadata: metadata)

                } label: { Label(L10n.t("feedback.portal.request.info"), systemImage: "info.circle") }
                #endif
            }

            statusSection
            labelSection
            imageSection
            moderationSection
            commentSection
            replySection
            notifySection

            if let error { Section { FeedbackErrorBanner(error: error, retry: nil) } }
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.t("feedback.portal.request.title"))
        .inlineNavigationTitle()
        .toolbar {

            ToolbarItem(placement: toolbarTrailingPlacement) {

                Menu {

                    Section {

                        Button(action: { Task { await store.moderation.approve(request); await reloadDetail() } },
                               label: { Label(L10n.t("feedback.common.clearReports"), systemImage: "checkmark.shield") })
                            .disabled(request.moderation == .approved)

                        if request.moderation == .hidden {

                            Button(action: { Task { await store.moderation.unhide(request); await reloadDetail() } },
                                   label: { Label(L10n.t("feedback.common.unhide"), systemImage: "eye") })
                        }
                        else {

                            Button(action: { Task { await store.moderation.hide(request); await reloadDetail() } },
                                   label: { Label(L10n.t("feedback.portal.hideFromEveryone"), systemImage: "eye.slash") })
                        }
                    }

                    Section(L10n.t("feedback.portal.dangerZone")) {

                        Button(role: .destructive, action: { showingDelete = true },
                               label: { Label(L10n.t("feedback.portal.deleteThisRequest"), systemImage: "trash") })

                        Button(role: .destructive, action: { showingBlockAuthor = true },
                               label: { Label(L10n.t("feedback.portal.hideEverythingByAuthor"), systemImage: "person.slash") })

                        Button(role: .destructive, action: { showingDeleteAuthorData = true },
                               label: { Label(L10n.t("feedback.portal.deleteAuthorData"), systemImage: "person.crop.circle.badge.xmark") })
                    }

                } label: { Label(L10n.t("feedback.common.options"), systemImage: "ellipsis.circle") }
            }
        }
        .modifier(PortalConfirmations(store: store,
                                      request: request,
                                      showingDelete: $showingDelete,
                                      showingBlockAuthor: $showingBlockAuthor,
                                      showingDeleteAuthorData: $showingDeleteAuthorData))
        .task { await reloadDetail() }

        #if os(macOS)
        .sheet(isPresented: $showingInfo) {

            NavigationStack {

                RequestInfoView(request: request, metadata: metadata)
                    .navigationTitle(L10n.t("feedback.portal.request.info"))
                    .toolbar {

                        ToolbarItem(placement: .confirmationAction) {

                            Button(L10n.t("feedback.common.done")) { showingInfo = false }
                        }
                    }
            }
            .frame(width: 460, height: 520)
        }
        #endif
    }

    // MARK: - Sections

    @ViewBuilder private var statusSection: some View {

        Section {

            Picker(L10n.t("feedback.common.status"), selection: Binding(get: { request.status },
                                                set: { newStatus in

                request.status = newStatus

                Task {

                    await store.moderation.setStatus(newStatus, on: request)

                    // The service prefills the version on completion; mirror it back into the field.
                    if newStatus == .complete, resolvedVersion.isEmpty {

                        resolvedVersion = DeviceInfo.getAppVersion()
                        request.resolvedInVersion = resolvedVersion
                    }
                }
            })) {

                ForEach(RequestStatus.allCases, id: \.self) { Text($0.localised).tag($0) }
            }

            if request.status == .complete || request.status == .updatePending {

                TextField(L10n.t("feedback.portal.request.fixedInVersion"), text: $resolvedVersion)
                    .onSubmit { commitVersion() }

                if resolvedVersion != request.resolvedInVersion {

                    Button(L10n.t("feedback.portal.request.saveVersion")) { commitVersion() }
                }
            }

        } header: { Text(L10n.t("feedback.common.status")) }
          footer: {

            Text(L10n.t("feedback.portal.request.versionFooter \(resolvedVersion.isEmpty ? "…" : resolvedVersion)"))
          }
    }

    @ViewBuilder private var labelSection: some View {

        Section {

            if !request.labels.isEmpty {

                ForEach(request.labels, id: \.self) { label in

                    HStack {

                        LabelChip(name: label)

                        Spacer()

                        Button(role: .destructive, action: { remove(label: label) },
                               label: { Image(systemName: "minus.circle") })
                            .buttonStyle(.borderless)
                            .accessibilityLabel(L10n.t("feedback.portal.request.removeLabel \(label)"))
                    }
                }
            }

            HStack {

                TextField(L10n.t("feedback.portal.request.addLabel"), text: $newLabel)

                Button(L10n.t("feedback.common.add")) { addLabel() }
                    .disabled(newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

        } header: { Text(L10n.t("feedback.common.labels")) }
    }

    @ViewBuilder private var imageSection: some View {

        if request.imageState != .none {

            Section {

                if !request.imageURLs.isEmpty {

                    ImageGallery(urls: request.imageURLs)
                }
                else if request.imageState != .rejected {

                    // The record says it has an image but no asset came back. Say so rather than
                    // rendering nothing, which is indistinguishable from a layout bug.
                    Label(isLoadingDetail ? L10n.t("feedback.portal.request.loadingImage") : L10n.t("feedback.portal.request.noImageData"),
                          systemImage: isLoadingDetail ? "clock" : "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }

                LabeledContent(L10n.t("feedback.common.state"), value: request.imageState.rawValue)

                if request.imageState == .pending {

                    // One row: the two are a single either/or decision, and stacking them made the
                    // section taller than the pane it sits in.
                    HStack(spacing: 10) {

                        Button(action: { moderateImage(approve: true) },
                               label: { Label(L10n.t("feedback.portal.request.approve"), systemImage: "checkmark.circle") })

                        Button(role: .destructive,
                               action: { moderateImage(approve: false) },
                               label: { Label(L10n.t("feedback.portal.request.rejectAndDelete"), systemImage: "trash") })

                        Spacer(minLength: 0)
                    }
                    .disabled(store.moderation.isWorking)
                }

            } header: { Text(L10n.t("feedback.common.image")) }
              footer: { Text(L10n.t("feedback.portal.request.imageFooter")) }
        }
    }

    /// Re-reads the record afterwards rather than guessing the new state locally, so what is on screen
    /// is always what the server actually stored.
    private func moderateImage(approve: Bool) {

        Task {

            if approve { await store.moderation.approveImage(on: request) }
            else { await store.moderation.rejectImage(on: request) }

            await reloadDetail()
        }
    }

    @ViewBuilder private var moderationSection: some View {

        Section {

            LabeledContent(L10n.t("feedback.portal.request.moderation"), value: request.moderation.rawValue)

            Button(action: { Task { await store.moderation.approve(request); request.moderation = .approved } },
                   label: { Label(L10n.t("feedback.common.clearReports"), systemImage: "checkmark.shield") })
                .disabled(request.moderation == .approved)

            if request.moderation == .hidden {

                Button(action: { Task { await store.moderation.unhide(request); request.moderation = .visible } },
                       label: { Label(L10n.t("feedback.common.unhide"), systemImage: "eye") })
            }
            else {

                Button(role: .destructive,
                       action: { Task { await store.moderation.hide(request); request.moderation = .hidden } },
                       label: { Label(L10n.t("feedback.portal.hideFromEveryone"), systemImage: "eye.slash") })
            }

        } header: { Text(L10n.t("feedback.portal.request.moderation")) }
          footer: { Text(L10n.t("feedback.portal.request.moderationFooter")) }
    }

    @ViewBuilder private var commentSection: some View {

        Section {

            if store.comments.comments.isEmpty {

                Text(L10n.t("feedback.portal.request.noReplies"))
                    .foregroundStyle(.secondary)
            }
            else {

                ForEach(store.comments.comments) { comment in

                    VStack(alignment: .leading, spacing: 4) {

                        HStack {

                            Text(comment.isDeveloper ? L10n.t("feedback.common.developer") : L10n.t("feedback.common.user"))
                                .font(.caption.weight(.semibold))

                            // A user comment whose author is neither the request's creator nor a
                            // developer should not exist. CloudKit cannot enforce that rule, so the
                            // portal shows it rather than pretending it cannot happen.
                            if !comment.isDeveloper && comment.creatorID != request.creatorID {

                                Label(L10n.t("feedback.portal.request.notAuthor"), systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }

                            Spacer()

                            Text(comment.createdAt, format: .relative(presentation: .named))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Text(comment.body)
                            .font(.footnote)

                        Text(comment.creatorID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

        } header: { Text(L10n.t("feedback.common.replies")) }
    }

    @ViewBuilder private var replySection: some View {

        Section {

            FeedbackTextEditor(placeholder: L10n.t("feedback.portal.request.replyPlaceholder"), text: $reply, minHeight: 70)

            Button(L10n.t("feedback.portal.request.postReply")) { postReply() }
                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        } header: { Text(L10n.t("feedback.portal.request.replyHeader")) }
    }

    @ViewBuilder private var notifySection: some View {

        Section {

            TextField(L10n.t("feedback.portal.request.announcePlaceholder"), text: $shippedMessage)

            Button(action: { notifyFollowers() },
                   label: { Label(L10n.t("feedback.portal.request.notifyFollowers"), systemImage: "bell.badge") })
                .disabled(shippedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || store.moderation.isWorking)

        } header: { Text(L10n.t("feedback.portal.request.announceHeader")) }
          footer: { Text(L10n.t("feedback.portal.request.announceFooter")) }
    }

    /// Report categories for this request, most common first, so the queue can be read at a glance.
    private var reportBreakdown: String? {

        let counts = store.reports.categories(for: request.id)

        guard !counts.isEmpty else { return nil }

        return counts
            .sorted { $0.value > $1.value }
            .map { "\($0.key.displayName) (\($0.value))" }
            .joined(separator: ", ")
    }

    // MARK: - Actions

    private func reloadDetail() async {

        isLoadingDetail = true

        request = await store.requests.loadDetail(request)
        resolvedVersion = request.resolvedInVersion
        metadata = await store.moderation.metadata(for: request)

        await store.comments.load(for: request.id)

        isLoadingDetail = false
    }

    private func commitVersion() {

        let version = resolvedVersion.trimmingCharacters(in: .whitespacesAndNewlines)

        guard version != request.resolvedInVersion else { return }

        request.resolvedInVersion = version

        Task { await store.moderation.setResolvedVersion(version, on: request) }
    }

    private func addLabel() {

        let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !label.isEmpty, !request.labels.contains(label) else { return }

        request.labels.append(label)
        newLabel = ""

        Task { await store.moderation.setLabels(request.labels, on: request) }
    }

    private func remove(label: String) {

        request.labels.removeAll { $0 == label }

        Task { await store.moderation.setLabels(request.labels, on: request) }
    }

    private func postReply() {

        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {

            do { try await store.comments.addDeveloperComment(to: request, body: text) }
            catch { self.error = CloudKitErrorHandler.classify(error) }

            reply = ""
        }
    }

    private func notifyFollowers() {

        let message = shippedMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {

            await store.moderation.notifyFollowers(of: request, message: message)

            shippedMessage = ""
        }
    }
}


/// The dialogs behind the danger-zone menu items, factored out so the toolbar builder stays readable.
private struct PortalConfirmations: ViewModifier {

    let store: FeedbackStore
    let request: FeedbackRequest

    @Binding var showingDelete: Bool
    @Binding var showingBlockAuthor: Bool
    @Binding var showingDeleteAuthorData: Bool

    func body(content: Content) -> some View {

        content

            .confirmationDialog(L10n.t("feedback.portal.deleteRequestConfirm"), isPresented: $showingDelete, titleVisibility: .visible) {

                Button(L10n.t("feedback.common.delete"), role: .destructive) { Task { await store.moderation.delete(request) } }
                Button(L10n.t("feedback.common.cancel"), role: .cancel) { }

            } message: { Text(L10n.t("feedback.portal.deleteRequestMessage")) }

            .confirmationDialog(L10n.t("feedback.portal.hideEverythingConfirm"),
                                isPresented: $showingBlockAuthor,
                                titleVisibility: .visible) {

                Button(L10n.t("feedback.portal.hideAll"), role: .destructive) { Task { await store.moderation.hideAll(by: request.creatorID) } }
                Button(L10n.t("feedback.common.cancel"), role: .cancel) { }

            } message: { Text(L10n.t("feedback.portal.hideEverythingMessage")) }

            .confirmationDialog(L10n.t("feedback.portal.deleteAuthorDataConfirm"),
                                isPresented: $showingDeleteAuthorData,
                                titleVisibility: .visible) {

                Button(L10n.t("feedback.myData.deleteConfirmAction"), role: .destructive) {

                    Task {

                        await store.accountData.delete(creatorID: request.creatorID)
                        await store.load()
                    }
                }

                Button(L10n.t("feedback.common.cancel"), role: .cancel) { }

            } message: { Text(L10n.t("feedback.portal.deleteAuthorDataMessage")) }
    }
}


/// Everything about where a request came from, moved off the triage screen so that screen stays
/// scannable. Nothing here is actionable, which is exactly why it does not belong inline.
struct RequestInfoView: View {

    let request: FeedbackRequest
    let metadata: [String: String]

    var body: some View {

        Form {

            Section {

                LabeledContent(L10n.t("feedback.common.author")) {

                    Text(request.creatorID)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                LabeledContent(L10n.t("feedback.detail.submitted"), value: request.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent(L10n.t("feedback.portal.request.lastActivity"), value: request.lastActivityAt.formatted(date: .abbreviated, time: .shortened))

            } header: { Text(L10n.t("feedback.portal.request.origin")) }

            Section {

                ForEach(request.environment.disclosureEntries, id: \.label) { entry in

                    LabeledContent(entry.label, value: entry.value)
                }

            } header: { Text(L10n.t("feedback.portal.request.environmentHeader")) }
              footer: { Text(L10n.t("feedback.portal.request.environmentFooter")) }

            Section {

                if metadata.isEmpty {

                    Text(L10n.t("feedback.portal.request.noneAttached"))
                        .foregroundStyle(.secondary)
                }
                else {

                    ForEach(metadata.keys.sorted(), id: \.self) { key in

                        LabeledContent(key, value: metadata[key] ?? "")
                    }
                }

            } header: { Text(L10n.t("feedback.portal.request.privateMetadata")) }
              footer: { Text(L10n.t("feedback.portal.request.privateMetadataFooter")) }
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.t("feedback.portal.request.info"))
        .inlineNavigationTitle()
    }
}
