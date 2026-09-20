//
//  FloatingLaneGuidanceView.swift
//  GorillaTranslate
//
//  懸浮車道導航框 - 浮喺主頁上方顯示車道信息
//

import SwiftUI

struct FloatingLaneGuidanceView: View {
    @ObservedObject var naviManager: AmapNaviManager

    // 懸浮框位置
    @State private var offset: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        if naviManager.showLaneGuidance, let laneImage = naviManager.laneImage {
            VStack(spacing: 0) {
                // 車道圖片（帶文字描述）
                Image(uiImage: laneImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                // 道路名稱 + 剩餘距離
                HStack {
                    if !naviManager.currentRoadName.isEmpty {
                        Text(naviManager.currentRoadName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    if naviManager.remainingDistance > 0 {
                        Text(formatDistance(naviManager.remainingDistance))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.cyan)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.cyan.opacity(0.4), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .offset(y: offset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        // 只允許垂直拖動
                        offset = CGSize(width: 0, height: value.translation.height)
                    }
                    .onEnded { _ in
                        isDragging = false
                        // 鬆手後彈回原位
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            offset = .zero
                        }
                    }
            )
            .scaleEffect(isDragging ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isDragging)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
            .zIndex(100) // 確保浮喺最上層
        }
    }

    // MARK: - 格式化距離
    private func formatDistance(_ meters: Int) -> String {
        if meters >= 1000 {
            return String(format: "%.1f 公里", Double(meters) / 1000.0)
        } else {
            return "\(meters) 米"
        }
    }
}

// MARK: - 預覽
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        Text("FloatingLaneGuidanceView Preview")
            .foregroundColor(.white)
    }
}
