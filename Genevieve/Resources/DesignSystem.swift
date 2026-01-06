import SwiftUI

// MARK: - Design System

/// Centralized design system for the Genevieve application.
enum DesignSystem {
    
    // MARK: - Colors
    
    struct Colors {
        static let background = Color(nsColor: .windowBackgroundColor)
        static let surface = Material.regular
        static let surfaceHighlight = Material.thick
        
        static let accent = Color.accentColor
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)
        
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue
        
        // Semantic Gradients
        static let primaryGradient = LinearGradient(
            colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Typography
    
    struct Fonts {
        static let display = Font.system(size: 32, weight: .bold, design: .rounded)
        static let title = Font.system(.title2, design: .default).weight(.semibold)
        static let headline = Font.system(.headline, design: .default)
        static let body = Font.system(.body, design: .default)
        static let caption = Font.system(.caption, design: .default)
        
        // Specialized
        static let monospaceNumeric = Font.system(.body, design: .monospaced)
    }
    
    // MARK: - Dimensions
    
    struct Metrics {
        static let cornerRadius: CGFloat = 12
        static let smallCornerRadius: CGFloat = 8
        static let padding: CGFloat = 16
        static let cardPadding: CGFloat = 20
    }
}

// MARK: - View Modifiers

struct GenevieveCardStyle: ViewModifier {
    var interactable: Bool = false
    @State private var isHovering = false
    
    func body(content: Content) -> some View {
        content
            .padding(DesignSystem.Metrics.cardPadding)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius)
                    .stroke(Color.white.opacity(isHovering && interactable ? 0.2 : 0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isHovering && interactable ? 0.1 : 0.05), radius: 5, x: 0, y: 2)
            .scaleEffect(isHovering && interactable ? 1.01 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isHovering)
            .onHover { hover in
                if interactable {
                    isHovering = hover
                }
            }
    }
}

extension View {
    func genevieveCardStyle(interactable: Bool = false) -> some View {
        modifier(GenevieveCardStyle(interactable: interactable))
    }
    
    func genevieveTitle() -> some View {
        self.font(DesignSystem.Fonts.title)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
    }
    
    func genevieveSubtitle() -> some View {
        self.font(DesignSystem.Fonts.headline)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
    }
}
