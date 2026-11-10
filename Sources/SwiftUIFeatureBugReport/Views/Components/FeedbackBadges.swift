//
//  FeedbackBadges.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

/// 徽章统一样式：单行、按内容自适应宽度，不被父级压缩或换行。
/// 采用小圆角矩形 + 淡色底，与列表卡片的投票方块在视觉上保持同一套语言。
private extension View {

    func badgeStyle<S: ShapeStyle>(background: S, foreground: some ShapeStyle) -> some View {

        self
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(foreground)
    }
}


/// 徽章内文字在前、图标在后且紧贴：系统 `Label` 的默认间距在小徽章里显得过大。
private struct CompactBadgeLabelStyle: LabelStyle {

    func makeBody(configuration: Configuration) -> some View {

        HStack(spacing: 4) {

            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}


struct TypeBadge: View {

    let type: FeedbackType

    var body: some View {

        Text(type.localised)
            .badgeStyle(background: type == .feature ? Color.blue : Color.red, foreground: .white)
    }
}


struct StatusBadge: View {

    let status: RequestStatus

    var body: some View {

        Label(status.localised, systemImage: status.symbolName)
            .labelStyle(CompactBadgeLabelStyle())
            .badgeStyle(background: status.tint.opacity(0.15), foreground: status.tint)
    }
}


/// Marks a request that has been moderated off the board.
///
/// Only ever rendered for a developer - the visibility rule filters these out for everyone else, so
/// this is the marker that tells the person who hid it that it *is* hidden, and from whom.
struct HiddenBadge: View {

    var body: some View {

        Label(L10n.t("feedback.badge.hidden"), systemImage: "eye.slash")
            .labelStyle(CompactBadgeLabelStyle())
            .badgeStyle(background: Color.secondary.opacity(0.15), foreground: .secondary)
            .accessibilityLabel(L10n.t("feedback.badge.hiddenAccessibility"))
            .help(L10n.t("feedback.badge.hiddenHelp"))
    }
}


struct LabelChip: View {

    let name: String

    var body: some View {

        Text(name)
            // 淡色底 + 同色文字，与状态徽章保持一致，避免标签比类型更抢眼
            .badgeStyle(background: Color(labelName: name).opacity(0.15), foreground: Color(labelName: name))
    }
}


/// The vote control.
///
/// Its accessibility label announces the count and whether this user has voted - VoiceOver reading
/// "button" over a bare arrow tells you nothing about either.
struct VoteButton: View {

    let count: Int
    let hasVoted: Bool
    let isBusy: Bool
    let isEnabled: Bool
    /// 为 true 时点击先弹出二次确认，确认后才执行 `action`（列表卡片上容易误触）。
    var confirms: Bool = false
    /// 外观：`.capsule` 为行内胶囊（详情页等），`.tile` 为列表卡片左侧的竖向方块。
    var style: Style = .capsule
    let action: () -> Void

    enum Style { case capsule, tile }

    @State private var isConfirming = false
    @State private var showsReadOnlyNotice = false

    private var tint: Color { hasVoted ? .green : .accentColor }

    var body: some View {

        // 按钮本身始终可点，不使用 `.disabled`：被禁用的按钮不再接收触摸，点按会穿透到父视图，
        // 在列表卡片上就会触发整行的「进入详情」手势。不可投票时改为提示原因。
        Button(action: handleTap) {

            switch style {

            case .capsule: capsuleLabel
            case .tile: tileLabel
            }
        }
        // 按下时轻微缩小，给出触感反馈；非默认样式在 List 行内仍可独立点击
        .buttonStyle(PressScaleButtonStyle())
        // 投票状态、票数变化时的弹性动画
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: hasVoted)
        .animation(.snappy, value: count)
        .animation(.easeInOut(duration: 0.2), value: isBusy)
        .sensoryFeedback(.selection, trigger: hasVoted)
        .confirmationDialog(hasVoted ? L10n.t("feedback.badge.withdrawVoteConfirm") : L10n.t("feedback.badge.voteConfirm"),
                            isPresented: $isConfirming,
                            titleVisibility: .visible) {

            if hasVoted { Button(L10n.t("feedback.common.withdrawVote"), role: .destructive, action: action) }
            else { Button(L10n.t("feedback.common.vote"), action: action) }

            Button(L10n.t("feedback.common.cancel"), role: .cancel) {}
        }
        .alert(L10n.t("feedback.notice.readOnly"), isPresented: $showsReadOnlyNotice) {

            Button(L10n.t("feedback.common.ok"), role: .cancel) {}

        } message: { Text(L10n.t("feedback.notice.readOnlyDetail")) }
        // 不可投票时视觉上置灰（但仍拦截点按，见上）。
        // Tappable while voted: the button toggles, so a mis-tap or a change of mind is recoverable.
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(hasVoted
                            ? L10n.t("feedback.common.votedCount \(count)")
                            : L10n.t("feedback.common.voteActionCount \(count)"))
        .accessibilityHint(hasVoted ? L10n.t("feedback.badge.withdrawsHint") : L10n.t("feedback.badge.addsVoteHint"))
        .accessibilityAddTraits(hasVoted ? [.isSelected] : [])
    }

    private func handleTap() {

        guard !isBusy else { return }

        guard isEnabled else { showsReadOnlyNotice = true; return }

        if confirms { isConfirming = true } else { action() }
    }

    /// 竖向方块：上箭头 + 紧凑计数（1.2K），描边圆角矩形；已投票时整块填充。
    private var tileLabel: some View {

        VStack(spacing: 2) {

            // 箭头始终占位，加载指示叠加在上方，避免切换时计数上下跳动
            Image(systemName: "chevron.up")
                .font(.caption.weight(.bold))
                .foregroundStyle(hasVoted ? Color.white : tint)
                .opacity(isBusy ? 0 : 1)
                .symbolEffect(.bounce.up, value: hasVoted)
                .overlay {

                    if isBusy {

                        ProgressView()
                            .controlSize(.mini)
                            .tint(hasVoted ? .white : tint)
                    }
                }

            Text(count.formatted(.number.notation(.compactName)))
                .contentTransition(.numericText(value: Double(count)))
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(hasVoted ? Color.white : Color.primary)
        }
        .frame(width: 44, height: 48)
        .background(hasVoted ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.06)),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint, lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var capsuleLabel: some View {

        HStack(spacing: 4) {

            if isBusy {

                ProgressView()
                    .controlSize(.small)
            }
            else {

                Image(systemName: hasVoted ? "hand.thumbsup.fill" : "hand.thumbsup")
            }

            Text(count.formatted(.number))
                .contentTransition(.numericText(value: Double(count)))
                .monospacedDigit()
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(tint)
        // 胶囊底色，让投票入口在行内更醒目、点击区域更大
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
        .contentShape(Capsule())
    }
}


/// 按下缩小的按钮样式。
private struct PressScaleButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {

        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}


/// "Fixed in 2.1" - the single most useful thing to tell someone looking at a completed request,
/// and the line that stops "then why is it still broken for me?" arriving as a support message.
///
/// Falls back to a plain "Fixed" when the developer has not recorded a version.
struct ResolvedVersionBadge: View {

    let version: String

    var body: some View {

        Group {

            if version.isEmpty { Label(L10n.t("feedback.badge.fixed"), systemImage: "checkmark.circle.fill") }
            else { Label(L10n.t("feedback.badge.fixedIn \(version)"), systemImage: "checkmark.circle.fill") }
        }
        .labelStyle(CompactBadgeLabelStyle())
        .badgeStyle(background: Color.green.opacity(0.15), foreground: Color.green)
    }
}


/// States the moderation situation at the top of a request in the portal.
///
/// Without it, hidden and auto-hidden requests look exactly like visible ones once you are inside
/// them - you can reply, set a status and announce a fix on something no user can see. The auto-hidden
/// case matters most: `moderation` is still `visible`, so nothing on the record says it is hidden;
/// only the report count crossing the threshold does, and that is computed client-side.
struct ModerationBanner: View {

    let moderation: ModerationState
    let reportCount: Int
    let threshold: Int

    private var state: (title: String, detail: String, symbol: String, tint: Color)? {

        switch moderation {

        case .hidden:
            return (L10n.t("feedback.badge.hiddenFromEveryone"),
                    L10n.t("feedback.badge.hiddenFromEveryoneDetail"),
                    "eye.slash.fill", .red)

        case .visible where reportCount >= threshold:
            return (L10n.t("feedback.badge.autoHidden"),
                    L10n.t("feedback.badge.autoHiddenDetail \(reportCount) \(threshold)"),
                    "exclamationmark.triangle.fill", .orange)

        case .approved:
            return (L10n.t("feedback.badge.reportsCleared"),
                    L10n.t("feedback.badge.reportsClearedDetail"),
                    "checkmark.shield.fill", .green)

        default:
            return nil
        }
    }

    var body: some View {

        if let state {

            HStack(alignment: .firstTextBaseline, spacing: 12) {

                Image(systemName: state.symbol)
                    .foregroundStyle(state.tint)

                VStack(alignment: .leading, spacing: 2) {

                    Text(state.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(state.tint)

                    Text(state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}
