//
//  MetadataDisclosureView.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

/// Exactly what will be attached, in full (§9.3).
///
/// No summarising and no hidden keys - if a developer attaches something through `FeedbackPrefill`,
/// the person submitting gets to read it before they send it.
struct MetadataDisclosureView: View {
    
    @Binding var includeMetadata: Bool

    let environment: DeviceEnvironment
    let metadata: [String: String]

    var body: some View {

        List {

            Section {

                ForEach(environment.disclosureEntries, id: \.label) { entry in

                    LabeledContent(entry.label, value: entry.value)
                }

            } header: { Text(L10n.t("feedback.metadata.deviceHeader")) }
            footer: { Text(L10n.t("feedback.metadata.visibleToAll")) }

            if metadata.isEmpty {

                Section {

                    Text(L10n.t("feedback.metadata.noneAdditional"))
                        .foregroundStyle(.secondary)
                }
            }
            else {
                
                // Its own section, not sharing a row with the disclosure link above - this only ever
                // holds back the developer-added extras. Device information always goes regardless of this
                // toggle; it is the minimum needed to triage a report, and matches any public issue tracker.
                Section {

                    Toggle(L10n.t("feedback.metadata.includeAdditional"), isOn: $includeMetadata)

                } header: { Text(L10n.t("feedback.metadata.additionalHeader")) }
                  footer: { Text(L10n.t("feedback.metadata.additionalFooter")) }

                
                Section(content: {
                    
                    ForEach(metadata.keys.sorted(), id: \.self) { key in

                        LabeledContent(key, value: metadata[key] ?? "")
                    }
                    
                }, footer: { Text(L10n.t("feedback.metadata.onlyDeveloper")) })
                .opacity(includeMetadata ? 1 : 0.5)
            }
        }
        .navigationTitle(L10n.t("feedback.metadata.pageTitle"))
        .inlineNavigationTitle()
    }
}
