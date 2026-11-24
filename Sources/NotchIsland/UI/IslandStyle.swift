import AppKit
import SwiftUI

/// 刘海岛统一的视觉样式：品牌色、表面透明度与动画曲线。
///
/// 岛始终是黑底，所以不跟随系统强调色：用户把强调色设成橙色或绿色时，
/// 界面里不会混着两套主色。
enum IslandStyle {
    // MARK: 品牌色

    static let brandBlue = Color(red: 0.36, green: 0.60, blue: 1.0)
    static let brandPurple = Color(red: 0.66, green: 0.44, blue: 0.98)
    static let brandColors = [brandBlue, brandPurple]

    static func brandGradient(
        startPoint: UnitPoint = .leading,
        endPoint: UnitPoint = .trailing
    ) -> LinearGradient {
        LinearGradient(colors: brandColors, startPoint: startPoint, endPoint: endPoint)
    }

    // MARK: 表面（白色叠加在黑底上的不透明度）

    static let surface: Double = 0.08
    static let surfaceHover: Double = 0.16
    static let surfacePressed: Double = 0.24

    // MARK: 液态玻璃

    /// 液态玻璃从 macOS 26 开始提供；更早的系统退回原来的纯黑底。
    static var supportsGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// 卡片、标签这类小块的底色。透明玻璃背后可能是亮色网页，白色叠加会看不见，
    /// 所以玻璃下改用半透明深色，让每块内容自带对比度。
    /// 卡片底板里缩略图那一格的底色：底板已经是深色，这里只要略微提亮。
    static func wellFill(hovering: Bool = false) -> Color {
        supportsGlass
            ? .white.opacity(hovering ? 0.14 : 0.07)
            : .white.opacity(hovering ? surfaceHover : 0.09)
    }

    static func chipFill(hovering: Bool = false) -> Color {
        supportsGlass
            ? .black.opacity(hovering ? 0.24 : 0.10)
            : .white.opacity(hovering ? surfaceHover : surface)
    }

    // MARK: 动画

    /// 系统设置里打开「减弱动态效果」时，用短淡入淡出代替弹簧和位移。
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 岛在收起 / 悬停 / 展开之间切换的动画。
    static var modeTransition: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .interactiveSpring(response: 0.28, dampingFraction: 0.9, blendDuration: 0.08)
    }

    /// 卡片增删、筛选切换等内容变化的动画。
    static var contentSpring: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.78)
    }

    static let hoverFade = Animation.easeOut(duration: 0.12)
}

/// 岛上按钮的按压反馈：轻微缩小，松手回弹。
struct IslandPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !IslandStyle.reduceMotion ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 展开时让各个区块依次出现：稍微从上方落下并淡入。
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        let reduce = IslandStyle.reduceMotion
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduce ? 0 : -6)
            .scaleEffect(appeared || reduce ? 1 : 0.98, anchor: .top)
            .onAppear {
                let animation: Animation = reduce
                    ? .easeOut(duration: 0.15)
                    : .spring(response: 0.34, dampingFraction: 0.86).delay(0.03 + Double(index) * 0.045)
                withAnimation(animation) { appeared = true }
            }
    }
}

extension View {
    func staggeredAppear(_ index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

/// 用淡底色标记卡片范围，悬停时加深。
/// 没有玻璃的系统上岛本身就是黑底，不需要底板。
struct CardTile: ViewModifier {
    var hovering = false

    func body(content: Content) -> some View {
        if IslandStyle.supportsGlass {
            content
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(hovering ? 0.15 : 0.035))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(hovering ? 0.16 : 0.07), lineWidth: 0.5)
                        }
                }
        } else {
            content
        }
    }
}

extension View {
    func cardTile(hovering: Bool = false) -> some View {
        modifier(CardTile(hovering: hovering))
    }

    /// 透明玻璃上的文字加一圈很淡的阴影，背后是亮色内容时也能读出来。
    func glassLegible() -> some View {
        shadow(color: .black.opacity(IslandStyle.supportsGlass ? 0.85 : 0), radius: 1.2, y: 0.7)
    }
}
