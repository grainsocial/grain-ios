import SwiftUI

struct FeedsManagementView: View {
    @Environment(AuthManager.self) private var auth
    @Bindable var prefsViewModel: FeedPreferencesViewModel
    let client: XRPCClient

    @State private var cameras: [CameraItem] = []
    @State private var locations: [LocationItem] = []
    @State private var isLoadingDiscovery = false
    @State private var selectedCamera: String?
    @State private var selectedLocation: LocationDestination?

    private var coreIds: Set<String> {
        Set(PinnedFeed.defaults.map(\.id))
    }

    private var unpinnedDefaults: [PinnedFeed] {
        let pinnedIds = Set(prefsViewModel.pinnedFeeds.map(\.id))
        return PinnedFeed.defaults.filter { !pinnedIds.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                ForEach(prefsViewModel.pinnedFeeds) { feed in
                    feedRow(feed: feed, showPin: true)
                }
                .onMove { from, to in
                    var feeds = prefsViewModel.pinnedFeeds
                    feeds.move(fromOffsets: from, toOffset: to)
                    Task { await prefsViewModel.reorderFeeds(feeds, auth: auth.authContext()) }
                }
            } header: {
                Text("Pinned Feeds")
            }

            if !unpinnedDefaults.isEmpty {
                Section {
                    ForEach(unpinnedDefaults) { feed in
                        feedRow(feed: feed, showPin: false)
                    }
                } header: {
                    Text("Available Feeds")
                }
            }

            if !cameras.isEmpty {
                Section {
                    ForEach(cameras) { camera in
                        cameraRow(camera: camera)
                    }
                } header: {
                    Text("Cameras")
                }
            }

            if !locations.isEmpty {
                Section {
                    ForEach(locations) { location in
                        locationRow(location: location)
                    }
                } header: {
                    Text("Locations")
                }
            }
        }
        .navigationTitle("My Feeds")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        .navigationDestination(item: $selectedCamera) { camera in
            CameraFeedView(client: client, camera: camera)
        }
        .navigationDestination(item: $selectedLocation) { loc in
            LocationFeedView(client: client, h3Index: loc.h3Index, locationName: loc.name)
        }
        .task {
            guard !isLoadingDiscovery else { return }
            isLoadingDiscovery = true
            async let camerasReq = client.getCameras(auth: auth.authContext())
            async let locationsReq = client.getLocations(auth: auth.authContext())
            do {
                let (c, l) = try await (camerasReq, locationsReq)
                cameras = c.cameras ?? []
                locations = l.locations ?? []
            } catch {}
            isLoadingDiscovery = false
        }
    }

    private func feedRow(feed: PinnedFeed, showPin: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: feed))
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(feed.label)
                .font(.body)

            Spacer()

            if showPin {
                Button {
                    Task { await prefsViewModel.unpinFeed(feed.id, auth: auth.authContext()) }
                } label: {
                    Image(systemName: "pin.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unpin feed")
            } else {
                Button {
                    Task { await prefsViewModel.pinFeed(feed, auth: auth.authContext()) }
                } label: {
                    Image(systemName: "pin")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pin feed")
            }
        }
        .moveDisabled(!showPin)
    }

    private func cameraRow(camera: CameraItem) -> some View {
        let feedId = "camera:\(camera.camera)"
        let pinned = prefsViewModel.isPinned(feedId)
        return Button {
            selectedCamera = camera.camera
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading) {
                    Text(camera.camera)
                        .font(.body)
                    Text("\(camera.photoCount) photos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .moveDisabled(true)
    }

    private func locationRow(location: LocationItem) -> some View {
        let feedId = "location:\(location.h3Index)"
        let pinned = prefsViewModel.isPinned(feedId)
        return Button {
            selectedLocation = LocationDestination(h3Index: location.h3Index, name: location.name)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading) {
                    Text(location.name)
                        .font(.body)
                    Text("\(location.galleryCount) galleries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .moveDisabled(true)
    }

    private func iconName(for feed: PinnedFeed) -> String {
        switch feed.id {
        case "recent": "clock"
        case "following": "person.2"
        case "foryou": "sparkles"
        default:
            switch feed.type {
            case "camera": "camera"
            case "location": "mappin.and.ellipse"
            case "hashtag": "number"
            default: "pin"
            }
        }
    }
}

#Preview {
    NavigationStack {
        FeedsManagementView(
            prefsViewModel: FeedPreferencesViewModel(client: XRPCClient(baseURL: AuthManager.serverURL)),
            client: XRPCClient(baseURL: AuthManager.serverURL)
        )
    }
    .environment(AuthManager())
}
