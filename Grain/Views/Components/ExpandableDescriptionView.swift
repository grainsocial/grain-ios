import SwiftUI

struct ExpandableDescriptionView: View {
    let text: String
    var lineLimit: Int = 2
    var onMentionTap: ((String) -> Void)?
    var onHashtagTap: ((String) -> Void)?

    @State private var isExpanded = false
    @State private var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            RichTextView(
                text: text,
                color: .secondary,
                onMentionTap: onMentionTap,
                onHashtagTap: onHashtagTap
            )
            .lineLimit(isExpanded ? nil : lineLimit)
            .background(
                RichTextView(
                    text: text,
                    color: .clear,
                    onMentionTap: nil,
                    onHashtagTap: nil
                )
                .lineLimit(lineLimit)
                .hidden()
                .background(GeometryReader { truncatedGeo in
                    RichTextView(
                        text: text,
                        color: .clear,
                        onMentionTap: nil,
                        onHashtagTap: nil
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .background(GeometryReader { fullGeo in
                        Color.clear.onAppear {
                            isTruncated = fullGeo.size.height > truncatedGeo.size.height + 1
                        }
                    })
                })
            )

            if isTruncated, !isExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                } label: {
                    Text("more")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
