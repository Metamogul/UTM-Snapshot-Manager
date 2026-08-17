import SwiftUI

struct NewSnapshotSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// The machine this dialog names, fixed at the moment it opened.
    let machineID: VirtualMachine.ID

    @State private var name = ""
    @State private var makeBaseline = false
    @FocusState private var isFieldFocused: Bool

    private var vm: VirtualMachine? { model.machines.first { $0.id == machineID } }

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
                    Text("Freezes “\(vm?.name ?? "")” exactly as it is now. \(diskPhrase) You can come back to this point at any time.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 18)

            Text("Name")
                .font(.callout.weight(.medium))
                .padding(.bottom, 4)

            TextField("e.g. Clean install, before sample run", text: $name)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($isFieldFocused)
                .onSubmit { submit() }

            Text(validation ?? String(localized: "A name you will still recognise in three weeks beats a timestamp."))
                .font(.caption)
                .foregroundStyle(validation == nil ? Color.secondary : Color.red)
                .padding(.top, 6)
                .frame(minHeight: 26, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $makeBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Make this the baseline")
                    Text("The point “Reset to Baseline” returns to. Useful for the state you want to come back to over and over.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)

            Divider().padding(.vertical, 14)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .primaryActionStyle()
                    .disabled(validation != nil)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onAppear {
            name = model.suggestedSnapshotName()
            isFieldFocused = true
        }
    }

    private var diskPhrase: String {
        let count = vm?.disks.count ?? 1
        return count > 1
            ? String(localized: "All \(count) disks are captured together as one restore point.")
            : ""
    }

    private var validation: String? {
        model.validationMessage(for: name)
    }

    private func submit() {
        guard validation == nil, let vm else { return }
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = makeBaseline
        // Dismiss first, then act: mutating model state while the sheet is
        // still on screen is what produced AttributeGraph cycle warnings.
        dismiss()
        Task {
            await model.createSnapshot(named: finalName, on: machineID)
            if pin, let saved = model.machines.first(where: { $0.id == machineID })?
                .snapshots.first(where: { $0.name == finalName }) {
                model.setBaseline(saved, for: vm)
            }
        }
    }
}
