//
//  GlassUI.swift
//  AVDB
//
//  iOS 26 系统 Liquid Glass + 液态玻璃动效层。
//  编译需 Xcode 26 SDK；运行时 iOS 26 走 .glassEffect / .buttonStyle(.glass)，
//  iOS 17–25 回退 .ultraThinMaterial。
//  在材质之外补：漂浮氛围光斑、按压回弹、错落入场、高光描边、微交互。
//

import SwiftUI
import UIKit

// MARK: - 真玻璃体（多层：模糊底 + 染色透光 + 厚度边 + 内高光 + 双层投影）

/// 玻璃体底层：材质模糊 + 染色透光 + 斜向柔光。避免纯色贴皮。
struct GlassBody<S: InsettableShape>: View {
    let shape: S
    var tint: Color? = nil
    /// 染色强度：0 清玻璃，0.35+ 彩色玻璃
    var tintStrength: Double = 0.18
    /// 是否盖一层冷白柔光（默认有，像玻璃表层）
    var sheen: Bool = true

    var body: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)

            // 染色透光：不是实色块，是薄色釉
            if let tint {
                shape.fill(tint.opacity(tintStrength))
                shape.fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(tintStrength * 1.35),
                            tint.opacity(tintStrength * 0.45),
                            tint.opacity(tintStrength * 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }

            if sheen {
                // 表层斜向反光：左上亮、右下略暗，形成弧面
                shape.fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(tint == nil ? 0.34 : 0.22),
                            .white.opacity(0.08),
                            .clear,
                            .black.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        }
    }
}

/// 玻璃厚度边 + 内阴影：让边缘像切过光的玻璃棱，而不是描边贴纸。
struct GlassRim<S: InsettableShape>: View {
    let shape: S
    var lineWidth: CGFloat = 1

    var body: some View {
        ZStack {
            // 外棱高光（左上白）
            shape.strokeBorder(
                AngularGradient(
                    colors: [
                        .white.opacity(0.72),
                        .white.opacity(0.18),
                        .black.opacity(0.08),
                        .white.opacity(0.28),
                        .white.opacity(0.72)
                    ],
                    center: .topLeading
                ),
                lineWidth: lineWidth
            )
            // 内侧厚度阴影（右下略压）
            shape
                .inset(by: lineWidth * 0.85)
                .strokeBorder(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: lineWidth * 0.7
                )
            // 顶部内高光条
            shape
                .inset(by: lineWidth * 1.6)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: lineWidth * 0.55
                )
        }
        .allowsHitTesting(false)
    }
}

/// 完整玻璃层（背景体 + 厚度边 + 落地影）。给内容套上后不再是「贴图」。
struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    var tintStrength: Double = 0.18
    var elevation: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background {
                GlassBody(shape: shape, tint: tint, tintStrength: tintStrength)
            }
            .overlay {
                GlassRim(shape: shape)
            }
            // 贴地短影 + 环境大影：有厚度、离开纸面
            .shadow(color: .black.opacity(0.07 * elevation), radius: 2 * elevation, y: 1 * elevation)
            .shadow(color: .black.opacity(0.10 * elevation), radius: 14 * elevation, y: 7 * elevation)
    }
}

extension View {
    /// 给任意内容套上真玻璃体。
    func glassSurface<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        tintStrength: Double = 0.18,
        elevation: CGFloat = 1
    ) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, tintStrength: tintStrength, elevation: elevation))
    }
}

/// 图片上的玻璃角标/芯片：染色玻璃，不是实色贴纸。
struct GlassChip: View {
    let text: String
    var tint: Color = .blue
    var font: Font = .caption2.weight(.semibold)
    var foreground: Color = .white
    var compact: Bool = true
    /// 色釉浓度：深色字用 0.12–0.2，白字用 0.55–0.7
    var tintStrength: Double = 0.62

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foreground)
            .shadow(color: .black.opacity(tintStrength >= 0.5 ? 0.28 : 0.08), radius: 1, y: 0.5)
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.vertical, compact ? 3.5 : 5)
            .background {
                Capsule(style: .continuous).fill(.ultraThinMaterial)
                Capsule(style: .continuous).fill(tint.opacity(tintStrength))
                Capsule(style: .continuous).fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(min(tintStrength + 0.12, 0.85)),
                            tint.opacity(tintStrength * 0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                Capsule(style: .continuous).fill(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .clear, .black.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                Capsule(style: .continuous).strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.08), .black.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
            }
            .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
            // 装饰角标不吃点击，避免挡住海报 NavigationLink
            .allowsHitTesting(false)
    }
}

// MARK: - 系统玻璃修饰符

