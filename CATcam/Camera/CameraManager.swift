import AVFoundation
import CoreImage
import UIKit

final class CameraManager: NSObject, ObservableObject {
    enum Status {
        case idle
        case running
        case denied
        case failed
    }

    @Published var status: Status = .idle

    /// レンズ種別(背面 / フロント)
    enum Lens: String, CaseIterable { case back, front }

    /// 背面の焦点距離(35mm換算)。基準24mm相当からのズーム倍率で表す。
    /// 28/52mm は主カメラのクロップ(52mm は 48MP の 2x クロップ域で劣化小)。
    /// 120mm は wide+tele の仮想デバイス経由なので、望遠搭載機(17 Pro=100mm,
    /// 16 Pro=120mm, 15/14/13 Pro=77mm)では実レンズに自動で切り替わる。
    enum Focal: Int, CaseIterable, Identifiable {
        case f28 = 28, f52 = 52, f120 = 120
        var id: Int { rawValue }
        var zoom: CGFloat { CGFloat(rawValue) / 24.0 }
        var label: String { "\(rawValue)mm" }
    }

    @Published private(set) var currentLens: Lens = .back
    @Published private(set) var currentFocal: Focal = .f28
    /// sessionQueue 側の焦点距離(configureSession が currentFocal(main)を読むと競合するため別持ち)
    private var sessionFocal: Focal = .f28

    let session = AVCaptureSession()

    /// プレビュー用フレーム。ビデオキューから呼ばれる。
    var onPreviewFrame: ((CIImage) -> Void)?

    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "mapcam.session")
    private let videoQueue = DispatchQueue(label: "mapcam.video")
    private var photoHandler: ((AVCapturePhoto) -> Void)?
    /// 現在の映像入力。レンズ切替時に差し替えるため保持する。
    private var videoDeviceInput: AVCaptureDeviceInput?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureAndRun()
                } else {
                    DispatchQueue.main.async { self.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capturePhoto(_ handler: @escaping (AVCapturePhoto) -> Void) {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.photoHandler = handler
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureAndRun() {
        sessionQueue.async {
            guard self.session.inputs.isEmpty else {
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { self.status = .running }
                return
            }
            do {
                try self.configureSession()
            } catch {
                DispatchQueue.main.async { self.status = .failed }
                return
            }
            self.session.startRunning()
            DispatchQueue.main.async { self.status = .running }
        }
    }

    private enum CameraError: Error {
        case noDevice
        case cannotAddIO
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        // 初期レンズ(currentLens)のデバイスを取得して入力に追加
        guard let (device, zoom, mirrored) = deviceConfig(for: currentLens) else {
            throw CameraError.noDevice
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddIO }
        session.addInput(input)
        videoDeviceInput = input

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddIO }
        session.addOutput(videoOutput)

        guard session.canAddOutput(photoOutput) else { throw CameraError.cannotAddIO }
        session.addOutput(photoOutput)

        applyConnectionSettings(mirrored: mirrored)
        applyZoom(zoom, to: device)
    }

    // MARK: - レンズ切替

    /// 背面の焦点距離を切り替える。フロント使用中は値だけ保持し、背面に戻ったとき反映する。
    func select(focal: Focal) {
        sessionQueue.async {
            self.sessionFocal = focal
            DispatchQueue.main.async { self.currentFocal = focal }
            guard let device = self.videoDeviceInput?.device,
                  device.position == .back else { return }
            self.applyZoom(focal.zoom, to: device)
        }
    }

    /// レンズを切り替える。session 未構成時は currentLens を保持するだけで、
    /// configureSession 時に反映される。
    func select(_ lens: Lens) {
        sessionQueue.async {
            // session 未構成なら状態だけ更新(configureSession が適用する)
            guard !self.session.inputs.isEmpty, let oldInput = self.videoDeviceInput else {
                DispatchQueue.main.async { self.currentLens = lens }
                return
            }
            guard let (device, zoom, mirrored) = self.deviceConfig(for: lens) else {
                return  // デバイス取得失敗時は現状維持
            }
            let newInput: AVCaptureDeviceInput
            do {
                newInput = try AVCaptureDeviceInput(device: device)
            } catch {
                return
            }

            self.session.beginConfiguration()
            self.session.removeInput(oldInput)
            guard self.session.canAddInput(newInput) else {
                // 失敗時は元の入力を戻す
                self.session.addInput(oldInput)
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(newInput)
            self.videoDeviceInput = newInput

            // 入力差し替え後に回転・ミラーリング・ズームを再設定
            self.applyConnectionSettings(mirrored: mirrored)
            self.applyZoom(zoom, to: device)
            self.session.commitConfiguration()

            DispatchQueue.main.async { self.currentLens = lens }
        }
    }

    /// レンズに対応するデバイス・ズーム倍率・ミラーリング要否を返す。
    private func deviceConfig(for lens: Lens) -> (AVCaptureDevice, CGFloat, Bool)? {
        switch lens {
        case .back:
            // wide+tele の仮想デバイスを優先(videoZoomFactor 1.0 = 24mm 主カメラ。
            // 望遠の切替倍率を超えると実レンズへ自動スイッチする)。
            // 望遠なし機はプレーンな主カメラでデジタルクロップにフォールバック。
            let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            guard let d = device else { return nil }
            return (d, sessionFocal.zoom, false)
        case .front:
            guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return nil }
            return (d, 1, true)
        }
    }

    /// 各 video コネクションに縦持ち固定とミラーリングを設定する。
    private func applyConnectionSettings(mirrored: Bool) {
        for output in [videoOutput, photoOutput] as [AVCaptureOutput] {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            connection.automaticallyAdjustsVideoMirroring = false
            // プレビュー(video)はソフトで向き/ミラーを補正するため hardware ミラーは常に off。
            // 写真(photo)は従来通りのミラー設定を維持する。
            connection.isVideoMirrored = (output === videoOutput) ? false : mirrored
        }
    }

    /// デバイスを lock してズーム倍率を設定する(最大値でクランプ)。
    private func applyZoom(_ zoom: CGFloat, to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(max(zoom, 1), device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        } catch {
            // ズーム設定失敗時はそのまま
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // フロントは iOS26 で videoRotationAngle が効かず横向きで届くため、ソフトで縦・ミラーに補正する。
        var frame = CIImage(cvPixelBuffer: pixelBuffer)
        if currentLens == .front, frame.extent.width > frame.extent.height {
            frame = frame.oriented(.rightMirrored)
            frame = frame.transformed(by: CGAffineTransform(translationX: -frame.extent.minX, y: -frame.extent.minY))
        }
        onPreviewFrame?(frame)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil else { return }
        let handler = photoHandler
        photoHandler = nil
        handler?(photo)
    }
}
