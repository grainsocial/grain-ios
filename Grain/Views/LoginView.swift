import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) private var auth
    @State private var handle = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Grain")
                        .font(.largeTitle.bold())
                    Text("Photo sharing on AT Protocol")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Login card with glass effect
                VStack(spacing: 16) {
                    TextField("Enter your handle", text: $handle)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button {
                        Task { await login() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Sign In")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(handle.isEmpty || isLoading)
                }
                .padding(24)
                .liquidGlass()
                .padding(.horizontal)

                if let errorMessage {
                    ScrollView {
                        Text(errorMessage)
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .padding(.horizontal)
                    }
                    .frame(maxHeight: 200)
                }

                Spacer()
            }
        }
    }

    private func login() async {
        isLoading = true
        errorMessage = nil
        do {
            try await auth.login(handle: handle)
        } catch {
            errorMessage = String(describing: error)
        }
        isLoading = false
    }
}
