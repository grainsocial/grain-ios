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
    @State private var highlightedSuggestionIndex: Int?
    @Namespace private var suggestionHighlightNS

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

                        if let reason = auth.reauthReason, suggestions.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.white)
                                Text(reason)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.25), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }

                        if suggestions.isEmpty {
                            // Heading
                            Text("Log in with your atmosphere account")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 4)

                            AtmosphereLogosMarquee()
                                .padding(.bottom, 16)
                        }

                        // Login card
                        VStack(spacing: 16) {
                            // Handle input
                            HStack(spacing: 10) {
                                Image(systemName: "at")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.5))

                                TextField("e.g. user.bsky.social", text: $handle, prompt: Text("e.g. user.bsky.social").foregroundStyle(.white.opacity(0.5)))
                                    .foregroundStyle(.white)
                                    .textContentType(.username)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .submitLabel(.go)
                                    .onSubmit(submitFromKeyboard)
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
                                    .onKeyPress(.downArrow) {
                                        moveSuggestionHighlight(by: 1)
                                    }
                                    .onKeyPress(.upArrow) {
                                        moveSuggestionHighlight(by: -1)
                                    }
                                    .onKeyPress(.tab) {
                                        moveSuggestionHighlight(by: 1, wrap: true)
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
                                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, actor in
                                        let isHighlighted = highlightedSuggestionIndex == index
                                        Button {
                                            handle = actor.handle
                                            suggestions = []
                                            highlightedSuggestionIndex = nil
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
                                            .background {
                                                if isHighlighted {
                                                    Color.clear
                                                        .glassEffect(
                                                            .regular.tint(Color.accentColor.opacity(0.45)),
                                                            in: .rect(cornerRadius: 12)
                                                        )
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .matchedGeometryEffect(id: "suggestion-highlight", in: suggestionHighlightNS)
                                                }
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .id(actor.id)

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
                    .onChange(of: suggestions) { _, newValue in
                        if newValue.isEmpty {
                            highlightedSuggestionIndex = nil
                        } else if let idx = highlightedSuggestionIndex, idx >= newValue.count {
                            highlightedSuggestionIndex = newValue.count - 1
                        }
                        if !newValue.isEmpty {
                            withAnimation {
                                proxy.scrollTo("suggestions", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: highlightedSuggestionIndex) { _, newIndex in
                        guard let idx = newIndex, suggestions.indices.contains(idx) else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(suggestions[idx].id, anchor: .center)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
            } // ScrollViewReader
        }
    }

    /// Move the keyboard highlight up or down the suggestions list.
    /// `wrap` (used for Tab) jumps back to the first item after the last.
    /// Up-arrow off the first item deselects so the TextField regains focus.
    /// The state change is wrapped in `withAnimation` so the matched-geometry
    /// highlight layer physically slides between rows.
    private func moveSuggestionHighlight(by delta: Int, wrap: Bool = false) -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        let last = suggestions.count - 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            if let current = highlightedSuggestionIndex {
                let next = current + delta
                if next < 0 {
                    highlightedSuggestionIndex = nil
                } else if next > last {
                    highlightedSuggestionIndex = wrap ? 0 : last
                } else {
                    highlightedSuggestionIndex = next
                }
            } else {
                highlightedSuggestionIndex = delta >= 0 ? 0 : last
            }
        }
        return .handled
    }

    /// Submit either the highlighted suggestion or the raw handle text,
    /// mirroring the behavior of clicking a row vs. tapping Sign In.
    private func submitFromKeyboard() {
        if let idx = highlightedSuggestionIndex, suggestions.indices.contains(idx) {
            handle = suggestions[idx].handle
            suggestions = []
            highlightedSuggestionIndex = nil
            Task { await login() }
        } else if !handle.isEmpty {
            Task { await login() }
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

        var components = URLComponents(url: AuthManager.serverURL.appendingPathComponent("xrpc/social.grain.unspecced.searchActorsTypeahead"), resolvingAgainstBaseURL: false)!
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

// MARK: - Atmosphere Logos Marquee

private struct AtmosphereApp: Identifiable {
    let name: String
    let logo: String
    var id: String {
        name
    }
}

private struct AtmosphereLogosMarquee: View {
    private static let apps: [AtmosphereApp] = [
        .init(name: "Bluesky", logo: "atmo-bluesky"),
        .init(name: "Tangled", logo: "atmo-tangled"),
        .init(name: "Anisota", logo: "atmo-anisota"),
        .init(name: "Beacon Bits", logo: "atmo-beacon-bits"),
        .init(name: "Eurosky", logo: "atmo-eurosky"),
        .init(name: "Flashes", logo: "atmo-flashes"),
        .init(name: "Gander", logo: "atmo-gander"),
        .init(name: "Germ", logo: "atmo-germ"),
        .init(name: "Leaflet", logo: "atmo-leaflet"),
        .init(name: "Northsky", logo: "atmo-northsky"),
        .init(name: "Offprint", logo: "atmo-offprint"),
        .init(name: "Pckt", logo: "atmo-pckt"),
        .init(name: "Plyr", logo: "atmo-plyr"),
        .init(name: "Popfeed", logo: "atmo-popfeed"),
        .init(name: "Blento", logo: "atmo-blento"),
        .init(name: "Semble", logo: "atmo-semble"),
        .init(name: "Skylight", logo: "atmo-skylight"),
        .init(name: "Blacksky", logo: "atmo-blacksky"),
        .init(name: "Spark", logo: "atmo-spark"),
        .init(name: "Stream Place", logo: "atmo-stream-place"),
    ]

    private let logoSize: CGFloat = 40
    private let itemSpacing: CGFloat = 12
    private let speed: CGFloat = 25

    private static let uiImages: [UIImage] = apps.compactMap { UIImage(named: $0.logo) }

    var body: some View {
        TimelineView(.animation) { (timeline: TimelineViewDefaultContext) in
            let now = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let images = Self.uiImages
                let totalWidth = CGFloat(images.count) * (logoSize + itemSpacing)
                let scrollOffset = (CGFloat(now) * speed).truncatingRemainder(dividingBy: totalWidth)

                for i in 0 ..< images.count * 2 {
                    let idx = i % images.count
                    let x = CGFloat(i) * (logoSize + itemSpacing) - scrollOffset
                    guard x + logoSize > 0, x < size.width else { continue }
                    let rect = CGRect(x: x, y: (size.height - logoSize) / 2, width: logoSize, height: logoSize)
                    ctx.drawLayer { layerCtx in
                        let clipPath = RoundedRectangle(cornerRadius: 10).path(in: rect)
                        layerCtx.clip(to: clipPath)
                        layerCtx.draw(Image(uiImage: images[idx]), in: rect)
                    }
                }
            }
            .frame(height: 44)
        }
        .clipped()
    }
}

#Preview {
    LoginView()
        .previewEnvironments()
}
