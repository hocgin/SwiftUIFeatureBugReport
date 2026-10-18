//
//  RequestRow.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

struct RequestRow: View {

    let request: FeedbackRequest
    let voteCount: Int
    let hasVoted: Bool
    let isVoting: Bool
    let canVote: Bool
    let showsType: Bool
    let onVote: () -> Void

    var body: some View {

        // 卡片式布局：左侧为「类型 · 时间 / 标题 / 状态与标签」，投票胶囊固定在右上角。
        HStack(alignment: .top, spacing: 12) {

            VStack(alignment: .leading, spacing: 6) {

                HStack(spacing: 8) {

                    if showsType { TypeBadge(type: request.type) }

                    Text(request.lastActivityAt, format: .relative(presentation: .named))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(request.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !request.body.isEmpty {

                    Text(request.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if hasChips {

                    // 标签过多时自动换行，而不是被截断
                    ChipFlowLayout(spacing: 8) {

                        if request.status == .complete { ResolvedVersionBadge(version: request.resolvedInVersion) }
                        else if request.status != .open { StatusBadge(status: request.status) }

                        if request.moderation == .hidden { HiddenBadge() }

                        ForEach(request.labels.prefix(3), id: \.self) { LabelChip(name: $0) }

                        if request.imageState == .pending {

                            Label(L10n.t("feedback.badge.imageInReview"), systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VoteButton(count: voteCount,
                       hasVoted: hasVoted,
                       isBusy: isVoting,
                       isEnabled: canVote,
                       confirms: true,
                       action: onVote)
        }
        .padding(.vertical, 2)
        // The vote button stays its own element; the rest of the row reads as one label.
        .accessibilityElement(children: .contain)
    }

    private var hasChips: Bool {

        !request.labels.isEmpty
            || request.status != .open
            || request.moderation == .hidden
            || request.imageState == .pending
    }
}


/// 按行流式排布子视图，放不下就换行。
private struct ChipFlowLayout: Layout {

    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {

        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {

        let result = arrange(bounds.width, subviews)

        for (index, origin) in result.origins.enumerated() {

            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                                  proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {

        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0

        for subview in subviews {

            let size = subview.sizeThatFits(.unspecified)

            if x > 0, x + size.width > width {

                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}


/// 看板顶部的引导说明：告诉第一次来的人这里能做什么，可关闭。
struct BoardGuideCard: View {

    let onDismiss: () -> Void

    var body: some View {

        VStack(alignment: .leading, spacing: 10) {

            HStack(alignment: .firstTextBaseline) {

                Label(L10n.t("feedback.guide.title"), systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                Spacer(minLength: 8)

                Button(action: onDismiss) {

                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.t("feedback.guide.dismiss"))
            }

            GuideStep(symbol: "magnifyingglass",
                      text: L10n.t("feedback.guide.stepSearch"))

            GuideStep(symbol: "hand.thumbsup",
                      text: L10n.t("feedback.guide.stepVote"))

            GuideStep(symbol: "plus.bubble",
                      text: L10n.t("feedback.guide.stepCreate"))

            GuideStep(symbol: "bell",
                      text: L10n.t("feedback.guide.stepNotify"))
        }
        .padding(.vertical, 4)
    }
}


private struct GuideStep: View {

    let symbol: String
    let text: String

    var body: some View {

        // 图标与文字同用 footnote 字号，间距收紧到 6pt：SF Symbol 字形自带水平内边距，
        // 叠加定宽 frame 的剩余宽度后，实际视觉空隙会明显大于 HStack 的 spacing 数值。
        HStack(alignment: .firstTextBaseline, spacing: 6) {

            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}


/// Shown while identity is still resolving.
///
/// Rendering rows before `identityState` is settled means every one of them reads "not mine, not
/// voted" and then visibly flips a moment later, which looks like a bug even though it is not.
struct IdentityResolvingView: View {

    var body: some View {

        VStack(spacing: 12) {

            ProgressView()

            Text(L10n.t("feedback.notice.resolving"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 32)
    }
}


/// The read-only state. Not an error - browsing and reading work fine without an account; only
/// writing needs one, because CloudKit public-database writes require a signed-in iCloud account.
struct ReadOnlyNotice: View {

    var body: some View {

        HStack(alignment: .firstTextBaseline, spacing: 12) {

            Image(systemName: "icloud.slash")

            VStack(alignment: .leading, spacing: 2) {

                Text(L10n.t("feedback.notice.readOnly"))
                    .font(.subheadline.weight(.semibold))

                Text(L10n.t("feedback.notice.readOnlyDetail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}


struct FeedbackEmptyState: View {

    let symbol: String
    let title: String
    let message: String

    var body: some View {

        VStack(spacing: 12) {

            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}


struct FeedbackErrorBanner: View {

    let error: FeedbackError

    /// `nil` while a rate limit is still running - a user able to spam-tap retry into an active rate
    /// limit only extends it.
    let retry: (() -> Void)?

    var body: some View {

        VStack(alignment: .leading, spacing: 8) {

            Label {

                Text(error.localizedDescription)
                    .font(.footnote)

            } icon: { Image(systemName: "exclamationmark.triangle") }

            if let retry {

                Button(L10n.t("feedback.common.tryAgain"), action: retry)
                    .font(.footnote)
            }
        }
        .foregroundStyle(.secondary)
    }
}
