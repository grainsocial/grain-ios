import Nuke
import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let client: XRPCClient
    var onProfileEdited: (() -> Void)?
    @State private var cacheSizeText = "Calculating..."

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

            Section {
                NavigationLink("Edit Profile") {
                    EditProfileView(client: client, onSaved: onProfileEdited)
                }
            }

            Section("Storage") {
                LabeledContent("Image Cache", value: cacheSizeText)
                Button("Clear Image Cache", role: .destructive) {
                    clearImageCache()
                }
            }
            .task {
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
