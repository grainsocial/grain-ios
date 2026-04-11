import Nuke
import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let client: XRPCClient
    @State private var cacheSizeText = "Calculating..."
    @State private var includeExif = true
    @State private var includeLocation = true
    @State private var hasLoadedPrefs = false
    @AppStorage("privacy.showSuggestedUsers") private var showSuggestedUsers = true
    @State private var showCopiedToast = false

    var body: some View {
        List {
            Section("Account") {
                if let handle = auth.userHandle {
                    Menu {
                        Button { copyText("@\(handle)") } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    } label: {
                        LabeledContent("Handle", value: "@\(handle)")
                    }
                    .foregroundStyle(.primary)
                }
                if let did = auth.userDID {
                    Menu {
                        Button { copyText(did) } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    } label: {
                        LabeledContent("DID", value: did)
                            .font(.caption)
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section("Notifications") {
                NavigationLink {
                    NotificationSettingsView(client: client)
                } label: {
                    Label("Notifications", systemImage: "bell")
                }
            }

            Section("Moderation") {
                NavigationLink {
                    ModerationView(client: client)
                } label: {
                    Label("Moderation", systemImage: "shield")
                }
            }

            Section {
                Toggle("Include location", isOn: $includeLocation)
                    .onChange(of: includeLocation) {
                        guard hasLoadedPrefs else { return }
                        Task {
                            guard let authContext = await auth.authContext() else { return }
                            try? await client.putIncludeLocation(includeLocation, auth: authContext)
                        }
                    }
                Toggle("Include camera data", isOn: $includeExif)
                    .onChange(of: includeExif) {
                        guard hasLoadedPrefs else { return }
                        Task {
                            guard let authContext = await auth.authContext() else { return }
                            try? await client.putIncludeExif(includeExif, auth: authContext)
                        }
                    }
                Toggle("Show suggested users", isOn: $showSuggestedUsers)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Camera data includes make, model, and exposure info. Location is auto-detected from photo metadata when available.")
            }

            Section("Storage") {
                LabeledContent("Image Cache", value: cacheSizeText)
                Button("Clear Image Cache", role: .destructive) {
                    clearImageCache()
                }
            }
            .task {
                guard !isPreview else { return }
                updateCacheSize()
            }

            Section("Legal") {
                Link("Privacy Policy", destination: URL(string: "https://grain.social/support/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://grain.social/support/terms")!)
                Link("Copyright Policy", destination: URL(string: "https://grain.social/support/copyright")!)
            }

            Section("About") {
                Link("Powered by AT Protocol", destination: URL(string: "https://atproto.com")!)
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    auth.logout()
                    dismiss()
                }
            }
        }
        .navigationTitle("Settings")
        .overlay(alignment: .center) {
            if showCopiedToast { CopiedCheckmarkToast() }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showCopiedToast)
        .sensoryFeedback(.impact(weight: .medium), trigger: showCopiedToast)
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

    private func copyText(_ text: String) {
        UIPasteboard.general.string = text
        showCopiedToast = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showCopiedToast = false
        }
    }

    private func updateCacheSize() {
        guard let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache else {
            cacheSizeText = "Unknown"
            return
        }
        let size = dataCache.totalSize
        cacheSizeText = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private func clearImageCache() {
        ImagePipeline.shared.cache.removeAll()
        if let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
            dataCache.removeAll()
        }
        cacheSizeText = "Zero KB"
    }
}

struct CopiedCheckmarkToast: View {
    @State private var checkScale = 0.3

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .scaleEffect(checkScale)
                .onAppear {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        checkScale = 1.0
                    }
                }
            Text("Copied")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .transition(.scale.combined(with: .opacity))
    }
}

#Preview {
    SettingsView(client: .preview)
        .previewEnvironments()
}
