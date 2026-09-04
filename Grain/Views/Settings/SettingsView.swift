import AuthenticationServices
import Nuke
import SafariServices
import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let client: XRPCClient
    @State private var cacheSizeText = "Calculating..."
    @State private var safariURL: URL?
    @State private var showAddAccount = false
    @State private var switchingDID: String?
    @State private var switchError: String?

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
                ForEach(auth.accounts) { account in
                    AccountRow(
                        account: account,
                        isActive: account.did == auth.userDID,
                        isSwitching: switchingDID == account.did
                    ) {
                        Task { await switchTo(account) }
                    }
                    // Full swipe is off: signing out is destructive enough to
                    // deserve a deliberate tap. The explicit tint is load-
                    // bearing — the list's `.tint(.primary)` would otherwise
                    // override the destructive role and paint the button white
                    // in dark mode.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await auth.signOut(did: account.did) }
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .tint(.red)
                    }
                }
                Button {
                    showAddAccount = true
                } label: {
                    Label("Add another account", systemImage: "plus")
                }
                .disabled(switchingDID != nil)
            } header: {
                Text("Accounts")
            } footer: {
                if let switchError {
                    Text(switchError).foregroundStyle(.red)
                }
            }

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
                Button("Sign out", role: .destructive) {
                    Task {
                        await auth.logout()
                        dismiss()
                    }
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
        .sheet(isPresented: $showAddAccount) {
            AddAccountView()
                .environment(auth)
        }
        .navigationTitle("Settings")
        .tint(.primary)
    }

    /// Switching rebuilds the app around the new account, so this view goes
    /// away with it — dismissing keeps Settings from flashing back on top.
    private func switchTo(_ account: StoredAccount) async {
        guard account.did != auth.userDID, switchingDID == nil else { return }
        switchingDID = account.did
        switchError = nil
        do {
            try await auth.switchTo(did: account.did)
            dismiss()
        } catch {
            switchError = error.localizedDescription
        }
        switchingDID = nil
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

struct AccountRow: View {
    let account: StoredAccount
    let isActive: Bool
    let isSwitching: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AvatarView(url: account.avatar, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.handle.map { "@\($0)" } ?? account.did)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isActive {
                        Text("Signed in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSwitching {
                    ProgressView()
                } else if isActive {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .disabled(isActive)
    }
}

/// Sign in to an additional account without disturbing the current one.
struct AddAccountView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var handle = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("e.g. user.bsky.social", text: $handle)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .focused($isInputFocused)
                        .onSubmit { Task { await add() } }
                } header: {
                    Text("Handle")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else {
                        Text("Grain switches to this account once you sign in. Your other accounts stay signed in.")
                    }
                }

                Section {
                    Button {
                        Task { await add() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                            }
                            Text("Sign in")
                        }
                    }
                    .disabled(handle.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
            }
            .navigationTitle("Add account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { isInputFocused = true }
        }
    }

    private func add() async {
        let trimmed = handle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await auth.login(handle: trimmed)
            dismiss()
        } catch XRPCError.authorizationDenied, ASWebAuthenticationSessionError.canceledLogin {
            // Backing out of the sign-in sheet isn't a failure worth reporting.
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct AccountDetailView: View {
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
                                Label("Copy handle", systemImage: "doc.on.doc")
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
                        Text("Delete account")
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
            Button("Delete account", role: .destructive) { Task { await performDelete() } }
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
            await auth.logout()
            dismiss()
        } catch {
            deleteError = error.localizedDescription
            isDeleting = false
        }
    }
}

struct FeedsSettingsView: View {
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

struct AppearanceSettingsView: View {
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

struct UploadDefaultsView: View {
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
                if let exif = prefs.includeExif {
                    includeExif = exif
                }
                if let location = prefs.includeLocation {
                    includeLocation = location
                }
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
