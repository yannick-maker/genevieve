import SwiftUI

/// Placeholder view to satisfy Xcode build input references.
struct MorningBriefingView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sunrise")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Morning Briefing")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
