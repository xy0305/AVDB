//
//  GlassUI.swift
//  AVDB
//
//  iOS 26 系统 Liquid Glass。
//  编译需 Xcode 26 SDK；运行时 iOS 26 走 .glassEffect / .buttonStyle(.glass)，
//  iOS 17–25 回退 .ultraThinMaterial。
//

import SwiftUI

// MARK: - 系统玻璃修饰符

/// 胶囊形系统 Liquid Glass（悬浮控件）。
struct LiquidGlassEffect: ViewModifier {
    var tint: Color? = nil
    var interactive: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(
                    interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                    in: Capsule()
                )
            } else {
                content.glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: Capsule()
                )
            }
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                }
        }
    }
}

/// 圆角矩形系统 Liquid Glass。
struct LiquidGlassRectEffect: ViewModifier {
    var cornerRadius: CGFloat = 16
    var tint: Color? = nil
    var interactive: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(
                    interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                    in: shape
                )
            } else {
                content.glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: shape
                )
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                }
        }
    }
}

/// 圆形系统 Liquid Glass。
struct LiquidGlassCircleEffect: ViewModifier {
    var tint: Color? = nil
    var interactive: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(
                    interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                    in: Circle()
                )
            } else {
                content.glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: Circle()
                )
            }
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                }
        }
    }
}

/// 多个玻璃控件融合（iOS 26 GlassEffectContainer）。
struct LiquidGlassContainer<Content: View>: View {
    var spacing: CGFloat = 8
    let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        // iPad 上 GlassEffectContainer 会把整块区域（含子控件空隙）做成命中层，
        // 返回/搜索/快捷入口/Tab 都会点不进去。融合效果只在 iPhone 上保留。
        if #available(iOS 26.0, *), !AdaptiveLayout.isPad {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - View 扩展

extension View {
    /// 悬浮胶囊控件：系统 Liquid Glass
    func liquidGlass(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlassEffect(tint: tint, interactive: interactive))
    }

    /// 悬浮圆角矩形：系统 Liquid Glass
    func liquidGlassRect(cornerRadius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlassRectEffect(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    /// 悬浮圆形：系统 Liquid Glass
    func liquidGlassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlassCircleEffect(tint: tint, interactive: interactive))
    }

    /// 系统玻璃按钮样式（iOS 26 `.glass` / `.glassProminent`）
    @ViewBuilder
    func avdbGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    /// 系统导航栏 / Tab 走液态玻璃。iOS 26 用系统默认；更早系统回退材质。
    /// 全屏不加 glassEffect，避免再吃点击。
    func liquidGlassChrome() -> some View {
        modifier(LiquidGlassChromeModifier())
    }

    /// 列表透出氛围背景。
    func liquidGlassList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { LiquidGlassBackground() }
    }

    /// 页面氛围背景（不抢点击）。
    func liquidGlassPage() -> some View {
        self.background { LiquidGlassBackground() }
    }

    /// 详情点番号/导演/片商后的二级列表。
    /// iPad 的系统 Tab 在顶部，会和导航栏叠成一大块玻璃，把第一排海报盖住。
    func nestedMovieListChrome() -> some View {
        modifier(NestedMovieListChrome())
    }
}

private struct NestedMovieListChrome: ViewModifier {
    func body(content: Content) -> some View {
        if AdaptiveLayout.isPad {
            content
                .toolbar(.hidden, for: .tabBar)
                .safeAreaPadding(.top, 8)
        } else {
            content
        }
    }
}

/// iOS 26：系统 Tab / Navigation 自动 Liquid Glass。
/// 更早系统：导航栏和 Tab 用薄材质。
private struct LiquidGlassChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        }
    }
}

// MARK: - 全局氛围背景（内容区，不是控件玻璃）

struct LiquidGlassBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.10),
                    Color.cyan.opacity(0.05),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - 液态玻璃按钮

struct GlassButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    var style: ButtonKind = .primary

    enum ButtonKind {
        case primary, secondary, destructive
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
        }
        .avdbGlassButton(prominent: style == .primary || style == .destructive)
        .tint(style == .destructive ? .red : .accentColor)
    }
}

// MARK: - 筛选芯片

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
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Capsule(style: .continuous).fill(Color.accentColor)
            }
        }
        .liquidGlass(interactive: false)
    }
}

// MARK: - 分段选择器

struct GlassSegmentedPicker<T: Hashable & CaseIterable>: View {
    @Binding var selection: T
    let title: (T) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(T.allCases), id: \.self) { option in
                segmentButton(option)
            }
        }
        .padding(3)
        .liquidGlass(interactive: false)
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
        .liquidGlassRect(cornerRadius: 20, interactive: false)
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
        .liquidGlassRect(cornerRadius: 12, interactive: false)
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
            .liquidGlassRect(cornerRadius: cornerRadius, tint: tint, interactive: false)
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
                .buttonStyle(.plain)
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
                .buttonStyle(.plain)
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
            .liquidGlassRect(cornerRadius: cornerRadius, interactive: false)
    }

    func glassButton() -> some View {
        self
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .liquidGlass()
    }
}
