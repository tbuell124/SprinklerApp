import SwiftUI

struct ShimmerViewModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    let gradient = LinearGradient(colors: [
                        Color(.systemGray5),
                        Color(.systemGray3),
                        Color(.systemGray5)
                    ], startPoint: .top, endPoint: .bottom)

                    Rectangle()
                        .fill(gradient)
                        .rotationEffect(.degrees(20))
                        .offset(x: phase * geometry.size.width * 2)
                        .frame(width: geometry.size.width * 1.5)
                }
                .mask(content)
            }
            .onAppear {
                phase = -1
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerViewModifier())
    }
}

struct SkeletonLine: View {
    var height: CGFloat = 12
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .shimmering()
    }
}

struct ToggleSkeleton: View {
    var body: some View {
        Capsule()
            .fill(Color(.systemGray5))
            .frame(width: 50, height: 30)
            .shimmering()
    }
}

struct PinRowSkeleton: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                SkeletonLine(height: 16)
                SkeletonLine(height: 12)
                    .frame(maxWidth: 120)
            }
            Spacer()
            ToggleSkeleton()
        }
        .padding(.vertical, 4)
    }
}

struct ScheduleRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonLine(height: 16)
            HStack(spacing: 12) {
                SkeletonLine(height: 12)
                    .frame(maxWidth: 60)
                SkeletonLine(height: 12)
                    .frame(maxWidth: 80)
                SkeletonLine(height: 12)
            }
        }
        .padding(.vertical, 6)
    }
}

struct RainCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SkeletonLine(height: 16)
            SkeletonLine(height: 14)
                .frame(maxWidth: 100)
            SkeletonLine(height: 14)
                .frame(maxWidth: 140)
            SkeletonLine(height: 44, cornerRadius: 12)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

struct ScheduleGroupSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonLine(height: 16)
                .frame(maxWidth: 120)
            SkeletonLine(height: 12)
                .frame(maxWidth: 180)
        }
        .padding(.vertical, 4)
    }
}
