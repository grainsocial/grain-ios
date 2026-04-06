import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let client: XRPCClient
    var onProfileEdited: (() -> Void)?
    @State private var includeExif = true
    @State private var hasLoadedExifPref = false

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
               let exif = prefs.includeExif {
                includeExif = exif
            }
            hasLoadedExifPref = true
        }
    }
}
