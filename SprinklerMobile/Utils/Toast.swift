import SwiftUI

struct ToastState: Identifiable, Equatable {
    enum Style {
        case success
        case error
        case info

        var background: Color {
            switch self {
            case .success: return Color.green.opacity(0.85)
            case .error: return Color.red.opacity(0.85)
            case .info: return Color.blue.opacity(0.85)
            }
        }
    }

    let id = UUID()
    let message: String
    let style: Style
}

struct ToastView: View {
    let state: ToastState

    var body: some View {
        Text(state.message)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial.opacity(0.3))
            .background(state.style.background)
            .clipShape(Capsule())
            .shadow(radius: 3)
            .padding(.bottom, 24)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var toast: ToastState?

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let toast {
                ToastView(state: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: toast)
            }
        }
    }
}

extension View {
    func toast(state: Binding<ToastState?>) -> some View {
        modifier(ToastModifier(toast: state))
    }
}
