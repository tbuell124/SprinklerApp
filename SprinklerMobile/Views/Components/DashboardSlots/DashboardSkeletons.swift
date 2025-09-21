import SwiftUI

struct LEDStatusSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SkeletonLine(height: 20)
                    .frame(maxWidth: 120)
                
                Spacer()
                
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 24)
                    .shimmering()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(0..<8, id: \.self) { _ in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 24, height: 24)
                            .shimmering()
                        
                        SkeletonLine(height: 10)
                            .frame(width: 20)
                    }
                }
            }
        }
    }
}

struct ScheduleSummarySkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonLine(height: 20)
                .frame(maxWidth: 100)
            
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(height: 60)
                    .shimmering()
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(height: 40)
                    .shimmering()
            }
        }
    }
}

struct PinControlsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonLine(height: 20)
                .frame(maxWidth: 120)
            
            VStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(height: 50)
                        .shimmering()
                }
            }
        }
    }
}

struct RainStatusSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonLine(height: 20)
                .frame(maxWidth: 100)
            
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(height: 80)
                .shimmering()
        }
    }
}
