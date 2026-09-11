import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                .padding(.top, 28)
            VStack(spacing: 4) {
                Text(AppInfo.name).font(.title.weight(.semibold))
                Text("Version \(AppInfo.version) (\(AppInfo.build))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("Close the lid. Your desktop stays where it was, softening into light as the glass folds over it. Open it, and everything comes back into focus.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
                .padding(.top, 4)
            HStack(spacing: 18) {
                Link("mac-duo.com", destination: AppInfo.website)
                Link("Source", destination: AppInfo.sourceCode)
                Link("Privacy", destination: AppInfo.privacy)
            }
            .font(.callout)
            .padding(.top, 6)
            Spacer()
            VStack(spacing: 2) {
                Text("Made by \(AppInfo.author). Inspired by iPhone Duo.")
                Text(AppInfo.copyright)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, minHeight: 440)
    }
}
