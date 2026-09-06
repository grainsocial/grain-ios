import SwiftUI

/// Every camera the explore chips only had room for the top of: a tile each,
/// two up, under a large heading that collapses as the grid scrolls.
struct CamerasView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(Router.self) private var router
    @State private var viewModel: CamerasViewModel

    let client: XRPCClient

    init(client: XRPCClient, viewModel: CamerasViewModel? = nil) {
        self.client = client
        _viewModel = State(initialValue: viewModel ?? CamerasViewModel(client: client))
    }

    var body: some View {
        ScrollView {
            if viewModel.cameras.isEmpty {
                Group {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text(viewModel.failed ? "Couldn't load cameras." : "No cameras yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                    ForEach(viewModel.cameras) { camera in
                        BrowseTile(
                            title: camera.camera,
                            meta: counted(camera.photoCount, "photo", "photos"),
                            thumbs: camera.thumbs ?? []
                        ) {
                            router.push(.camera(camera.camera))
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Cameras")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await viewModel.load(auth: auth.authContext()) }
        .task {
            guard !isPreview else { return }
            await viewModel.load(auth: auth.authContext())
        }
    }
}
