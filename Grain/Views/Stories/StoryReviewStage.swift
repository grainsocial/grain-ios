import SwiftUI

/// The second half of the story composer: the chosen photo with chips over it
/// for location, content labels, and Bluesky cross-posting, and a post button.
struct StoryReviewStage: View {
    let image: UIImage
    let locationName: String?
    let labelSummary: String?
    @Binding var postToBluesky: Bool
    let errorMessage: String?
    let isUploading: Bool
    let onRetake: () -> Void
    let onEditLocation: () -> Void
    let onClearLocation: () -> Void
    let onEditLabels: () -> Void
    let onClearLabels: () -> Void
    let onPost: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(white: 0.08)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()

                VStack {
                    HStack {
                        StoryChromeButton("xmark", label: "Retake", action: onRetake)
                        Spacer()
                    }
                    .padding(16)

                    Spacer()

                    VStack(alignment: .leading, spacing: 10) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .glassEffect(.regular.tint(.red.opacity(0.6)), in: .rect(cornerRadius: 12))
                        }
                        chips
                    }
                    .padding(16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            controls
                .padding(.top, 20)
                .padding(.bottom, 12)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                StoryDetailChip(
                    symbol: "mappin.and.ellipse",
                    text: locationName ?? "Add location",
                    isSet: locationName != nil,
                    onClear: locationName == nil ? nil : onClearLocation,
                    action: onEditLocation
                )

                StoryDetailChip(
                    symbol: "eye.slash",
                    text: labelSummary ?? "Content warning",
                    isSet: labelSummary != nil,
                    onClear: labelSummary == nil ? nil : onClearLabels,
                    action: onEditLabels
                )

                StoryDetailChip(
                    symbol: postToBluesky ? "checkmark.circle.fill" : "circle",
                    text: "Post to Bluesky",
                    isSet: postToBluesky,
                    onClear: nil
                ) {
                    postToBluesky.toggle()
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var controls: some View {
        HStack {
            Spacer()
            Button(action: onPost) {
                HStack(spacing: 8) {
                    if isUploading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Post")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .fontWeight(.semibold)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .disabled(isUploading)
            .accessibilityLabel(isUploading ? "Posting" : "Post story")
        }
        .padding(.horizontal, 24)
    }
}

/// Glass capsule over the photo that opens an editor for one story detail
/// and, once that detail is set, offers a clear button on its trailing edge.
struct StoryDetailChip: View {
    let symbol: String
    let text: String
    let isSet: Bool
    let onClear: (() -> Void)?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                    Text(text)
                        .font(.subheadline.weight(isSet ? .semibold : .regular))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.leading, 14)
                .padding(.trailing, onClear == nil ? 14 : 6)
                .padding(.vertical, 10)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.trailing, 10)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(text)")
            }
        }
        .glassEffect(isSet ? .regular.tint(Color.accentColor.opacity(0.5)) : .regular, in: .capsule)
    }
}

#Preview {
    @Previewable @State var bluesky = true
    ZStack {
        Color.black.ignoresSafeArea()
        StoryReviewStage(
            image: UIImage(systemName: "photo")!,
            locationName: "Golden Gate Park",
            labelSummary: nil,
            postToBluesky: $bluesky,
            errorMessage: nil,
            isUploading: false,
            onRetake: {},
            onEditLocation: {},
            onClearLocation: {},
            onEditLabels: {},
            onClearLabels: {},
            onPost: {}
        )
    }
    .grainPreview()
}
