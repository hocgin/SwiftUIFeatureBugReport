//
//  MyDataView.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

/// Reached from the board's overflow menu (§9.4). Not on the main screen, not buried three levels
/// down - somewhere a user looking for it will actually find it.
public struct MyDataView: View {

    @State private var store: FeedbackStore
    @State private var showingDeleteConfirmation = false

    private let embedsNavigationStack: Bool

    public init(configuration: FeedbackConfiguration, embedsNavigationStack: Bool = true) {

        self.init(store: FeedbackStore(configuration: configuration), embedsNavigationStack: embedsNavigationStack)
    }

    public init(store: FeedbackStore, embedsNavigationStack: Bool = true) {

        self.store = store
        self.embedsNavigationStack = embedsNavigationStack
    }

    public var body: some View {

        if embedsNavigationStack {

            NavigationStack { myData }
        }
        else {

            myData
        }
    }

    @ViewBuilder private var myData: some View {

        Form {

            if !store.canWrite {

                Section { ReadOnlyNotice() }
            }
            else {

                Section {

                    if store.accountData.isLoading {

                        HStack { ProgressView().controlSize(.small); Text(L10n.t("feedback.myData.counting")) }
                    }
                    else {

                        LabeledContent(L10n.t("feedback.myData.requests"), value: store.accountData.counts.requests.formatted(.number))
                        LabeledContent(L10n.t("feedback.common.votes"), value: store.accountData.counts.votes.formatted(.number))
                            .foregroundStyle(.secondary)
                        LabeledContent(L10n.t("feedback.common.replies"), value: store.accountData.counts.comments.formatted(.number))
                        LabeledContent(L10n.t("feedback.common.reports"), value: store.accountData.counts.reports.formatted(.number))
                    }

                } header: { Text(L10n.t("feedback.myData.activityHeader")) }
                  footer: { Text(L10n.t("feedback.myData.activityFooter")) }

                Section {

                    Button(role: .destructive, action: { showingDeleteConfirmation = true },
                           label: { Label(L10n.t("feedback.myData.deleteMine"), systemImage: "trash") })
                        .disabled(store.accountData.isDeleting || store.accountData.counts.isEmpty)

                    if store.accountData.isDeleting {

                        HStack { ProgressView().controlSize(.small); Text(L10n.t("feedback.myData.deleting")) }
                    }

                } footer: {

                    Text(L10n.t("feedback.myData.deleteVotesFooter"))
                }

                if !store.reports.blockedAuthors.isEmpty { blockedSection }
            }

            if let error = store.accountData.error {

                Section { FeedbackErrorBanner(error: error, retry: nil) }
            }
        }
        .formStyle(.grouped)
        .ownedNavigationTitle(L10n.t("feedback.myData.title"), ownsStack: embedsNavigationStack)
        .inlineNavigationTitle()
        .task {

            await store.start()
            await store.accountData.loadCounts()
        }

        .confirmationDialog(L10n.t("feedback.myData.deleteConfirmTitle"),
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {

            Button(L10n.t("feedback.myData.deleteConfirmAction"), role: .destructive) {

                Task { await store.deleteMyData() }
            }

            Button(L10n.t("feedback.common.cancel"), role: .cancel) { }

        } message: {

            // Stated plainly rather than buried, in both directions: what goes, and what stays.
            // Deleting a request really does take other people's votes and replies on it with it, and
            // someone about to do that deserves to know before rather than after.
            Text(L10n.t("feedback.myData.deleteConfirmMessage"))
        }
    }

    @ViewBuilder private var blockedSection: some View {

        Section {

            ForEach(Array(store.reports.blockedAuthors).sorted(), id: \.self) { author in

                HStack {

                    Text(author)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button(L10n.t("feedback.myData.unblock")) { store.reports.unblock(author: author) }
                        .font(.caption)
                }
            }

        } header: { Text(L10n.t("feedback.myData.blockedHeader")) }
          footer: { Text(L10n.t("feedback.myData.blockedFooter")) }
    }
}
