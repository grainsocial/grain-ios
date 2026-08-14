import SwiftUI

/// Covers the create sheet while a gallery is going out.
///
/// The old flow put an indeterminate spinner in the toolbar and any error in a
/// caption at the bottom of a long scrolling form — which is a good part of why
/// a failure could go unnoticed until a duplicate showed up in the feed. This
/// takes over the screen instead: it says which photo is uploading, it can't be
/// tapped through, and a failure arrives with the two things worth knowing —
/// that nothing was lost, and what to do next.
struct GalleryPublishOverlay: View {
    let stage: GalleryUploadCenter.Stage
    var onRetry: () -> Void
    var onPostLater: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if case let .failed(message) = stage {
                    failureContent(message: message)
                } else {
                    progressContent
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 24, y: 8)
        }
        .transition(.opacity)
    }

    private var progressContent: some View {
        VStack(spacing: 14) {
            if let fraction = stage.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
            }
            Text(stage.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
                .animation(.smooth, value: stage.label)
        }
    }

    private func failureContent(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Button(action: onRetry) {
                    Text("Try again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onPostLater) {
                    Text("Post later")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)

            Text("Your photos stay on this device until the gallery posts.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// A slim bar above the tab bar for a gallery that's finishing in the background.
///
/// This is what "post later" leads to. Without it an auto-resumed publish would
/// be entirely invisible — including a second failure.
struct PendingGalleryBar: View {
    let stage: GalleryUploadCenter.Stage
    let pendingCount: Int
    var onRetry: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        if let content {
            HStack(spacing: 12) {
                if stage.isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }

                Text(content)
                    .font(.footnote)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if !stage.isBusy {
                    Button("Retry", action: onRetry)
                        .font(.footnote.weight(.semibold))
                    Button("Discard", role: .destructive, action: onDiscard)
                        .font(.footnote)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var content: String? {
        if stage.isBusy {
            return "Finishing your gallery — \(stage.label.lowercased())"
        }
        if case .failed = stage, pendingCount > 0 {
            return "A gallery didn't finish posting."
        }
        if pendingCount > 0 {
            return "A gallery is waiting to finish posting."
        }
        return nil
    }
}

#Preview("Uploading") {
    GalleryPublishOverlay(
        stage: .uploading(completed: 3, total: 8),
        onRetry: {},
        onPostLater: {}
    )
}

#Preview("Failed") {
    GalleryPublishOverlay(
        stage: .failed(message: "The connection dropped. Nothing was lost — trying again picks up where it stopped."),
        onRetry: {},
        onPostLater: {}
    )
}
