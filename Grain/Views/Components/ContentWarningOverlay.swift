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

/// Media blur overlay — blurs the media with a reveal button on top.
struct MediaWarningOverlay: View {
    let name: String
    let onReveal: () -> Void

    var body: some View {
        Button {
            onReveal()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text(name)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: .capsule)
        }
        .buttonStyle(.plain)
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
