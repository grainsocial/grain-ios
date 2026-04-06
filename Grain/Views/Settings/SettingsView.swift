import Nuke
import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let client: XRPCClient
    @State private var cacheSizeText = "Calculating..."
    @AppStorage("privacy.includeLocation") private var includeLocation = true
    @AppStorage("privacy.includeCameraData") private var includeCameraData = true
    @AppStorage("privacy.showSuggestedUsers") private var showSuggestedUsers = true

    var body: some View {
        List {
            Section("Account") {
                if let handle = auth.userHandle {
                    LabeledContent("Handle", value: "@\(handle)")
                }
                if let did = auth.userDID {
                    LabeledContent("DID", value: did)
                        .font(.caption)
                }
            }

            Section("Photos") {
                Toggle("Include camera data (EXIF) when uploading", isOn: $includeExif)
                    .onChange(of: includeExif) {
                        guard hasLoadedExifPref else { return }
                        Task {
                            guard let authContext = await auth.authContext() else { return }
                            try? await client.putIncludeExif(includeExif, auth: authContext)
                        }
                    }
            }

            Section {
                Toggle("Include location", isOn: $includeLocation)
                Toggle("Include camera data", isOn: $includeCameraData)
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
        .task {
            if let authContext = await auth.authContext(),
               let prefs = try? await client.getPreferences(auth: authContext).preferences,
               let exif = prefs.includeExif
            {
                includeExif = exif
            }
            hasLoadedExifPref = true
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
