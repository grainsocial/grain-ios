import SwiftUI

struct PhotoEditor: View {
    @Binding var items: [PhotoItem]
    @Binding var selectedPhotoID: UUID?
    let sendExif: Bool

    @State private var isExpanded = false
    @State private var showingCarouselAlt = false

    private var selectedIndex: Int? {
        guard let id = selectedPhotoID else { return nil }
        return items.firstIndex(where: { $0.id == id })
    }

    var body: some View {
        // MARK: Photos section (strip OR grid)

        Section {
            Group {
                if isExpanded {
                    ReorderablePhotoGrid(
                        items: $items,
                        selectedPhotoID: $selectedPhotoID
                    )
                } else {
                    ReorderablePhotoStrip(
                        items: $items,
                        selectedPhotoID: $selectedPhotoID
                    )
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        } header: {
            HStack {
                Text("Photos")
                Spacer()
                Button {
                    withAnimation(.smooth) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded
                        ? "rectangle.compress.vertical"
                        : "rectangle.expand.vertical")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse photos" : "Expand photos")
            }
        }

        // MARK: Post Preview section (carousel + EXIF) — strip mode only

        if let idx = selectedIndex, !isExpanded {
            Section {
                VStack(spacing: 0) {
                    photoCarousel
                    exifInfo(for: items[idx])
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.black)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.black)
            } header: {
                Text("Post Preview")
            }
            // Skip implicit animations on this section's appearance so the TabView
            // doesn't animate to the selected page when grid → strip switches.
            .transaction { $0.disablesAnimations = true }
        }

        // MARK: Alt text section — both modes, tied to selectedPhotoID

        if let idx = selectedIndex {
            Section {
                TextField(
                    "Add a description for accessibility",
                    text: $items[idx].alt,
                    axis: .vertical
                )
                .font(.subheadline)
                .lineLimit(2 ... 4)
            } header: {
                Text("Alt text")
            }
        }
    }

    // MARK: - Carousel (mirrors GalleryCardView.photoCarousel)

    private func ratio(for item: PhotoItem) -> CGFloat {
        let w = item.thumbnail.size.width
        let h = item.thumbnail.size.height
        guard h > 0 else { return 1 }
        return w / h
    }

    @ViewBuilder
    private var photoCarousel: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            let ratios = items.map(ratio(for:))
            let hasMixedRatios = Set(ratios.map { Int($0 * 100) }).count > 1
            let safeIdx = min(max(selectedIndex ?? 0, 0), items.count - 1)
            let carouselRatio: CGFloat = hasMixedRatios
                ? max(ratios.min() ?? 1, 0.56)
                : ratios[safeIdx]

            GeometryReader { geo in
                let height = geo.size.width / carouselRatio

                ZStack(alignment: .bottom) {
                    Color.black

                    TabView(selection: $selectedPhotoID) {
                        ForEach(items) { item in
                            ZStack {
                                ZoomableImage(
                                    localImage: item.thumbnail,
                                    aspectRatio: ratio(for: item)
                                )

                                if showingCarouselAlt {
                                    let alt = item.alt.trimmingCharacters(in: .whitespaces)
                                    if !alt.isEmpty {
                                        ZStack {
                                            Color.black.opacity(0.6)
                                            Text(alt)
                                                .font(.subheadline)
                                                .foregroundStyle(.white)
                                                .multilineTextAlignment(.center)
                                                .padding(20)
                                        }
                                        .allowsHitTesting(false)
                                    }
                                }
                            }
                            .tag(item.id as UUID?)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    pageIndicator
                    altPillIndicator(for: safeIdx)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    let alt = items[safeIdx].alt.trimmingCharacters(in: .whitespaces)
                    guard !alt.isEmpty else { return }
                    withAnimation(.smooth) { showingCarouselAlt.toggle() }
                }
                .onChange(of: selectedPhotoID) { showingCarouselAlt = false }
                .frame(height: height)
            }
            .aspectRatio(carouselRatio, contentMode: .fit)
        }
    }

    @ViewBuilder
    private var pageIndicator: some View {
        if items.count > 1 {
            let current = selectedIndex ?? 0
            let ratios = items.map(ratio(for:))
            let hasPortrait = ratios.contains { $0 < 1 }
            HStack(spacing: 5) {
                let total = items.count
                let maxVisible = 5
                let start = total <= maxVisible ? 0 : min(max(current - 2, 0), total - maxVisible)
                let end = total <= maxVisible ? total : start + maxVisible

                ForEach(start ..< end, id: \.self) { index in
                    let distance = abs(index - current)
                    let currentIsLandscape = ratios[current] >= 1
                    let dotColor: Color = hasPortrait && currentIsLandscape ? .secondary : .white
                    Circle()
                        .fill(dotColor.opacity(index == current ? 1.0 : distance == 1 ? 0.5 : distance == 2 ? 0.3 : 0.2))
                        .frame(
                            width: distance <= 1 ? 6 : distance == 2 ? 4 : 3,
                            height: distance <= 1 ? 6 : distance == 2 ? 4 : 3
                        )
                        .animation(.smooth, value: current)
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func altPillIndicator(for index: Int) -> some View {
        let hasAlt = !items[index].alt.trimmingCharacters(in: .whitespaces).isEmpty
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text("ALT")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .opacity(hasAlt ? 1 : 0.5)
                    .padding(8)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - EXIF Info (mirrors ExifInfoView from the feed)

    @ViewBuilder
    private func exifInfo(for item: PhotoItem) -> some View {
        if let exif = item.exifSummary {
            VStack(alignment: .leading, spacing: 4) {
                if let camera = exif.camera {
                    HStack(spacing: 6) {
                        Image(systemName: "camera").font(.caption2)
                        Text(camera).font(.caption)
                    }
                    .foregroundStyle(sendExif ? .secondary : .tertiary)
                }
                if let lens = exif.lens {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.circle").font(.caption2)
                        Text(lens).font(.caption)
                    }
                    .foregroundStyle(sendExif ? .secondary : .tertiary)
                }
                let settingsParts = [exif.shutterSpeed, exif.aperture, exif.iso, exif.focalLength].compactMap(\.self)
                if !settingsParts.isEmpty {
                    Text(settingsParts.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(sendExif ? .secondary : .tertiary)
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var state: [PhotoItem] = PreviewData.photoItems
    @Previewable @State var selected: UUID?
    @Previewable @State var zoomState = ImageZoomState()
    Form {
        PhotoEditor(items: $state, selectedPhotoID: $selected, sendExif: true)
    }
    .environment(zoomState)
    .modifier(ImageZoomOverlay(zoomState: zoomState))
    .onAppear { selected = state.first?.id }
    .preferredColorScheme(.dark)
}
