//
//  GlassUI.swift
//  AVDB
//
//  iOS 26 液态玻璃风格 UI 组件库
//  核心特征：镜面高光描边 + 顶部内发光 + 多层柔和投影 + 流体圆角
//

import SwiftUI

// MARK: - 液态玻璃修饰符

/// 液态玻璃材质修饰符：毛玻璃底 + 镜面边缘高光 + 顶部内发光 + 多层阴影
struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var material: Material = .ultraThinMaterial
    var tint: Color? = nil
    var edgeOpacity: Double = 0.55
    var glowOpacity: Double = 0.18
    var shadowRadius: CGFloat = 16
    var shadowY: CGFloat = 8
    var hasBorder: Bool = true

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .overlay {
                        // 顶部内发光：模拟光线从上方进入玻璃
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(glowOpacity),
                                        .white.opacity(glowOpacity * 0.3),
                                        .clear,
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tint.opacity(0.08))
                        }
                    }
                    .overlay {
                        // 镜面边缘高光：左上亮、右下暗，模拟光线折射
                        if hasBorder {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(edgeOpacity),
                                            .white.opacity(edgeOpacity * 0.25),
                                            .white.opacity(edgeOpacity * 0.15),
                                            .white.opacity(edgeOpacity * 0.4),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        }
                    }
                    .shadow(color: .black.opacity(0.08), radius: shadowRadius * 0.4, y: shadowY * 0.4)
                    .shadow(color: .black.opacity(0.06), radius: shadowRadius, y: shadowY)
            }
    }
}

/// 胶囊液态玻璃修饰符（Tab Bar / 按钮）
struct LiquidCapsuleModifier: ViewModifier {
    var material: Material = .ultraThinMaterial
    var tint: Color? = nil
    var edgeOpacity: Double = 0.5
    var glowOpacity: Double = 0.22
    var shadowRadius: CGFloat = 18
    var shadowY: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background {
                Capsule(style: .continuous)
                    .fill(material)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(glowOpacity),
                                        .white.opacity(glowOpacity * 0.25),
                                        .clear,
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                    .overlay {
                        if let tint {
                            Capsule(style: .continuous)
                                .fill(tint.opacity(0.1))
                        }
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(edgeOpacity),
                                        .white.opacity(edgeOpacity * 0.2),
                                        .white.opacity(edgeOpacity * 0.12),
                                        .white.opacity(edgeOpacity * 0.38),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    }
                    .shadow(color: .black.opacity(0.1), radius: shadowRadius * 0.5, y: shadowY * 0.5)
                    .shadow(color: .black.opacity(0.08), radius: shadowRadius, y: shadowY)
            }
    }
}

// MARK: - View 扩展

extension View {
    /// 液态玻璃卡片
    func liquidGlass(
        cornerRadius: CGFloat = 20,
        material: Material = .ultraThinMaterial,
        tint: Color? = nil,
        edgeOpacity: Double = 0.55,
        glowOpacity: Double = 0.18,
        shadowRadius: CGFloat = 16,
        shadowY: CGFloat = 8
    ) -> some View {
        modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            material: material,
            tint: tint,
            edgeOpacity: edgeOpacity,
            glowOpacity: glowOpacity,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        ))
    }

    /// 液态玻璃胶囊
    func liquidCapsule(
        material: Material = .ultraThinMaterial,
        tint: Color? = nil,
        edgeOpacity: Double = 0.5,
        glowOpacity: Double = 0.22,
        shadowRadius: CGFloat = 18,
        shadowY: CGFloat = 8
    ) -> some View {
        modifier(LiquidCapsuleModifier(
            material: material,
            tint: tint,
            edgeOpacity: edgeOpacity,
            glowOpacity: glowOpacity,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        ))
    }

    /// 浅玻璃卡片（无阴影，用于内嵌区域）
    func liquidGlassFlat(
        cornerRadius: CGFloat = 16,
        material: Material = .thinMaterial,
        tint: Color? = nil
    ) -> some View {
        modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            material: material,
            tint: tint,
            edgeOpacity: 0.35,
            glowOpacity: 0.12,
            shadowRadius: 6,
            shadowY: 2
        ))
    }

    /// 镜面高光描边叠加（用于图片等已有背景的元素）
    func glassEdge(
        cornerRadius: CGFloat = 12,
        opacity: Double = 0.4
    ) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(opacity),
                            .white.opacity(opacity * 0.2),
                            .white.opacity(opacity * 0.1),
                            .white.opacity(opacity * 0.35),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
    }

    /// 顶部内发光叠加
    func glassInnerGlow(
        cornerRadius: CGFloat = 12,
        opacity: Double = 0.15
    ) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(opacity),
                            .white.opacity(opacity * 0.3),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 液态玻璃卡片容器

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
            .liquidGlass(cornerRadius: cornerRadius, tint: tint)
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

        var gradient: LinearGradient {
            switch self {
            case .primary:
                return LinearGradient(colors: [.blue, .blue.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .secondary:
                return LinearGradient(
                    colors: [.white.opacity(0.25), .white.opacity(0.1)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            case .destructive:
                return LinearGradient(colors: [.red, .red.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }

        var foreground: Color {
            switch self {
            case .primary, .destructive: return .white
            case .secondary: return .primary
            }
        }

        var edgeOpacity: Double {
            switch self {
            case .primary: return 0.45
            case .secondary: return 0.55
            case .destructive: return 0.4
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
            .background {
                if style == .secondary {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(style.gradient)
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(style.edgeOpacity),
                                            .white.opacity(style.edgeOpacity * 0.2),
                                            .white.opacity(style.edgeOpacity * 0.35),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        }
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                } else {
                    Capsule(style: .continuous)
                        .fill(style.gradient)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.25), .clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(style.edgeOpacity),
                                            .white.opacity(style.edgeOpacity * 0.15),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        }
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 液态玻璃标签气泡

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
            .background {
                Capsule(style: .continuous)
                    .fill(color.gradient)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 0.6)
                    }
                    .shadow(color: color.opacity(0.35), radius: 5, y: 2)
            }
    }
}

// MARK: - 液态玻璃分段选择器

struct GlassSegmentedPicker<T: Hashable & CaseIterable>: View {
    @Binding var selection: T
    let title: (T) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(T.allCases), id: \.self) { option in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .font(.system(size: 14, weight: selection == option ? .semibold : .regular))
                        .foregroundStyle(selection == option ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if selection == option {
                                Capsule(style: .continuous)
                                    .fill(.blue.gradient)
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.3), .clear],
                                                    startPoint: .top,
                                                    endPoint: .center
                                                )
                                            )
                                    }
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .liquidCapsule(glowOpacity: 0.16, shadowRadius: 10, shadowY: 4)
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

// MARK: - 液态玻璃导航栏

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
                        .liquidCapsule(glowOpacity: 0.14, shadowRadius: 8, shadowY: 3)
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
                        .liquidCapsule(glowOpacity: 0.14, shadowRadius: 8, shadowY: 3)
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

// MARK: - 空状态

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

// MARK: - 加载指示器

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
        .liquidGlass(cornerRadius: 22, glowOpacity: 0.2, shadowRadius: 14, shadowY: 6)
    }
}

// MARK: - 错误提示

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
        .liquidGlass(cornerRadius: 14, glowOpacity: 0.14, shadowRadius: 10, shadowY: 4)
        .padding(.horizontal)
    }
}

// MARK: - 兼容旧调用点

extension View {
    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .liquidGlass(cornerRadius: cornerRadius)
    }

    func glassButton() -> some View {
        self
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .liquidCapsule(shadowRadius: 10, shadowY: 4)
    }
}
