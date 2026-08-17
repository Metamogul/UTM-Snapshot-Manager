import SwiftUI

/// Shown while `qemu-img` is missing.
///
/// UTM ships its own copy of qemu-img, but as a dynamic library it loads
/// in-process rather than an executable — it cannot be run from here, and
/// reaching into another app's signed frameworks would be a fragile foundation
/// for the one tool this app depends on. So QEMU is a real prerequisite, and
/// the job of this screen is to make installing it a two-click affair.
struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var didCopy = false

    private let command = "brew install qemu"

    private var hasHomebrew: Bool {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shippingbox")
                .font(.system(size: 52, weight: .thin))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("One Piece Is Missing")
                    .font(.title2.weight(.semibold))
                Text("This app manages restore points with “qemu-img”. It ships with QEMU, which isn't on this Mac yet. UTM does include its own copy, but in a form that only UTM itself can run.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if hasHomebrew {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Text(command)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                            didCopy = true
                        } label: {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy command")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassCard(cornerRadius: 10)

                    Text("Homebrew is installed, so this is a single command. It takes a few minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Homebrew isn't installed either — it's the usual way to get QEMU on macOS.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Link("Install Homebrew first", destination: URL(string: "https://brew.sh")!)
                        .font(.callout)
                }
            }

            HStack(spacing: 12) {
                Button("Open Terminal") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                }
                Button("Check Again") {
                    Task {
                        await model.checkPrerequisites()
                        await model.refresh()
                    }
                }
                .primaryActionStyle()
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
