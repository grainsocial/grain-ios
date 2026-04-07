import SwiftUI

struct ReportView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let client: XRPCClient
    let subjectUri: String
    let subjectCid: String

    @State private var labelDefs: [LabelDefinition] = []
    @State private var selectedLabel = ""
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var isSubmitted = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isSubmitted {
                    ContentUnavailableView(
                        "Report Submitted",
                        systemImage: "checkmark.circle",
                        description: Text("Thank you. Your report has been submitted for review.")
                    )
                } else {
                    Form {
                        Section("Category") {
                            if labelDefs.isEmpty {
                                ProgressView()
                            } else {
                                Picker("Category", selection: $selectedLabel) {
                                    ForEach(labelDefs) { def in
                                        Text(def.displayName).tag(def.identifier)
                                    }
                                }
                                .pickerStyle(.inline)
                                .labelsHidden()
                            }
                        }

                        Section("Details (optional)") {
                            TextField("Provide additional context...", text: $reason, axis: .vertical)
                                .lineLimit(3 ... 6)
                        }

                        if let error {
                            Section {
                                Text(error)
                                    .foregroundStyle(.red)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .navigationTitle(isSubmitted ? "" : "Report Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isSubmitted ? "Done" : "Cancel") {
                        dismiss()
                    }
                }
                if !isSubmitted {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") {
                            Task { await submit() }
                        }
                        .disabled(selectedLabel.isEmpty || isSubmitting)
                    }
                }
            }
            .task {
                await loadLabels()
            }
        }
    }

    private func loadLabels() async {
        do {
            labelDefs = try await client.describeLabels(auth: auth.authContext())
            if let first = labelDefs.first {
                selectedLabel = first.identifier
            }
        } catch {
            self.error = "Failed to load report categories."
        }
    }

    private func submit() async {
        guard !selectedLabel.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        error = nil
        do {
            try await client.createReport(
                subjectUri: subjectUri,
                subjectCid: subjectCid,
                label: selectedLabel,
                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reason.trimmingCharacters(in: .whitespacesAndNewlines),
                auth: auth.authContext()
            )
            isSubmitted = true
        } catch {
            self.error = "Failed to submit report. Please try again."
        }
        isSubmitting = false
    }
}

#Preview {
    ReportView(
        client: XRPCClient(baseURL: AuthManager.serverURL),
        subjectUri: "at://did:plc:preview/social.grain.gallery/r1",
        subjectCid: "cid"
    )
    .environment(AuthManager())
}