/// 胶囊形系统 Liquid Glass（悬浮控件）。
struct LiquidGlassEffect: ViewModifier {
    var tint: Color? = nil
    var interactive: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            Group {
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
            }
            .overlay {
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .clear, .black.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.55
                )
                .allowsHitTesting(false)
            }
        } else {
            content.glassSurface(in: Capsule(), tint: tint, tintStrength: tint == nil ? 0 : 0.16)
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
            Group {
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
            }
            .overlay {
                GlassRim(shape: shape)
            }
        } else {
            content.glassSurface(in: shape, tint: tint, tintStrength: tint == nil ? 0 : 0.16)
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
            Group {
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
            }
            .overlay {
                GlassRim(shape: Circle())
            }
        } else {
            content.glassSurface(in: Circle(), tint: tint, tintStrength: tint == nil ? 0 : 0.16)
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

// MARK: - View 扩展（玻璃）

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

/// 页面底层：冷色渐变 + 缓慢漂浮的柔光斑，形成液态玻璃的「有厚度」感。
struct LiquidGlassBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            Color(.systemBackground)

            LinearGradient(
                colors: [
                    Color.blue.opacity(0.14),
                    Color.cyan.opacity(0.08),
                    Color.purple.opacity(0.05),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 漂浮光斑：慢速位移 + 缩放，模拟液态折射
            blob(
                color: Color.blue.opacity(0.22),
                size: AdaptiveLayout.isPad ? 280 : 200,
                x: -0.18, y: -0.22,
                phase: drift ? 1 : 0
            )
            blob(
                color: Color.cyan.opacity(0.16),
                size: AdaptiveLayout.isPad ? 240 : 170,
                x: 0.72, y: -0.05,
                phase: drift ? 1 : 0
            )
            blob(
                color: Color.purple.opacity(0.12),
                size: AdaptiveLayout.isPad ? 260 : 190,
                x: 0.55, y: 0.68,
                phase: drift ? 1 : 0
            )

            LinearGradient(
                colors: [.white.opacity(0.18), .clear, .black.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 10)
                .repeatForever(autoreverses: true)
            ) {
                drift.toggle()
            }
        }
    }

    private func blob(color: Color, size: CGFloat, x: CGFloat, y: CGFloat, phase: CGFloat) -> some View {
        GeometryReader { geo in
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .blur(radius: 40)
                .scaleEffect(phase == 1 ? 1.12 : 0.92)
                .offset(
                    x: geo.size.width * x + (phase == 1 ? 18 : -12),
                    y: geo.size.height * y + (phase == 1 ? 22 : -10)
                )
        }
    }
}

// MARK: - 动效 / 微交互

enum GlassMotion {
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.72)
    static let soft = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let enter = Animation.spring(response: 0.48, dampingFraction: 0.84)
    static let select = Animation.spring(response: 0.3, dampingFraction: 0.78)
}

/// 按压缩放 + 轻微变暗，让玻璃控件有「可捏」手感。
struct PressableGlassStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(GlassMotion.press, value: configuration.isPressed)
    }
}

extension View {
    func pressableGlass(scale: CGFloat = 0.96) -> some View {
        buttonStyle(PressableGlassStyle(scale: scale))
    }

    /// 卡片按压反馈：只做视觉缩放，不附加手势。
    /// 重要：绝不能在 NavigationLink 标签上加 onLongPressGesture，
    /// 否则会吃掉点击，封面无法进详情。
    func glassPressFeedback() -> some View {
        self
    }

    /// 错落入场：轻微上浮 + 缩放淡入。
    func staggerAppear(index: Int = 0) -> some View {
        modifier(StaggerAppearModifier(index: index))
    }

