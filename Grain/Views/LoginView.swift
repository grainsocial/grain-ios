import NukeUI
import SwiftUI

struct LoginView: View {
    static let legalMarkdown =
        "By signing in you agree to our [Terms](https://grain.social/support/terms), " +
        "[Privacy Policy](https://grain.social/support/privacy), " +
        "and [Community Guidelines](https://grain.social/support/community-guidelines)."

    @Environment(AuthManager.self) private var auth
    @State private var handle = ""
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var suggestions: [ActorSuggestion] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let fullHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            ZStack {
                Image("login-bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: fullHeight)
                    .clipped()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ScrollViewReader { proxy in
                    ScrollView {
                        if suggestions.isEmpty {
                            Spacer()
                                .frame(minHeight: 100)
                                .frame(maxHeight: .infinity)
                        } else {
                            Spacer()
                                .frame(height: 60)
                        }

                        // Logo
                        Text("grain")
                            .font(.custom("Syne", size: 44).weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.bottom, suggestions.isEmpty ? 60 : 20)

                        if suggestions.isEmpty {
                            // Heading
                            Text("Log in with your internet handle")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 4)

                            Text("Enter the domain you use as your identity across the open social web.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)

                            Link("Learn more", destination: URL(string: "https://internethandle.org")!)
                                .font(.subheadline.weight(.medium))
                                .underline()
                                .foregroundStyle(.white)
                                .padding(.bottom, 16)
                        }

                        // Login card
                        VStack(spacing: 16) {
                            // Handle input
                            HStack(spacing: 10) {
                                Image(systemName: "at")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.5))

                                TextField("e.g. jasmine.garden", text: $handle, prompt: Text("e.g. jasmine.garden").foregroundStyle(.white.opacity(0.5)))
                                    .foregroundStyle(.white)
                                    .textContentType(.username)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .submitLabel(.go)
                                    .onSubmit {
                                        if !handle.isEmpty { Task { await login() } }
                                    }
                                    .onChange(of: handle) {
                                        searchTask?.cancel()
                                        let query = handle
                                        let trimmed = query.trimmingCharacters(in: .whitespaces)
                                        isSearching = trimmed.count >= 2
                                        searchTask = Task {
                                            try? await Task.sleep(for: .milliseconds(200))
                                            guard !Task.isCancelled else { return }
                                            await searchActors(query: query)
                                        }
                                    }

                                if isSearching {
                                    ProgressView()
                                        .tint(.white.opacity(0.7))
                                        .scaleEffect(0.8)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.25), lineWidth: 1)
                            )

                            // Suggestions
                            if !suggestions.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(suggestions) { actor in
                                        Button {
                                            handle = actor.handle
                                            suggestions = []
                                            Task { await login() }
                                        } label: {
                                            HStack(spacing: 10) {
                                                if let avatar = actor.avatar, let url = URL(string: avatar) {
                                                    LazyImage(url: url) { state in
                                                        if let image = state.image {
                                                            image.resizable().scaledToFill()
                                                        } else {
                                                            Circle().fill(.white.opacity(0.2))
                                                        }
                                                    }
                                                    .frame(width: 32, height: 32)
                                                    .clipShape(Circle())
                                                } else {
                                                    Circle()
                                                        .fill(.white.opacity(0.2))
                                                        .frame(width: 32, height: 32)
                                                }

                                                VStack(alignment: .leading, spacing: 1) {
                                                    if let displayName = actor.displayName, !displayName.isEmpty {
                                                        Text(displayName)
                                                            .font(.subheadline.weight(.medium))
                                                            .foregroundStyle(.white)
                                                            .lineLimit(1)
                                                    }
                                                    Text("@\(actor.handle)")
                                                        .font(.caption)
                                                        .foregroundStyle(.white.opacity(0.6))
                                                        .lineLimit(1)
                                                }

                                                Spacer()
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)

                                        if actor.id != suggestions.last?.id {
                                            Divider()
                                                .background(.white.opacity(0.15))
                                                .padding(.leading, 58)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                                .id("suggestions")
                            }

                            // Sign in button
                            Button {
                                Task { await login() }
                            } label: {
                                Group {
                                    if isLoading {
                                        ProgressView()
                                            .tint(.black)
                                    } else {
                                        Text("Sign In")
                                            .font(.body.weight(.semibold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                            }
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.black)
                            .disabled(handle.isEmpty || isLoading)
                            .opacity(handle.isEmpty ? 0.4 : 1)

                            // Create account button
                            Button {
                                Task { await createAccount() }
                            } label: {
                                Text("Create Account")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.25), lineWidth: 1)
                            )
                            .foregroundStyle(.white)
                            .disabled(isLoading)
                            // Legal links
                            Text(LocalizedStringKey(Self.legalMarkdown))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                                .tint(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        Spacer()
                            .frame(height: 60)
                    }
                    .frame(minHeight: geo.size.height)
                    .onChange(of: suggestions) {
                        if !suggestions.isEmpty {
                            withAnimation {
                                proxy.scrollTo("suggestions", anchor: .bottom)
                            }
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
            } // ScrollViewReader
        }
    }

    private func createAccount() async {
        isLoading = true
        errorMessage = nil
        do {
            try await auth.login(createAccount: true)
        } catch {
            errorMessage = String(describing: error)
        }
        isLoading = false
    }

    private func login() async {
        isLoading = true
        errorMessage = nil
        suggestions = []
        do {
            try await auth.login(handle: handle)
        } catch let XRPCError.httpError(statusCode, body) {
            let bodyStr = body.flatMap { String(data: $0, encoding: .utf8) } ?? "no body"
            errorMessage = "HTTP \(statusCode): \(bodyStr)"
        } catch {
            errorMessage = String(describing: error)
        }
        isLoading = false
    }

    private func searchActors(query: String) async {
        defer { isSearching = false }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            suggestions = []
            return
        }

        var components = URLComponents(string: "https://public.api.bsky.app/xrpc/app.bsky.actor.searchActorsTypeahead")!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = components.url else { return }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actors = json["actors"] as? [[String: Any]]
        else {
            return
        }

        suggestions = actors.compactMap { dict in
            guard let handle = dict["handle"] as? String else { return nil }
            return ActorSuggestion(
                handle: handle,
                displayName: dict["displayName"] as? String,
                avatar: dict["avatar"] as? String
            )
        }
    }
}

private struct ActorSuggestion: Identifiable, Equatable {
    let handle: String
    let displayName: String?
    let avatar: String?
    var id: String {
        handle
    }
}
