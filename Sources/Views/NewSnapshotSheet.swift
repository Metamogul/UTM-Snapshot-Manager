import SwiftUI

struct NewSnapshotSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 30, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Take Snapshot")
                        .font(.title3.weight(.semibold))
                    Text("The current state of “\(model.selected?.name ?? "")” will be preserved. You can come back to this point at any time.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 18)

            Text("Name")
                .font(.callout.weight(.medium))
                .padding(.bottom, 4)

            TextField("e.g. Before the update", text: $name)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($isFieldFocused)
                .onSubmit { submit() }

            Text(validation ?? String(localized: "A descriptive name makes it easy to recognise later."))
                .font(.caption)
                .foregroundStyle(validation == nil ? Color.secondary : Color.red)
                .padding(.top, 6)
                .frame(minHeight: 26, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 14)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(validation != nil)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear {
            name = model.suggestedSnapshotName()
            isFieldFocused = true
        }
    }

    private var validation: String? {
        model.validationMessage(for: name)
    }

    private func submit() {
        guard validation == nil else { return }
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Dismiss first, then act: mutating model state while the sheet is
        // still on screen is what produced AttributeGraph cycle warnings.
        dismiss()
        Task { await model.createSnapshot(named: finalName) }
    }
}
