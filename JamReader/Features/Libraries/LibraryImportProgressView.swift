import SwiftUI

/// What a long task shows in `TaskBanner`: what it does, where, counts and progress.
struct TaskBannerContent: Equatable {
    enum Phase: Equatable {
        case running(fraction: Double?)
        /// Finished without problems; the banner closes itself after a few seconds.
        case succeeded
        /// Finished with skipped or failed items; stays until the person closes it.
        case needsAttention
    }

    var phase: Phase
    var title: String
    var detail: String?

    var isRunning: Bool {
        if case .running = phase {
            return true
        }
        return false
    }
}

/// Floating bar above the tab bar for imports and scans: the single place that
/// shows long-running work and its result. See docs/design-system/components/TaskBanner.
struct TaskBanner: View {
    private static let successDismissDelay: Duration = .seconds(4)

    let content: TaskBannerContent
    var actionTitle: String?
    var action: (() -> Void)?
    /// Cancels a running task, or dismisses a finished one. `nil` hides ×.
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            leadingIndicator
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(content.title)
                    .font(AppFont.subheadline(.semibold))
                    .foregroundStyle(Color.textPrimary)

                if let detail = content.detail {
                    Text(detail)
                        .font(AppFont.footnote().monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(AppFont.subheadline(.semibold))
                    .foregroundStyle(Color.appAccent)
                    .buttonStyle(.borderless)
            }

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(AppFont.caption(.bold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.tertiarySystemFill), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(content.isRunning ? Text("Cancel") : Text("Close"))
            }
        }
        .padding(.leading, Spacing.md)
        .padding(.trailing, onClose == nil ? Spacing.md : Spacing.xxs)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 60)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
        .appShadow(AppShadow.lg)
        .task(id: content) {
            guard content.phase == .succeeded, let onClose else {
                return
            }
            try? await Task.sleep(for: Self.successDismissDelay)
            guard !Task.isCancelled else {
                return
            }
            onClose()
        }
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        switch content.phase {
        case .running(let fraction):
            if let fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .tint(.appJam)
            } else {
                ProgressView()
            }
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.appSuccess)
                .accessibilityHidden(true)
        case .needsAttention:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(Color.appWarning)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Places a `TaskBanner` above the bottom bars without covering other controls.
    func taskBanner<Banner: View>(@ViewBuilder _ banner: () -> Banner) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            banner()
                .padding(.horizontal)
                .padding(.bottom, Spacing.xs)
        }
    }
}

extension ImportedComicsImportProgress {
    func taskBannerContent(destinationName: String?) -> TaskBannerContent {
        var detailParts: [String] = []
        if let destinationName {
            detailParts.append(String(localized: "To \(destinationName)"))
        }
        if let totalCount {
            detailParts.append(String(localized: "\(completedCount) of \(totalCount)"))
        } else if let detailLine {
            detailParts.append(detailLine)
        }

        return TaskBannerContent(
            phase: .running(fraction: fractionCompleted),
            title: title,
            detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · ")
        )
    }
}

extension ImportedComicsImportResult {
    /// Result bar: imported count, then skipped and failed counts when present.
    /// The import service reports reused files as imported, so "already in the
    /// library" cannot be counted separately.
    var taskBannerContent: TaskBannerContent {
        let failedCount = failedItemNames.count + (scanErrorMessage == nil ? 0 : 1)
        let skippedCount = unsupportedItemNames.count
        var parts = [
            importedComicCount == 1
                ? String(localized: "1 imported")
                : String(localized: "\(importedComicCount) imported")
        ]
        if skippedCount > 0 {
            parts.append(String(localized: "\(skippedCount) unsupported"))
        }
        if failedCount > 0 {
            parts.append(String(localized: "\(failedCount) failed"))
        }

        let isClean = skippedCount == 0 && failedCount == 0 && importedComicCount > 0
        return TaskBannerContent(
            phase: isClean ? .succeeded : .needsAttention,
            title: isClean
                ? String(localized: "Import Complete")
                : String(localized: "Import Partly Complete"),
            detail: "\(importedDestinationDisplayName) · \(parts.joined(separator: " · "))"
        )
    }
}

/// Hands an import result from the page that started the import to the
/// library page that opens next, so the result bar appears where the comics are.
@MainActor
final class LibraryTaskResultInbox {
    static let shared = LibraryTaskResultInbox()
    static let didReceiveResult = Notification.Name("LibraryTaskResultInbox.didReceiveResult")

    private var results: [UUID: TaskBannerContent] = [:]

    func post(_ content: TaskBannerContent, for libraryID: UUID) {
        results[libraryID] = content
        NotificationCenter.default.post(name: Self.didReceiveResult, object: libraryID)
    }

    func take(for libraryID: UUID) -> TaskBannerContent? {
        results.removeValue(forKey: libraryID)
    }
}
