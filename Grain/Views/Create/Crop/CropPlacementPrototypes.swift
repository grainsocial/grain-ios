import SwiftUI

// MARK: - Root browser

struct CropPlacementPrototypes: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Chosen designs — high fidelity") {
                    NavigationLink("Story — tap photo + corner badge") { StoryFinal() }
                    NavigationLink("Gallery — bottomBar + context menu") { GalleryFinal() }
                    NavigationLink("Settings — inline menu picker") { SettingsFinal() }
                }

                Section("Story Create — crop entry point") {
                    NavigationLink("A. Form row (current)") { StoryPlacement_FormRow() }
                    NavigationLink("B. Tap photo (direct manipulation)") { StoryPlacement_TapPhoto() }
                    NavigationLink("C. Corner badge on photo") { StoryPlacement_CornerBadge() }
                    NavigationLink("D. Toolbar button") { StoryPlacement_Toolbar() }
                    NavigationLink("E. Context menu (long-press)") { StoryPlacement_ContextMenu() }
                }

                Section("Gallery Create — crop entry point") {
                    NavigationLink("A. Form row (current)") { GalleryPlacement_FormRow() }
                    NavigationLink("B. Toolbar button (when selected)") { GalleryPlacement_Toolbar() }
                    NavigationLink("C. Context menu on cell") { GalleryPlacement_ContextMenu() }
                    NavigationLink("D. Floating action bar") { GalleryPlacement_FloatingBar() }
                    NavigationLink("E. Inline icon under selected") { GalleryPlacement_InlineIconRow() }
                }

                Section("Settings — default crop ratio") {
                    NavigationLink("A. Inline menu picker") { SettingsPlacement_InlineMenu() }
                    NavigationLink("B. Inline nav-link picker") { SettingsPlacement_NavLinkPicker() }
                    NavigationLink("C. Folded into Defaults screen") { SettingsPlacement_FoldedDefaults() }
                    NavigationLink("D. Dedicated 'Cropping' screen") { SettingsPlacement_DedicatedCropping() }
                    NavigationLink("E. Feature-adjacent (in crop tool)") { SettingsPlacement_FeatureAdjacent() }
                    NavigationLink("Z. Photo Editor subscreen (current)") { SettingsPlacement_Current() }
                }
            }
            .navigationTitle("Crop Placements")
        }
    }
}

// MARK: - Shared mocks

private struct PhotoPlaceholder: View {
    var aspect: CGFloat = 4.0 / 3.0
    var body: some View {
        Rectangle()
            .fill(Color(.tertiarySystemFill))
            .aspectRatio(aspect, contentMode: .fit)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.tertiary)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct GalleryGridMock: View {
    let selectedIndex: Int?
    var body: some View {
        let cols = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]
        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(0 ..< 6, id: \.self) { i in
                Rectangle()
                    .fill(Color(.tertiarySystemFill))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.tertiary)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentColor, lineWidth: selectedIndex == i ? 3 : 0)
                    )
            }
        }
    }
}

private struct CommonStoryFormRows: View {
    var body: some View {
        Group {
            Label("Choose from Library", systemImage: "photo.on.rectangle")
            Label("Take Photo", systemImage: "camera")
        }
    }
}

// MARK: - Story prototypes

private struct StoryPlacement_FormRow: View {
    var body: some View {
        Form {
            Section("Photo") {
                PhotoPlaceholder()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                Label("Crop Photo", systemImage: "crop.rotate")
                CommonStoryFormRows()
            }
            Section("Location") { Text("Add location").foregroundStyle(.secondary) }
        }
        .navigationTitle("New Story")
    }
}

private struct StoryPlacement_TapPhoto: View {
    @State private var hint = true
    var body: some View {
        Form {
            Section("Photo") {
                PhotoPlaceholder()
                    .overlay(alignment: .bottom) {
                        if hint {
                            Text("Tap photo to crop")
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.thinMaterial, in: Capsule())
                                .padding(.bottom, 10)
                                .transition(.opacity)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .onTapGesture { withAnimation { hint.toggle() } }
                CommonStoryFormRows()
            }
            Section("Location") { Text("Add location").foregroundStyle(.secondary) }
        }
        .navigationTitle("New Story")
    }
}

private struct StoryPlacement_CornerBadge: View {
    var body: some View {
        Form {
            Section("Photo") {
                PhotoPlaceholder()
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "crop.rotate")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(10)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                CommonStoryFormRows()
            }
            Section("Location") { Text("Add location").foregroundStyle(.secondary) }
        }
        .navigationTitle("New Story")
    }
}

private struct StoryPlacement_Toolbar: View {
    var body: some View {
        Form {
            Section("Photo") {
                PhotoPlaceholder()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                CommonStoryFormRows()
            }
            Section("Location") { Text("Add location").foregroundStyle(.secondary) }
        }
        .navigationTitle("New Story")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {} label: { Image(systemName: "crop.rotate") }
            }
        }
    }
}

