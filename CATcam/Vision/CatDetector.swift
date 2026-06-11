import Vision
import CoreVideo
import Combine
import Foundation

/// Vision の動物認識(VNRecognizeAnimalsRequest)でカメラ映像内の猫をリアルタイムに数える。
/// CameraManager から毎フレーム process(_:) が呼ばれる前提。CPU 節約のためフレームを間引く。
final class CatDetector: ObservableObject {
    /// 現在の猫の頭数(信頼度しきい値を超えた observation 数)。更新は必ずメインスレッド。
    @Published private(set) var catCount: Int = 0

    /// Vision 実行用の専用シリアルキュー(プレビュー経路をブロックしない)
    private let queue = DispatchQueue(label: "catcam.vision")

    /// フレーム間引き用カウンタ(frameStride フレームに 1 回だけ実行)
    private var frameCounter = 0
    private let frameStride = 5

    /// 同時実行を防ぐフラグ(1 フレーム処理中は次を捨てる)
    private var isProcessing = false

    /// ちらつき防止デバウンス: 直近で猫を検出した時刻。
    /// 0 匹になっても holdInterval の間は直前の頭数を保持してから 0 にする。
    private var lastPositiveDate: Date?
    private var lastPositiveCount = 0
    private let holdInterval: TimeInterval = 0.6

    /// 猫と判定する信頼度しきい値
    private let confidenceThreshold: Float = 0.6

    private let request = VNRecognizeAnimalsRequest()

    /// 外部(CameraManager 経由)から毎フレーム呼ばれる。間引きと実行制御はここで行う。
    func process(_ pixelBuffer: CVPixelBuffer) {
        frameCounter += 1
        guard frameCounter % frameStride == 0 else { return }
        guard !isProcessing else { return }
        isProcessing = true

        queue.async { [weak self] in
            guard let self else { return }
            defer { self.isProcessing = false }

            // orientation: 背面カメラの縦持ち映像(videoRotationAngle=90)に合わせて .right。
            // 実機で要確認(端末の向き・ミラーリングで調整が必要な場合がある)。
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: .right,
                                                options: [:])
            var detected = 0
            do {
                try handler.perform([self.request])
                if let results = self.request.results {
                    detected = results.filter { observation in
                        observation.labels.contains {
                            $0.identifier == VNAnimalIdentifier.cat.rawValue
                                && $0.confidence > self.confidenceThreshold
                        }
                    }.count
                }
            } catch {
                // 検出失敗時は安全に 0 扱い(デバウンスで直前値を保持)
                detected = 0
            }

            self.publish(detected)
        }
    }

    /// デバウンスを適用して catCount をメインスレッドで更新する。
    private func publish(_ detected: Int) {
        let now = Date()
        let value: Int
        if detected > 0 {
            // 検出あり: 値を更新して保持タイマーを更新
            lastPositiveDate = now
            lastPositiveCount = detected
            value = detected
        } else if let last = lastPositiveDate, now.timeIntervalSince(last) < holdInterval {
            // 検出なしだが保持期間内: 直前の頭数を維持(ちらつき防止)
            value = lastPositiveCount
        } else {
            // 保持期間を過ぎた: 0 に落とす
            lastPositiveCount = 0
            value = 0
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.catCount != value else { return }
            self.catCount = value
        }
    }
}
