//
//  GlassUI.swift
//  AVDB
//
//  iOS 26 液态玻璃风格 UI 组件库
//

import SwiftUI

// MARK: - 毛玻璃卡片容器
struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16
    
    init(cornerRadius: CGFloat = 20, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }
}

// MARK: - 悬浮按钮
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
                return LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .secondary:
                return LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .destructive:
                return LinearGradient(colors: [.red, .red.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(style.gradient, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 标签气泡
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
            .background(color.gradient, in: Capsule())
            .shadow(color: color.opacity(0.3), radius: 4, y: 2)
    }
}

// MARK: - 分段选择器（毛玻璃风格）
struct GlassSegmentedPicker<T: Hashable & CaseIterable>: View {
    @Binding var selection: T
    let title: (T) -> String
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(T.allCases), id: \.self) { option in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                                Capsule()
                                    .fill(.blue.gradient)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
    }
    
    @Namespace private var namespace
}

// MARK: - 评分星星
struct RatingStars: View {
    let rating: Double
    var size: CGFloat = 14
    var color: Color = .yellow
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
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

// MARK: - 毛玻璃导航栏
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
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - 增强空状态视图
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
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if let action = action, let actionTitle = actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.blue.gradient, in: Capsule())
                }
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
            
            if let message = message {
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 120, height: 120)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
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
            
            if let retry = retry {
                Button("重试", action: retry)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.horizontal)
    }
}

// MARK: - View 扩展
extension View {
    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }
    
    func glassButton() -> some View {
        self
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}
