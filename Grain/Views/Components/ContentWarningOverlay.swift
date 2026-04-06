import SwiftUI

/// Full content warning overlay — hides all content behind a reveal button.
struct ContentWarningOverlay: View {
    let name: String
    let action: LabelAction
    let onReveal: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: action == .hide ? "eye.slash.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("This content has been flagged.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Show anyway") {
                onReveal()
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

/// Media warning overlay — centered bar with label name and Show button (Bluesky-style).
struct MediaWarningOverlay: View {
    let name: String
    let onReveal: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Show") {
                    onReveal()
                }
                .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            Spacer()
        }
    }
}

/// Small inline badge for low-severity labels.
struct LabelBadge: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(name)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: .capsule)
    }
}