private struct StoryPlacement_ContextMenu: View {
    var body: some View {
        Form {
            Section("Photo") {
                PhotoPlaceholder()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .contextMenu {
                        Button {} label: { Label("Crop", systemImage: "crop.rotate") }
                        Button {} label: { Label("Replace", systemImage: "photo") }
                        Button(role: .destructive) {} label: { Label("Remove", systemImage: "trash") }
                    }
                Text("(long-press the photo)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CommonStoryFormRows()
            }
        }
        .navigationTitle("New Story")
    }
}

// MARK: - Gallery prototypes

private struct GalleryPlacement_FormRow: View {
    var body: some View {
        Form {
            Section {
                GalleryGridMock(selectedIndex: 1)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                Label("Crop Photo", systemImage: "crop.rotate")
            } header: { Picker("Mode", selection: .constant(0)) {
                Text("Edit").tag(0); Text("Reorder").tag(1); Text("Preview").tag(2)
            }.pickerStyle(.segmented) }
        }
        .navigationTitle("New Gallery")
    }
}

private struct GalleryPlacement_Toolbar: View {
    var body: some View {
        Form {
            Section {
                GalleryGridMock(selectedIndex: 1)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: { Picker("Mode", selection: .constant(0)) {
                Text("Edit").tag(0); Text("Reorder").tag(1); Text("Preview").tag(2)
            }.pickerStyle(.segmented) }
        }
        .navigationTitle("New Gallery")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {} label: { Image(systemName: "crop.rotate") }
            }
        }
    }
}

private struct GalleryPlacement_ContextMenu: View {
    var body: some View {
        Form {
            Section {
                GalleryGridMock(selectedIndex: 1)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                Text("(long-press a photo for Crop / Replace / Remove)")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Picker("Mode", selection: .constant(0)) {
                Text("Edit").tag(0); Text("Reorder").tag(1); Text("Preview").tag(2)
            }.pickerStyle(.segmented) }
        }
        .navigationTitle("New Gallery")
    }
}

private struct GalleryPlacement_FloatingBar: View {
    @State private var selectedIndex: Int? = 1
    var body: some View {
        ZStack(alignment: .bottom) {
            Form {
                Section {
                    GalleryGridMock(selectedIndex: selectedIndex)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    Button(selectedIndex == nil ? "Tap to select photo 2" : "Deselect") {
                        selectedIndex = selectedIndex == nil ? 1 : nil
                    }
                    .font(.footnote)
                } header: { Picker("Mode", selection: .constant(0)) {
                    Text("Edit").tag(0); Text("Reorder").tag(1); Text("Preview").tag(2)
                }.pickerStyle(.segmented) }
            }

            if selectedIndex != nil {
                HStack(spacing: 22) {
                    floatingItem("crop.rotate", "Crop")
                    floatingItem("photo", "Replace")
                    floatingItem("trash", "Remove")
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: selectedIndex)
        .navigationTitle("New Gallery")
    }

    private func floatingItem(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.title3)
            Text(label).font(.caption2)
        }
        .foregroundStyle(.primary)
    }
}

private struct GalleryPlacement_InlineIconRow: View {
    @State private var selectedIndex: Int? = 1
    var body: some View {
        Form {
            Section {
                GalleryGridMock(selectedIndex: selectedIndex)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                Button(selectedIndex == nil ? "Tap to select photo 2" : "Deselect") {
                    withAnimation(.smooth) {
                        selectedIndex = selectedIndex == nil ? 1 : nil
                    }
                }
                .font(.footnote)
                if selectedIndex != nil {
                    HStack {
                        Spacer()
                        iconButton("crop.rotate")
                        iconButton("arrow.counterclockwise")
                        iconButton("photo")
                        iconButton("trash")
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .transition(.opacity)
                }
            } header: { Picker("Mode", selection: .constant(0)) {
                Text("Edit").tag(0); Text("Reorder").tag(1); Text("Preview").tag(2)
            }.pickerStyle(.segmented) }
        }
        .navigationTitle("New Gallery")
    }

    private func iconButton(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title3)
            .frame(width: 44, height: 44)
            .foregroundStyle(.primary)
    }
}

// MARK: - Settings prototypes

private struct SettingsPlacement_InlineMenu: View {
    @State private var ratio: String = "Free"
    var body: some View {
        List {
            Section {
                NavigationLink("Appearance") { Text("…") }
                NavigationLink("Account") { Text("…") }
                NavigationLink("Notifications") { Text("…") }
                NavigationLink("Moderation") { Text("…") }
                NavigationLink("Feeds") { Text("…") }
                NavigationLink("Privacy") { Text("…") }
                Picker("Default Crop", selection: $ratio) {
                    ForEach(AspectRatioPreset.allPresets) { p in Text(p.label).tag(p.label) }
                }
                .pickerStyle(.menu)
            }
        }
        .navigationTitle("Settings")
    }
}

