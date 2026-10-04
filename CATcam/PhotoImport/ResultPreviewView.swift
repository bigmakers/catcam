import SwiftUI

/// 直近の加工結果を全画面で大きく確認するプレビュー。
/// 自動保存済みの画像を閲覧するためのビュー(保存操作は持たない)。
struct ResultPreviewView: View {
    let image: UIImage
    let onClose: () -> Void

    @State private var zoom: CGFloat = 1
    /// スワイプで閉じる用のドラッグ量(拡大していないときのみ有効)。
    @State private var drag: CGSize = .zero

    /// ドラッグ量に応じた背景の不透明度(引くほど暗幕が薄れて下の画面が見える演出)。
    private var backdropOpacity: Double {
        1 - min(Double(abs(drag.height)) / 600.0, 0.7)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity).ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(zoom)
                .offset(drag)
                .gesture(magnify)
                .simultaneousGesture(swipeToDismiss)
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) { zoom = zoom > 1 ? 1 : 2 }
                }

            VStack {
                topBar
                Spacer()
            }
        }
        .statusBarHidden()
    }

    // MARK: - スワイプで閉じる(フリックでカメラ画面へ戻る)

    private var swipeToDismiss: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard zoom <= 1.01 else { return }   // 拡大中はパン優先で無効
                drag = value.translation
            }
            .onEnded { value in
                guard zoom <= 1.01 else { return }
                // 移動量 or 勢い(予測終点)が閾値を超えたら閉じる
                let dist = abs(value.translation.height)
                let predicted = abs(value.predictedEndTranslation.height)
                if dist > 120 || predicted > 320 {
                    onClose()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = .zero }
                }
            }
    }

    // MARK: - 上部バー(閉じる/共有)

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }

            Spacer()

            ShareLink(item: Image(uiImage: image), preview: SharePreview("CATcam", image: Image(uiImage: image))) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var magnify: some Gesture {
        MagnificationGesture()
            .onChanged { zoom = max(1, min($0, 4)) }
            .onEnded { _ in
                if zoom < 1.05 { withAnimation { zoom = 1 } }
            }
    }
}
