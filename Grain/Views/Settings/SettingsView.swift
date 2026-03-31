import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let client: XRPCClient

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
                    EditProfileView(client: client)
                }
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
}