    /// 玻璃厚度棱 + 内高光（替换旧的单层描边）。
    func glassSpecular(cornerRadius: CGFloat = 14) -> some View {
        overlay {
            GlassRim(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// 图片内容框：轻玻璃棱 + 内暗角。装饰层全部不吃点击。
    func glassMediaFrame(cornerRadius: CGFloat = 12) -> some View {
        self
            .overlay {
                LinearGradient(
                    colors: [
                        .white.opacity(0.14),
                        .clear,
                        .black.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            }
            .overlay {
                GlassRim(
                    shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                    lineWidth: 0.9
                )
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

private struct StaggerAppearModifier: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .scaleEffect(shown ? 1 : 0.97)
            .onAppear {
                // 滚动时必须很快：短延迟 + 短时长，避免网格逐张慢慢弹出
                let delay = Double(min(index, 5)) * 0.015
                withAnimation(.easeOut(duration: 0.18).delay(delay)) {
                    shown = true
                }
            }
    }
}

/// 柔光呼吸环（头像 / 播放钮）。
struct SoftPulseRing: View {
    var color: Color = .blue
    @State private var pulse = false

    var body: some View {
        Circle()
            .strokeBorder(color.opacity(0.45), lineWidth: 1.5)
            .scaleEffect(pulse ? 1.12 : 0.96)
            .opacity(pulse ? 0.2 : 0.55)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .allowsHitTesting(false)
    }
}

/// 骨架屏微光扫过。
struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            LinearGradient(
                colors: [
                    Color(.systemGray5),
                    Color(.systemGray4),
                    Color(.systemGray5)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.45), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: w * 0.55)
                .offset(x: phase * w * 1.4)
            }
        }
        .clipped()
        .onAppear {
            withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}

/// 轻触反馈（按钮态切换时）。
enum GlassHaptic {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        Button(action: {
            GlassHaptic.tap()
            action()
        }) {
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
        .pressableGlass()
    }
}

/// 详情页操作胶囊：选中态是染色玻璃，不是实色贴片。
struct GlassActionPill: View {
    let title: String
    let icon: String
    var isSelected: Bool = false
    var tint: Color = .blue
    let action: () -> Void

    var body: some View {
        Button {
            GlassHaptic.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolEffect(.bounce, value: isSelected)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? tint : Color.primary)
            .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Capsule())
        }
        .pressableGlass(scale: 0.94)
        .liquidGlass(tint: isSelected ? tint.opacity(0.55) : nil, interactive: false)
    }
}

// MARK: - 筛选芯片

struct LiquidFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            GlassHaptic.tap()
            action()
        } label: {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .shadow(color: isSelected ? .black.opacity(0.18) : .clear, radius: 1, y: 0.5)
        }
        .pressableGlass(scale: 0.94)
        .liquidGlass(tint: isSelected ? Color.accentColor.opacity(0.7) : nil, interactive: false)
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
            GlassHaptic.tap()
            withAnimation(GlassMotion.select) {
                selection = option
            }
        } label: {
            Text(title(option))
                .font(.system(size: 14, weight: selection == option ? .semibold : .regular))
                .foregroundStyle(selection == option ? Color.white : Color.primary)
                .shadow(color: selection == option ? .black.opacity(0.16) : .clear, radius: 1, y: 0.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if selection == option {
                        ZStack {
                            Capsule(style: .continuous).fill(.ultraThinMaterial)
                            Capsule(style: .continuous).fill(Color.accentColor.opacity(0.72))
                            Capsule(style: .continuous).fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.28), .clear, .black.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                        .matchedGeometryEffect(id: "segment", in: namespace)
                        .overlay {
                            Capsule(style: .continuous).strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.5), .clear, .black.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.6
                            )
                        }
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 区块标题（玻璃徽章 + 点缀）

struct GlassSectionHeader: View {
    let title: String
    var icon: String? = nil
    var badge: String? = nil
    var trailingTitle: String? = "全部"
    var action: (() -> Void)? = nil

    init(
        title: String,
        icon: String? = nil,
        badge: String? = nil,
        trailingTitle: String? = "全部",
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self.trailingTitle = trailingTitle
        self.action = action
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(Color.accentColor.opacity(0.16))
                        Circle().fill(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .overlay {
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                    }
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
            Text(title)
                .font(.system(size: 17, weight: .bold))
            if let badge {
                GlassChip(
                    text: badge,
                    tint: Color.accentColor,
                    font: .system(size: 11, weight: .semibold),
                    foreground: Color.accentColor,
                    compact: true,
                    tintStrength: 0.14
                )
            }
            Spacer()
            if let trailingTitle {
                Button {
                    GlassHaptic.tap()
                    action?()
                } label: {
                    HStack(spacing: 2) {
                        Text(trailingTitle)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassSurface(in: Capsule(), tintStrength: 0, elevation: 0.5)
                }
                .pressableGlass(scale: 0.94)
            }
        }
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
                .overlay(alignment: .center) {
                    SoftPulseRing(color: .blue.opacity(0.5))
                        .frame(width: 88, height: 88)
                }

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
        .staggerAppear(index: 0)
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
        GlassChip(
            text: text,
            tint: color,
            font: size.font,
            foreground: .white,
            compact: size == .small
        )
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
                Button {
                    GlassHaptic.tap()
                    leftAction()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .liquidGlass()
                }
                .pressableGlass(scale: 0.9)
            }

            Spacer()

            Text(title)
                .font(.system(size: 18, weight: .bold))

            Spacer()

            if let rightAction = rightButton {
                Button {
                    GlassHaptic.tap()
                    rightAction()
                } label: {
                    Image(systemName: rightIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .liquidGlass()
                }
                .pressableGlass(scale: 0.9)
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
