import SwiftUI
import NukeUI

struct SearchView: View {
    @Environment(AuthManager.self) private var auth
    @Bindable var viewModel: SearchViewModel
    @State private var searchNavigationUri: String?
    @State private var selectedProfileDid: String?
    @State private var selectedHashtag: String?
    let client: XRPCClient

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.searchText.isEmpty {
                ContentUnavailableView("Search", systemImage: "magnifyingglass", description: Text("Search for galleries and profiles"))
            } else {
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
                                GalleryCardView(gallery: $gallery, client: client, onNavigate: {
                                    searchNavigationUri = gallery.uri
                                }, onProfileTap: { did in
                                    selectedProfileDid = did
                                }, onHashtagTap: { tag in
                                    selectedHashtag = tag
                                })
                            }
                        case .profiles:
                            ForEach(viewModel.profileResults) { profile in
                                Button {
                                    selectedProfileDid = profile.did
                                } label: {
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
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top)
                }
            }
        }
        .onChange(of: viewModel.selectedTab) {
            if !viewModel.searchText.isEmpty {
                Task { await viewModel.search(auth: auth.authContext()) }
            }
        }
        .navigationDestination(item: $searchNavigationUri) { uri in
            GalleryDetailView(client: client, galleryUri: uri)
        }
        .navigationDestination(item: $selectedProfileDid) { did in
            ProfileView(client: client, did: did)
        }
        .navigationDestination(item: $selectedHashtag) { tag in
            HashtagFeedView(client: client, tag: tag)
        }
    }
}
