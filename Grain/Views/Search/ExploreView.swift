import SwiftUI

/// The explore page, as on grain.social: chips for the top cameras and places
/// over a grid of the recent feed. Lives under the search field and shows
/// whenever nothing has been typed.
struct ExploreView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(Router.self) private var router
    @State private var viewModel: ExploreViewModel
    @State private var width: CGFloat = 0

    let client: XRPCClient

    /// How many chips a group shows before deferring to its index screen.
    private static let chipLimit = 10
    private static let columns = 3
    private static let spacing: CGFloat = 2

    init(client: XRPCClient, viewModel: ExploreViewModel? = nil) {
        self.client = client
        _viewModel = State(initialValue: viewModel ?? ExploreViewModel(client: client))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !viewModel.cameras.isEmpty {
                    ChipGroup(
                        label: "Cameras",
                        chips: viewModel.cameras.prefix(Self.chipLimit).map { camera in
                            Chip(title: camera.camera) { router.push(.camera(camera.camera)) }
                        },
                        seeAll: viewModel.cameras.count > Self.chipLimit ? { router.push(.cameras) } : nil
                    )
                }
                if !viewModel.locations.isEmpty {
                    ChipGroup(
                        label: "Locations",
                        chips: viewModel.locations.prefix(Self.chipLimit).map { place in
                            Chip(title: place.name) {
                                router.push(.locations(cell: place.h3Index, name: place.name, galleryCount: place.galleryCount))
                            }
                        },
                        seeAll: viewModel.locations.count > Self.chipLimit ? { router.push(.locations()) } : nil
                    )
                }

                grid
                    .padding(.top, 8)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .refreshable { await viewModel.refresh(auth: auth.authContext()) }
        .task {
            guard !isPreview else { return }
            await viewModel.loadIfNeeded(auth: auth.authContext())
        }
    }

    @ViewBuilder
    private var grid: some View {
        if viewModel.galleries.isEmpty {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Text("Nothing to explore yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            let cellWidth = max((width - Self.spacing * CGFloat(Self.columns - 1)) / CGFloat(Self.columns), 0)
            let cellSize = CGSize(width: cellWidth, height: cellWidth * 4 / 3)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: Self.columns),
                spacing: Self.spacing
            ) {
                ForEach(viewModel.galleries) { gallery in
                    GalleryThumbnailCell(gallery: gallery, cellSize: cellSize) {
                        router.push(.gallery(uri: gallery.uri))
                    }
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .onAppear {
                        if gallery.id == viewModel.galleries.last?.id {
                            Task { await viewModel.loadMore(auth: auth.authContext()) }
                        }
                    }
                }
            }
            if viewModel.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
}

private struct Chip: Identifiable {
    let id = UUID()
    let title: String
    let action: () -> Void
}

/// A small uppercase label over a wrapping row of chips, with an optional
/// "See all" at the end when the row is only the top of a longer list.
private struct ChipGroup: View {
    let label: String
    let chips: [Chip]
    let seeAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(0.9)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(chips) { chip in
                    Button(chip.title, action: chip.action)
                        .buttonStyle(ChipStyle(prominent: false))
                }
                if let seeAll {
                    Button("See all", action: seeAll)
                        .buttonStyle(ChipStyle(prominent: true))
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

private struct ChipStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(prominent ? Color.accentColor : Color.primary.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(prominent ? Color.clear : Color(.secondarySystemBackground), in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
