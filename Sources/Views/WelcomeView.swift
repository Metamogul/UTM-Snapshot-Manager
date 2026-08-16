import SwiftUI

/// One-time greeting on first launch. Explains the app in three sentences
/// and then stays out of the way forever.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .padding(.bottom, 14)

            Text("Welcome to UTM Snapshot Manager")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Restore points for your UTM machines.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 18) {
                WelcomePoint(
                    symbol: "magnifyingglass",
                    title: "Nothing to set up",
                    detail: "Your virtual machines are found automatically, no matter which folder they live in."
                )
                WelcomePoint(
                    symbol: "camera.aperture",
                    title: "Save before you break things",
                    detail: "One click freezes the current state of the disk before you try something risky."
                )
                WelcomePoint(
                    symbol: "clock.arrow.circlepath",
                    title: "Go back any time",
                    detail: "If things go wrong, restoring the saved state takes seconds."
                )
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 8)

            Text("Snapshots only work while a machine is shut down. This app keeps an eye on that and tells you when it isn't.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            Button("Get Started") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
        .frame(width: 480)
    }
}

private struct WelcomePoint: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
