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

    /// レンズ種別(背面 1x / 3x / 5x / フロント)
    enum Lens: String, CaseIterable { case back1x, back3x, back5x, front }

    @Published private(set) var currentLens: Lens = .back1x

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
        case .back1x:
            guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return nil }
            return (d, 1, false)
        case .back3x:
            if let tele = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) {
                return (tele, 1, false)
            }
            guard let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return nil }
            return (wide, 3, false)
        case .back5x:
            if let tele = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) {
                // iPhone 14 Pro の望遠は 3x のため、5x 相当には 5.0/3.0 倍する
                return (tele, 5.0 / 3.0, false)
            }
            guard let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return nil }
            return (wide, 5, false)
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
            connection.isVideoMirrored = mirrored
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
        onPreviewFrame?(CIImage(cvPixelBuffer: pixelBuffer))
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
