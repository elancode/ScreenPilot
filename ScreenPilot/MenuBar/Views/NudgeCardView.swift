import SwiftUI
import AppKit

struct NudgeCardView: View {
    let nudge: Nudge
    let followUps: [FollowUp]
    let isQuerying: Bool
    let canQuery: Bool
    let queryError: String?
    let screenshot: CGImage?
    let onQuery: (String) -> Void

    @State private var questionText = ""
    @State private var isExpanded = false
    @State private var isTruncated = false
    @State private var showScreenshot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: timestamp + badge + close button
            HStack {
                Text(nudge.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                typeBadge
                Spacer()
            }

            // Title
            Text(markdownString(nudge.title))
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
                .textSelection(.enabled)

            // Body
            Text(markdownString(nudge.body))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 6)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .background(
                    GeometryReader { visibleGeometry in
                        Text(markdownString(nudge.body))
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)
                            .background(
                                GeometryReader { fullGeometry in
                                    Color.clear.preference(
                                        key: TruncationPreferenceKey.self,
                                        value: fullGeometry.size.height > visibleGeometry.size.height + 1
                                    )
                                }
                            )
                            .hidden()
                    }
                    .hidden()
                )
                .onPreferenceChange(TruncationPreferenceKey.self) { value in
                    isTruncated = value
                }

            if isTruncated && !isExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                } label: {
                    Text("See more")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            // Screenshot toggle
            if let screenshot {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showScreenshot.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showScreenshot ? "eye.slash" : "eye")
                            .font(.system(size: 11))
                        Text(showScreenshot ? "Hide screenshot" : "Show screenshot")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                if showScreenshot {
                    Image(decorative: screenshot, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                }
            }

            // Follow-up conversation
            if !followUps.isEmpty {
                followUpSection
            }

            // Query input
            if canQuery {
                queryInput
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1.5)
        )
    }

    // MARK: - Follow-up Section

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            ForEach(followUps) { followUp in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(followUp.question)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                        Text(markdownString(followUp.answer))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: - Query Input

    private var queryInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            if followUps.isEmpty {
                Divider()
            }

            if let error = queryError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 6) {
                TextField("Ask about this...", text: $questionText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit(submitQuery)
                    .disabled(isQuerying)

                if isQuerying {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: submitQuery) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.body)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(questionText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func submitQuery() {
        let trimmed = questionText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isQuerying else { return }
        onQuery(trimmed)
        questionText = ""
    }

    // MARK: - Subviews

    private var typeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: nudge.type == .technicalCopilot ? "paperplane.fill" : "checkmark.circle")
                .font(.system(size: 10))
            Text(nudge.type == .technicalCopilot ? "TECHNICAL COPILOT" : "TASK ASSISTANT")
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(nudge.type == .technicalCopilot ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
        .foregroundStyle(nudge.type == .technicalCopilot ? .blue : .green)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

}

private struct TruncationPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

func markdownString(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}
