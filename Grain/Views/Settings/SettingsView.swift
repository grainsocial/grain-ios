import Nuke
import SafariServices
import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let client: XRPCClient
    @State private var cacheSizeText = "Calculating..."
    @State private var safariURL: URL?

    @AppStorage("appearance") private var appearance: String = "auto"

    private var appearanceLabel: String {
        switch appearance {
        case "light": "Light"
        case "dark": "Dark"
        default: "Auto"
        }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    LabeledContent("Appearance", value: appearanceLabel)
                }
                NavigationLink("Account") {
                    AccountDetailView(client: client)
                }
                NavigationLink("Notifications") {
                    NotificationSettingsView(client: client)
                }
                NavigationLink("Moderation") {
                    ModerationView(client: client)
                }
                NavigationLink("Feeds") {
                    FeedsSettingsView()
                }
                NavigationLink("Privacy") {
                    UploadDefaultsView(client: client)
                }
            }

            Section {
                settingsLink("Privacy Policy", url: "https://grain.social/support/privacy")
                settingsLink("Terms of Service", url: "https://grain.social/support/terms")
                settingsLink("Copyright Policy", url: "https://grain.social/support/copyright")
                settingsLink("Community Guidelines", url: "https://grain.social/support/community-guidelines")
                settingsLink("AT Protocol", url: "https://atproto.com")
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    auth.logout()
                    dismiss()
                }
            }

            Section {
                Button {
                    clearImageCache()
                } label: {
                    HStack {
                        Text("Clear cache")
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        Text(cacheSizeText)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                guard !isPreview else { return }
                updateCacheSize()
            }
        }
        .sheet(item: $safariURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
        .navigationTitle("Settings")
        .tint(.primary)
    }

    private func updateCacheSize() {
        guard let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache else {
            cacheSizeText = "Unknown"
            return
        }
        let size = dataCache.totalSize
        cacheSizeText = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private func settingsLink(_ title: String, url: String) -> some View {
        Button {
            safariURL = URL(string: url)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func clearImageCache() {
        ImagePipeline.shared.cache.removeAll()
        if let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
            dataCache.removeAll()
        }
        cacheSizeText = "Zero KB"
    }
}

extension URL: @retroactive Identifiable {
    public var id: String {
        absoluteString
    }
}

private struct AccountDetailView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let client: XRPCClient
    @State private var safariURL: URL?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        List {
            Section {
                if let handle = auth.userHandle {
                    LabeledContent("Handle", value: "@\(handle)")
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = "@\(handle)"
                            } label: {
                                Label("Copy Handle", systemImage: "doc.on.doc")
                            }
                        }
                }
                if let did = auth.userDID {
                    LabeledContent("DID", value: did)
                        .font(.caption)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = did
                            } label: {
                                Label("Copy DID", systemImage: "doc.on.doc")
                            }
                        }
                }
            }

            Section {
                if let did = auth.userDID {
                    Button {
                        safariURL = URL(string: "https://pdsls.dev/at://\(did)")
                    } label: {
                        HStack {
                            Text("Manage your data")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    if isDeleting {
                        HStack {
                            ProgressView()
                            Text("Deleting…")
                        }
                    } else {
                        Text("Delete Account")
                    }
                }
                .disabled(isDeleting)
            } footer: {
                if let deleteError {
                    Text(deleteError).foregroundStyle(.red)
                }
            }
        }
        .sheet(item: $safariURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
        .navigationTitle("Account")
        .tint(.primary)
        .alert("Delete your Grain account?", isPresented: $showDeleteConfirm) {
            Button("Delete Account", role: .destructive) { Task { await performDelete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all your Grain galleries, stories, photos, favorites, comments, follows, and blocks. Your atproto identity is separate and is not affected. This cannot be undone.")
        }
    }

    private func performDelete() async {
        guard let authContext = await auth.authContext() else { return }
        isDeleting = true
        deleteError = nil
        do {
            try await client.deleteAccount(auth: authContext)
            auth.logout()
            dismiss()
        } catch {
            deleteError = error.localizedDescription
            isDeleting = false
        }
    }
}

private struct FeedsSettingsView: View {
    @AppStorage("privacy.showSuggestedUsers") private var showSuggestedUsers = true

    var body: some View {
        List {
            Section {
                Toggle("Show suggested users", isOn: $showSuggestedUsers)
            }
        }
        .navigationTitle("Feeds")
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage("appearance") private var appearance: String = "auto"

    var body: some View {
        List {
            Section {
                ForEach(["auto", "light", "dark"], id: \.self) { option in
                    HStack {
                        Text(option == "auto" ? "Automatic" : option == "light" ? "Light" : "Dark")
                        Spacer()
                        if appearance == option {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appearance = option
                    }
                }
            } footer: {
                Text("Automatic follows your device's system setting.")
            }
        }
        .navigationTitle("Appearance")
    }
}

private struct UploadDefaultsView: View {
    @Environment(AuthManager.self) private var auth
    let client: XRPCClient
    @State private var includeExif = true
    @State private var includeLocation = true
    @State private var hasLoadedPrefs = false

    var body: some View {
        List {
            Section("Defaults for new uploads") {
                Toggle(isOn: $includeLocation) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include location")
                        Text("Auto-detected from photo metadata")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: includeLocation) {
                    guard hasLoadedPrefs else { return }
                    Task {
                        guard let authContext = await auth.authContext() else { return }
                        try? await client.putIncludeLocation(includeLocation, auth: authContext)
                    }
                }
                Toggle(isOn: $includeExif) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include camera data")
                        Text("Make, model, and exposure info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: includeExif) {
                    guard hasLoadedPrefs else { return }
                    Task {
                        guard let authContext = await auth.authContext() else { return }
                        try? await client.putIncludeExif(includeExif, auth: authContext)
                    }
                }
            }
        }
        .navigationTitle("Privacy")
        .task {
            if let authContext = await auth.authContext(),
               let prefs = try? await client.getPreferences(auth: authContext).preferences
            {
                if let exif = prefs.includeExif { includeExif = exif }
                if let location = prefs.includeLocation { includeLocation = location }
            }
            hasLoadedPrefs = true
        }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context _: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_: SFSafariViewController, context _: Context) {}
}

#Preview {
    SettingsView(client: .preview)
        .previewEnvironments()
}
