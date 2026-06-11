import Vision
import CoreVideo
import Combine
import Foundation

/// Vision の動物認識(VNRecognizeAnimalsRequest)でカメラ映像内の猫をリアルタイムに数える。
/// CameraManager から毎フレーム process(_:) が呼ばれる前提。CPU 節約のためフレームを間引く。
final class CatDetector: ObservableObject {
    /// 現在の猫の頭数(信頼度しきい値を超えた observation 数)。更新は必ずメインスレッド。
    @Published private(set) var catCount: Int = 0

    /// 猫がカメラの方を向いているか(オートシャッター用)。更新は必ずメインスレッド。
    /// ポーズ検出で目・鼻の配置を見て判定。失敗・未対応時は false。
    @Published private(set) var isCatFacing: Bool = false

    /// Vision 実行用の専用シリアルキュー(プレビュー経路をブロックしない)
    private let queue = DispatchQueue(label: "catcam.vision")

    /// フレーム間引き用カウンタ(frameStride フレームに 1 回だけ実行)
    private var frameCounter = 0
    private let frameStride = 5

    /// 向き判定の間引きカウンタ(ポーズ検出は重いので頭数より粗く間引く)
    private var faceFrameCounter = 0
    private let faceFrameStride = 10

    /// 同時実行を防ぐフラグ(1 フレーム処理中は次を捨てる)
    private var isProcessing = false

    /// ちらつき防止デバウンス: 直近で猫を検出した時刻。
    /// 0 匹になっても holdInterval の間は直前の頭数を保持してから 0 にする。
    private var lastPositiveDate: Date?
    private var lastPositiveCount = 0
    private let holdInterval: TimeInterval = 0.6

    /// 向き判定のちらつき防止: facing=true になったら 0.4 秒は維持する。
    private var lastFacingDate: Date?
    private let facingHoldInterval: TimeInterval = 0.4

    /// 猫と判定する信頼度しきい値
    private let confidenceThreshold: Float = 0.6

    /// 目・鼻ジョイントを採用する信頼度しきい値
    private let jointConfidenceThreshold: Float = 0.3

    private let request = VNRecognizeAnimalsRequest()
    private let poseRequest = VNDetectAnimalBodyPoseRequest()

    /// 外部(CameraManager 経由)から毎フレーム呼ばれる。間引きと実行制御はここで行う。
    func process(_ pixelBuffer: CVPixelBuffer) {
        frameCounter += 1
        faceFrameCounter += 1
        let runFace = faceFrameCounter % faceFrameStride == 0
        guard frameCounter % frameStride == 0 || runFace else { return }
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

            // 頭数とポーズ(向き判定)を同じ handler でまとめて perform する。
            // ポーズ検出は重いため runFace のフレームでのみ要求に含める。
            var requests: [VNRequest] = [self.request]
            if runFace { requests.append(self.poseRequest) }

            var detected = 0
            var facing: Bool?  // runFace のときのみ判定結果をセット(nil は据え置き)
            do {
                try handler.perform(requests)
                if let results = self.request.results {
                    detected = results.filter { observation in
                        observation.labels.contains {
                            $0.identifier == VNAnimalIdentifier.cat.rawValue
                                && $0.confidence > self.confidenceThreshold
                        }
                    }.count
                }
                if runFace {
                    facing = self.evaluateFacing(poseResults: self.poseRequest.results,
                                                 animalResults: self.request.results)
                }
            } catch {
                // 検出失敗時は安全に 0 / 非向き扱い(デバウンスで直前値を保持)
                detected = 0
                if runFace { facing = false }
            }

            self.publish(detected)
            if let facing { self.publishFacing(facing) }
        }
    }

    /// ポーズ observation から「猫が正面を向いている」かを判定する。
    /// 左目・右目・鼻が confidence > しきい値 で取得でき、両目が概ね水平・
    /// 鼻が両目の間に位置するなら true。ジョイントが取れない場合は
    /// 猫 bbox が画面の一定割合以上の大きさかを向き相当のフォールバックにする。
    private func evaluateFacing(poseResults: [VNAnimalBodyPoseObservation]?,
                                animalResults: [VNRecognizedObjectObservation]?) -> Bool {
        // --- 1. 目・鼻ジョイントによる正面判定 ---
        if let poses = poseResults, !poses.isEmpty {
            // 最も信頼度の高いポーズ observation を採用
            let best = poses.max(by: { $0.confidence < $1.confidence })
            if let best,
               let points = try? best.recognizedPoints(.all) {
                let leftEye = points[.leftEye]
                let rightEye = points[.rightEye]
                let nose = points[.nose]
                if let le = leftEye, let re = rightEye, let no = nose,
                   le.confidence > jointConfidenceThreshold,
                   re.confidence > jointConfidenceThreshold,
                   no.confidence > jointConfidenceThreshold {
                    // Vision の正規化座標(原点左下、0...1)。両目の間隔を基準にする。
                    let eyeDX = abs(le.location.x - re.location.x)
                    let eyeDY = abs(le.location.y - re.location.y)
                    let eyeSpan = max(eyeDX, 0.0001)
                    // 両目が概ね水平: 縦ずれが横間隔より十分小さい
                    let eyesLevel = eyeDY < eyeSpan * 0.6
                    // 鼻が両目の中点付近(横方向)にある: 対称性チェック
                    let eyeMidX = (le.location.x + re.location.x) / 2
                    let noseCentered = abs(no.location.x - eyeMidX) < eyeSpan * 0.6
                    return eyesLevel && noseCentered
                }
            }
        }

        // --- 2. フォールバック: ジョイントが無い/取れない場合 ---
        // 猫 bbox が画面の一定割合以上(幅か高さ >= 0.25)なら「近くで安定検出」=
        // 向いている代わりの指標として扱う。目・鼻 API が使えない端末向けの保険。
        if let animals = animalResults {
            for obs in animals where obs.labels.contains(where: {
                $0.identifier == VNAnimalIdentifier.cat.rawValue
                    && $0.confidence > confidenceThreshold
            }) {
                if obs.boundingBox.width >= 0.25 || obs.boundingBox.height >= 0.25 {
                    return true
                }
            }
        }
        return false
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

    /// 向き判定を 0.4 秒のホールド付きでメインスレッド更新する(ちらつき防止)。
    /// true になったら facingHoldInterval の間は true を維持してから false に落とす。
    private func publishFacing(_ facing: Bool) {
        let now = Date()
        let value: Bool
        if facing {
            lastFacingDate = now
            value = true
        } else if let last = lastFacingDate, now.timeIntervalSince(last) < facingHoldInterval {
            // 直近で向いていた: 保持期間内は true を維持
            value = true
        } else {
            value = false
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCatFacing != value else { return }
            self.isCatFacing = value
        }
    }
}
