import NaturalLanguage
import SwiftUI
import Translation

struct ExpandableDescriptionView: View {
    let text: String
    var lineLimit: Int = 2
    var onMentionTap: ((String) -> Void)?
    var onHashtagTap: ((String) -> Void)?

    @State private var isExpanded = false
    @State private var isTruncated = false
    @State private var showTranslation = false
    @State private var isForeignLanguage = false

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
            .contentShape(Rectangle())
            .onTapGesture {
                if isTruncated, !isExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                }
            }

            HStack(spacing: 12) {
                if isTruncated, !isExpanded {
                    Text("more")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                if isForeignLanguage {
                    Button {
                        showTranslation = true
                    } label: {
                        Text("translate")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .translationPresentation(isPresented: $showTranslation, text: text)
        .onAppear {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            if let detected = recognizer.dominantLanguage?.rawValue {
                let preferred = Locale.preferredLanguages.first ?? "en"
                isForeignLanguage = !preferred.hasPrefix(detected)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        ExpandableDescriptionView(text: "Short caption.")
        ExpandableDescriptionView(
            text: "A much longer caption that keeps going well past two lines. Photographed at golden hour in the hills above the city. Shot with #35mm film, developed in Rodinal. See @alice.grain.social for the full series.",
            onMentionTap: { _ in },
            onHashtagTap: { _ in }
        )
    }
    .padding()
    .preferredColorScheme(.dark)
    .tint(Color.accentColor)
}
