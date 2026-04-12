import SwiftUI

struct NotificationSettingsView: View {
    @Environment(AuthManager.self) private var auth
    let client: XRPCClient
    @State private var prefs = NotificationPrefs.default
    @State private var hasLoaded = false

    private let categories: [(key: String, label: String, desc: String, icon: String)] = [
        ("favorites", "Favorites", "When someone favorites your gallery or story", "heart"),
        ("follows", "New followers", "When someone follows you", "person.badge.plus"),
        ("comments", "Comments", "When someone comments on your gallery or story", "bubble.left"),
        ("mentions", "Mentions", "When someone mentions you", "at"),
    ]

    var body: some View {
        List {
            ForEach(categories, id: \.key) { cat in
                Section {
                    let pref = binding(for: cat.key)

                    Toggle("Push notifications", isOn: Binding(
                        get: { pref.wrappedValue.push },
                        set: { pref.wrappedValue.push = $0; save() }
                    ))

                    Toggle("In-app notifications", isOn: Binding(
                        get: { pref.wrappedValue.inApp },
                        set: { pref.wrappedValue.inApp = $0; save() }
                    ))

                    Picker("From", selection: Binding(
                        get: { pref.wrappedValue.from },
                        set: { pref.wrappedValue.from = $0; save() }
                    )) {
                        Text("Everyone").tag("all")
                        Text("People I follow").tag("follows")
                    }
                } header: {
                    Label(cat.label, systemImage: cat.icon)
                } footer: {
                    Text(cat.desc)
                }
            }
        }
        .navigationTitle("Notifications")
        .task {
            guard !hasLoaded else { return }
            if let authContext = await auth.authContext(),
               let response = try? await client.getPreferences(auth: authContext).preferences.notificationPrefs
            {
                prefs = response
            }
            hasLoaded = true
        }
    }

    private func binding(for key: String) -> Binding<NotifPref> {
        switch key {
        case "favorites": $prefs.favorites.defaulted()
        case "follows": $prefs.follows.defaulted()
        case "comments": $prefs.comments.defaulted()
        case "mentions": $prefs.mentions.defaulted()
        default: .constant(.default)
        }
    }

    private func save() {
        guard hasLoaded else { return }
        let current = prefs
        Task {
            guard let authContext = await auth.authContext() else { return }
            try? await client.putNotificationPrefs(current, auth: authContext)
        }
    }
}

private extension Binding where Value == NotifPref? {
    func defaulted() -> Binding<NotifPref> {
        Binding<NotifPref>(
            get: { self.wrappedValue ?? .default },
            set: { self.wrappedValue = $0 }
        )
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView(client: .preview)
            .previewEnvironments()
    }
}