private struct SettingsPlacement_NavLinkPicker: View {
    @State private var ratio: String = "Free"
    var body: some View {
        List {
            Section {
                NavigationLink("Appearance") { Text("…") }
                NavigationLink("Account") { Text("…") }
                NavigationLink("Notifications") { Text("…") }
                NavigationLink("Moderation") { Text("…") }
                NavigationLink("Feeds") { Text("…") }
                NavigationLink("Privacy") { Text("…") }
                Picker("Default Crop", selection: $ratio) {
                    ForEach(AspectRatioPreset.allPresets) { p in Text(p.label).tag(p.label) }
                }
                .pickerStyle(.navigationLink)
            }
        }
        .navigationTitle("Settings")
    }
}

private struct SettingsPlacement_FoldedDefaults: View {
    @State private var ratio: String = "Free"
    @State private var includeLocation = true
    @State private var includeExif = true
    var body: some View {
        List {
            Section {
                NavigationLink("Appearance") { Text("…") }
                NavigationLink("Account") { Text("…") }
                NavigationLink("Notifications") { Text("…") }
                NavigationLink("Moderation") { Text("…") }
                NavigationLink("Feeds") { Text("…") }
                NavigationLink("Defaults") {
                    List {
                        Section("New uploads") {
                            Toggle("Include location", isOn: $includeLocation)
                            Toggle("Include camera data", isOn: $includeExif)
                        }
                        Section("Photo editing") {
                            Picker("Default crop", selection: $ratio) {
                                ForEach(AspectRatioPreset.allPresets) { p in Text(p.label).tag(p.label) }
                            }
                            .pickerStyle(.navigationLink)
                        }
                    }
                    .navigationTitle("Defaults")
                }
            }
        }
        .navigationTitle("Settings")
    }
}

private struct SettingsPlacement_DedicatedCropping: View {
    @State private var ratio: String = "Free"
    var body: some View {
        List {
            Section {
                NavigationLink("Appearance") { Text("…") }
                NavigationLink("Account") { Text("…") }
                NavigationLink("Privacy") { Text("…") }
                NavigationLink("Cropping") {
                    List {
                        Section {
                            Picker("Default ratio", selection: $ratio) {
                                ForEach(AspectRatioPreset.allPresets) { p in Text(p.label).tag(p.label) }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        } footer: {
                            Text("Applied when opening the crop tool on a new photo.")
                        }
                    }
                    .navigationTitle("Cropping")
                }
            }
        }
        .navigationTitle("Settings")
    }
}

private struct SettingsPlacement_FeatureAdjacent: View {
    @State private var defaultRatio: String = "Free"
    var body: some View {
        VStack(spacing: 0) {
            PhotoPlaceholder(aspect: 1)
                .padding()

            Spacer()

            HStack(spacing: 14) {
                ForEach(AspectRatioPreset.allPresets) { p in
                    Text(p.label)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(p.label == defaultRatio ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill),
                                    in: Capsule())
                        .overlay(alignment: .topTrailing) {
                            if p.label == defaultRatio {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tint)
                                    .offset(x: 4, y: -4)
                            }
                        }
                        .contextMenu {
                            Button {
                                defaultRatio = p.label
                            } label: {
                                Label("Set as default", systemImage: "pin")
                            }
                        }
                }
            }
            .padding(.bottom, 24)

            Text("Long-press a ratio → \"Set as default\"")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .navigationTitle("Crop")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsPlacement_Current: View {
    @State private var ratio: String = "Free"
    var body: some View {
        List {
            Section {
                NavigationLink("Appearance") { Text("…") }
                NavigationLink("Account") { Text("…") }
                NavigationLink("Privacy") { Text("…") }
                NavigationLink("Photo Editor") {
                    List {
                        Section {
                            ForEach(AspectRatioPreset.allPresets) { p in
                                HStack {
                                    Text(p.label)
                                    Spacer()
                                    if ratio == p.label {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { ratio = p.label }
                            }
                        } header: { Text("Default crop ratio") }
                    }
                    .navigationTitle("Photo Editor")
                }
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Final: Story / Gallery / Settings (real production views)

private struct StoryFinal: View {
    var body: some View {
        StoryCreateView(
            client: .preview,
            initialImage: PreviewData.photoItems.first?.originalImage
        )
    }
}

private struct GalleryFinal: View {
    var body: some View {
        CreateGalleryView(client: .preview, initialItems: PreviewData.photoItems)
    }
}

private struct SettingsFinal: View {
    var body: some View {
        SettingsView(client: .preview)
    }
}

// MARK: - Preview

#Preview {
    CropPlacementPrototypes().grainPreview()
}
