import SwiftUI
import NukeUI

struct SearchView: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: SearchViewModel
    @State private var searchNavigationUri: String?
    let client: XRPCClient

    init(client: XRPCClient) {
        self.client = client
        _viewModel = State(initialValue: SearchViewModel(client: client))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.searchText.isEmpty {
                    // Discovery view
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if !viewModel.locations.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Locations")
                                        .font(.headline)
                                        .padding(.horizontal)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(viewModel.locations) { location in
                                                VStack {
                                                    Text(location.name)
                                                        .font(.subheadline.bold())
                                                    Text("\(location.galleryCount) galleries")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }

                            if !viewModel.cameras.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Cameras")
                                        .font(.headline)
                                        .padding(.horizontal)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(viewModel.cameras) { camera in
                                                VStack {
                                                    Text(camera.camera)
                                                        .font(.subheadline.bold())
                                                    Text("\(camera.photoCount) photos")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                } else {
                    // Search results
                    Picker("Search", selection: $viewModel.selectedTab) {
                        ForEach(SearchViewModel.SearchTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            switch viewModel.selectedTab {
                            case .galleries:
                                ForEach($viewModel.galleryResults) { $gallery in
                                    GalleryCardView(gallery: $gallery, client: client) {
                                        searchNavigationUri = gallery.uri
                                    }
                                }
                            case .profiles:
                                ForEach(viewModel.profileResults) { profile in
                                    HStack {
                                        AvatarView(url: profile.avatar, size: 40)
                                        VStack(alignment: .leading) {
                                            Text(profile.displayName ?? profile.handle ?? "")
                                                .font(.subheadline.bold())
                                            if let handle = profile.handle {
                                                Text("@\(handle)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.top)
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.searchText, prompt: "Search galleries & profiles")
            .onSubmit(of: .search) {
                Task { await viewModel.search(auth: auth.authContext()) }
            }
            .onChange(of: viewModel.selectedTab) {
                if !viewModel.searchText.isEmpty {
                    Task { await viewModel.search(auth: auth.authContext()) }
                }
            }
            .task {
                await viewModel.loadDiscovery(auth: auth.authContext())
            }
            .navigationDestination(item: $searchNavigationUri) { uri in
                GalleryDetailView(client: client, galleryUri: uri)
            }
        }
    }
}
