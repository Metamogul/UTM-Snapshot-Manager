import SwiftUI

/// One-time greeting on first launch. Explains the app in three sentences and
/// then stays out of the way forever.
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
                    // Says what is actually searched. The previous wording
                    // promised "no matter which folder" while the scan
                    // deliberately skips several of them — a safety-critical
                    // app that oversells itself is hard to trust elsewhere.
                    detail: "Your machines are found automatically in UTM's own folder, Documents, Downloads and the Desktop."
                )
                WelcomePoint(
                    symbol: "flag.fill",
                    title: "Pick a baseline, return to it in one step",
                    detail: "Mark the state you want back — a clean install, a prepared lab — and reset to it whenever you need, shutdown and restart included."
                )
                WelcomePoint(
                    symbol: "lock.shield",
                    title: "It refuses when it isn't sure",
                    detail: "Changes are only ever written to a machine UTM confirms is shut down. If that cannot be confirmed, nothing happens."
                )
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 8)

            Text("Snapshots need the machine shut down — not paused, not suspended. This app checks with UTM every few seconds and shows you the state at all times.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            Button("Get Started") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .primaryActionStyle()
                .controlSize(.large)
        }
        .padding(32)
        .frame(width: 500)
    }
}

private struct WelcomePoint: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 30)
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
