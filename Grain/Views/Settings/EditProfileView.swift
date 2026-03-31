import PhotosUI
import SwiftUI
import NukeUI

struct EditProfileView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let client: XRPCClient
    var onSaved: (() -> Void)?

    @State private var displayName = ""
    @State private var bio = ""
    @State private var existingAvatarURL: String?
    @State private var existingAvatarBlob: [String: AnyCodable]?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var newAvatarData: Data?
    @State private var newAvatarImage: UIImage?
    @State private var removeAvatar = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let maxDisplayName = 64
    private let maxBio = 256

    var body: some View {
        Form {
            // Avatar section
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            if let newAvatarImage {
                                Image(uiImage: newAvatarImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else if !removeAvatar, let existingAvatarURL {
                                AvatarView(url: existingAvatarURL, size: 100)
                            } else {
                                ZStack {
                                    Circle().fill(.quaternary)
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(width: 100, height: 100)
                            }

                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color("AccentColor"), in: Circle())
                            }
                        }

                        if newAvatarImage != nil || (!removeAvatar && existingAvatarURL != nil) {
                            Button("Remove Photo", role: .destructive) {
                                newAvatarData = nil
                                newAvatarImage = nil
                                selectedPhoto = nil
                                removeAvatar = true
                            }
                            .font(.caption)
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            // Fields
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Display Name", text: $displayName)
                        .textInputAutocapitalization(.words)
                    Text("\(displayName.count)/\(maxDisplayName)")
                        .font(.caption2)
                        .foregroundStyle(displayName.count > maxDisplayName ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Bio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $bio)
                        .frame(minHeight: 100)
                    Text("\(bio.count)/\(maxBio)")
                        .font(.caption2)
                        .foregroundStyle(bio.count > maxBio ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(isSaving || displayName.count > maxDisplayName || bio.count > maxBio)
            }
        }
        .onChange(of: selectedPhoto) {
            Task { await loadSelectedPhoto() }
        }
        .task {
            await loadProfile()
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private func loadProfile() async {
        guard let did = auth.userDID, let authContext = auth.authContext() else { return }
        do {
            let profile = try await client.getActorProfile(actor: did, auth: authContext)
            displayName = profile.displayName ?? ""
            bio = profile.description ?? ""
            existingAvatarURL = profile.avatar

            // Fetch raw record to get avatar blob ref for preservation on save
            let record = try await client.getRecord(uri: "at://\(did)/social.grain.actor.profile/self", auth: authContext)
            if let value = record.record?.dictValue?["value"],
               let avatar = value.dictValue?["avatar"] {
                existingAvatarBlob = avatar.dictValue
            }
        } catch {
            errorMessage = "Failed to load profile"
        }
        isLoading = false
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        do {
            if let data = try await selectedPhoto.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let resized = resizeImage(image, maxSize: 1000, maxBytes: 900_000)
                newAvatarImage = UIImage(data: resized)
                newAvatarData = resized
                removeAvatar = false
            }
        } catch {
            errorMessage = "Failed to load selected photo"
        }
    }

    private func save() async {
        guard let authContext = auth.authContext() else { return }
        isSaving = true
        errorMessage = nil

        do {
            var avatarValue: AnyCodable?

            if let newAvatarData {
                // Upload new avatar
                let response = try await client.uploadBlob(data: newAvatarData, mimeType: "image/jpeg", auth: authContext)
                avatarValue = blobRefToAnyCodable(response.blob)
            } else if removeAvatar {
                avatarValue = nil
            } else if let existingAvatarBlob {
                // Preserve existing avatar
                avatarValue = AnyCodable(existingAvatarBlob)
            }

            var record: [String: AnyCodable] = [
                "createdAt": AnyCodable(ISO8601DateFormatter().string(from: Date()))
            ]

            let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                record["displayName"] = AnyCodable(trimmedName)
            }

            let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBio.isEmpty {
                record["description"] = AnyCodable(trimmedBio)
            }

            if let avatarValue {
                record["avatar"] = avatarValue
            }

            _ = try await client.putRecord(
                collection: "social.grain.actor.profile",
                rkey: "self",
                record: AnyCodable(record),
                auth: authContext
            )

            onSaved?()
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
        isSaving = false
    }

    private func blobRefToAnyCodable(_ blob: BlobRef) -> AnyCodable {
        var dict: [String: AnyCodable] = [
            "$type": AnyCodable("blob")
        ]
        if let mimeType = blob.mimeType {
            dict["mimeType"] = AnyCodable(mimeType)
        }
        if let size = blob.size {
            dict["size"] = AnyCodable(size)
        }
        if let ref = blob.ref {
            dict["ref"] = AnyCodable(["$link": AnyCodable(ref.link)])
        }
        return AnyCodable(dict)
    }

    private func resizeImage(_ image: UIImage, maxSize: CGFloat, maxBytes: Int) -> Data {
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        // Binary search for quality that fits under maxBytes
        var low: CGFloat = 0.1
        var high: CGFloat = 0.95
        var result = rendered.jpegData(compressionQuality: high) ?? Data()

        if result.count <= maxBytes { return result }

        for _ in 0..<8 {
            let mid = (low + high) / 2
            let data = rendered.jpegData(compressionQuality: mid) ?? Data()
            if data.count <= maxBytes {
                result = data
                low = mid
            } else {
                high = mid
            }
        }
        return result
    }
}
