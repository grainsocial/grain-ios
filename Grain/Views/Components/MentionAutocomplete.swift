import SwiftUI

struct MentionSuggestion: Identifiable, Equatable {
    let handle: String
    let displayName: String?
    let avatar: String?
    var id: String { handle }
}

/// Detects @mention queries in text and provides autocomplete suggestions.
@Observable
@MainActor
final class MentionAutocompleteState {
    var suggestions: [MentionSuggestion] = []
    var isActive: Bool { activeQuery != nil }
    private(set) var activeQuery: String?
    private var searchTask: Task<Void, Never>?

    /// Call on every text change to detect @mention patterns.
    func update(text: String) {
        guard let query = extractMentionQuery(from: text) else {
            clear()
            return
        }
        activeQuery = query
        searchTask?.cancel()
        let q = query
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await search(query: q)
        }
    }

    func clear() {
        activeQuery = nil
        suggestions = []
        searchTask?.cancel()
    }

    /// Replace the @query in the text with the selected handle.
    func complete(handle: String, in text: inout String) {
        guard let query = activeQuery else { return }
        // Find the last @query and replace it
        let suffix = "@\(query)"
        if let range = text.range(of: suffix, options: .backwards) {
            text.replaceSubrange(range, with: "@\(handle) ")
        }
        clear()
    }

    private func extractMentionQuery(from text: String) -> String? {
        // Find the last @ that's either at the start or preceded by whitespace
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        let beforeAt = text[text.startIndex..<atIndex]
        if !beforeAt.isEmpty && !beforeAt.last!.isWhitespace { return nil }
        let after = String(text[text.index(after: atIndex)...])
        // Must not contain spaces (still typing the handle)
        guard !after.contains(" ") else { return nil }
        // Need at least 1 character after @
        guard !after.isEmpty else { return nil }
        return after
    }

    private func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 1 else {
            suggestions = []
            return
        }

        var components = URLComponents(url: AuthManager.serverURL.appendingPathComponent("xrpc/social.grain.unspecced.searchActorsTypeahead"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = components.url else { return }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actors = json["actors"] as? [[String: Any]] else {
            return
        }

        guard !Task.isCancelled else { return }
        suggestions = actors.compactMap { dict in
            guard let handle = dict["handle"] as? String else { return nil }
            return MentionSuggestion(
                handle: handle,
                displayName: dict["displayName"] as? String,
                avatar: dict["avatar"] as? String
            )
        }
    }
}

/// Compact horizontal suggestion strip that appears above the keyboard.
struct MentionSuggestionOverlay: View {
    let state: MentionAutocompleteState
    let onSelect: (MentionSuggestion) -> Void

    var body: some View {
        if state.isActive && !state.suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(state.suggestions) { suggestion in
                                Button {
                                    onSelect(suggestion)
                                } label: {
                                    HStack(spacing: 6) {
                                        AvatarView(url: suggestion.avatar, size: 24)
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(suggestion.displayName ?? suggestion.handle)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text("@\(suggestion.handle)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .glassEffect(.regular.interactive())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
        }
    }
}
