//
//  GlassUI.swift
//  AVDB
//
//  iOS 26 Liquid Glass 组件库
//  原则：玻璃只用于「悬浮在内容之上的控件」，内容区保持正常底。
//  iOS 26+ 使用系统 .glassEffect() / GlassEffectContainer；
//  更低版本回退到干净的 .ultraThinMaterial，不做手绘高光。
//

import SwiftUI

// MARK: - 兼容层：iOS 26 系统玻璃 / 旧系统回退

/// 悬浮控件的液态玻璃修饰符。
/// iOS 26+：系统 .glassEffect()（真实折射、阴影、边缘）。
/// iOS 17–25：.ultraThinMaterial + 连续圆角，不加手绘高光。
struct LiquidGlassEffect: ViewModifier {
    var tint: Color? = nil

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(.regular.tint(tint), in: .capsule)
            } else {
                content.glassEffect(.regular, in: .capsule)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
    }
}

/// 矩形圆角的液态玻璃（卡片、搜索框、面板把手）。
struct LiquidGlassRectEffect: ViewModifier {
    var cornerRadius: CGFloat = 16
    var tint: Color? = nil

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if let tint {
                content.glassEffect(.regular.tint(tint), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
    }
}

/// 多个玻璃控件的融合容器（iOS 26 自动合并相邻玻璃）。
struct LiquidGlassContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - View 扩展

extension View {
    /// 悬浮胶囊控件玻璃（Tab 栏、播放按钮、小工具按钮）
    func liquidGlass(tint: Color? = nil) -> some View {
        modifier(LiquidGlassEffect(tint: tint))
    }

    /// 悬浮矩形控件玻璃（搜索框、筛选栏、面板）
    func liquidGlassRect(cornerRadius: CGFloat = 16, tint: Color? = nil) -> some View {
        modifier(LiquidGlassRectEffect(cornerRadius: cornerRadius, tint: tint))
    }
}

// MARK: - 全局氛围背景（极淡，内容下层）

/// App 最底层的氛围色。非常淡，只为玻璃提供可折射的内容，不抢视觉。
struct LiquidGlassBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)

            RadialGradient(
                colors: [Color.accentColor.opacity(0.06), .clear],
                center: UnitPoint(x: 0.2, y: 0.0),
                startRadius: 0,
                endRadius: 360
            )
            RadialGradient(
                colors: [Color.orange.opacity(0.04), .clear],
                center: UnitPoint(x: 0.85, y: 0.05),
                startRadius: 0,
                endRadius: 280
            )
        }
    }
}

// MARK: - 液态玻璃按钮

struct GlassButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    var style: ButtonStyle = .primary

    enum ButtonStyle {
        case primary, secondary, destructive

        var tint: Color? {
            switch self {
            case .primary: return .blue
            case .secondary: return nil
            case .destructive: return .red
            }
        }

        var foreground: Color {
            switch self {
            case .primary, .destructive: return .white
            case .secondary: return .primary
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .liquidGlass(tint: style.tint)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 筛选芯片（悬浮在内容之上）

struct LiquidFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? .white : .primary)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.accentColor)
                    } else {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    if !isSelected {
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 分段选择器

struct GlassSegmentedPicker<T: Hashable & CaseIterable>: View {
    @Binding var selection: T
    let title: (T) -> String
    @Namespace private var namespace

    var body: some View {
        if #available(iOS 26.0, *) {
            HStack(spacing: 0) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    segmentButton(option)
                }
            }
            .padding(3)
            .liquidGlass()
        } else {
            HStack(spacing: 0) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    segmentButton(option)
                }
            }
            .padding(3)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private func segmentButton(_ option: T) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selection = option
            }
        } label: {
            Text(title(option))
                .font(.system(size: 14, weight: selection == option ? .semibold : .regular))
                .foregroundStyle(selection == option ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if selection == option {
                        Capsule(style: .continuous)
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "segment", in: namespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 评分星星

struct RatingStars: View {
    let rating: Double
    var size: CGFloat = 14
    var color: Color = .yellow

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: starType(for: index))
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(color.gradient)
            }
        }
    }

    private func starType(for index: Int) -> String {
        let position = Double(index) + 0.5
        if rating >= Double(index + 1) {
            return "star.fill"
        } else if rating >= position {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
}

// MARK: - 空状态 / 加载 / 错误

struct GlassEmptyView: View {
    let icon: String
    let title: String
    let subtitle: String?
    var action: (() -> Void)?
    var actionTitle: String?

    init(icon: String, title: String, subtitle: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let action, let actionTitle {
                GlassButton(title: actionTitle, icon: nil, action: action)
                    .padding(.top, 8)
            }
        }
        .padding(40)
    }
}

struct GlassLoadingView: View {
    let message: String?

    init(_ message: String? = nil) {
        self.message = message
    }

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            if let message {
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 120, height: 120)
        .liquidGlassRect(cornerRadius: 20)
    }
}

struct ErrorBanner: View {
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.primary)

            Spacer()

            if let retry {
                Button("重试", action: retry)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
            }
        }
        .padding()
        .liquidGlassRect(cornerRadius: 12)
        .padding(.horizontal)
    }
}

// MARK: - 兼容旧调用

struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16
    var tint: Color? = nil

    init(cornerRadius: CGFloat = 20, padding: CGFloat = 16, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .liquidGlassRect(cornerRadius: cornerRadius, tint: tint)
    }
}

struct GlassTag: View {
    let text: String
    var color: Color = .blue
    var size: TagSize = .medium

    enum TagSize {
        case small, medium, large

        var font: Font {
            switch self {
            case .small: return .system(size: 11, weight: .medium)
            case .medium: return .system(size: 13, weight: .medium)
            case .large: return .system(size: 15, weight: .semibold)
            }
        }

        var padding: EdgeInsets {
            switch self {
            case .small: return EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            case .medium: return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            case .large: return EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            }
        }
    }

    var body: some View {
        Text(text)
            .font(size.font)
            .foregroundStyle(.white)
            .padding(size.padding)
            .background(color, in: Capsule())
    }
}

struct GlassNavigationBar: View {
    let title: String
    var leftButton: (() -> Void)?
    var rightButton: (() -> Void)?
    var rightIcon: String = "ellipsis.circle"

    var body: some View {
        HStack {
            if let leftAction = leftButton {
                Button(action: leftAction) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .liquidGlass()
                }
            }

            Spacer()

            Text(title)
                .font(.system(size: 18, weight: .bold))

            Spacer()

            if let rightAction = rightButton {
                Button(action: rightAction) {
                    Image(systemName: rightIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .liquidGlass()
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .liquidGlassRect(cornerRadius: cornerRadius)
    }

    func glassButton() -> some View {
        self
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .liquidGlass()
    }
}
