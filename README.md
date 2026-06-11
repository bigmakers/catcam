# MapCam

Passage 風の GPS 情報オーバーレイ付きカメラアプリ(iOS / SwiftUI / Metal)。

## 機能

- **GPS オーバーレイ** — 逆ジオコーディングした地名(例: `📍 Selangor, Malaysia`)+ 座標 + 撮影日時を写真左上に焼き込み
- **Metal フィルタ** — Core Image カスタムカーネル(`NoirFilm.ci.metal`)による「黒が引き立つ」フィルム調。シャドウを深く沈め、暗部の彩度を落として青へ転がし、ビネットを重ねる。スライダーで強度 0–100% 調整
- **ポラロイドモード(オンオフ)** — 真四角クロップ + 白フチ + 下帯に地名・日時キャプション
- **ライブプレビュー** — MTKView + CIContext(Metal) でフィルタ適用済み映像を 30fps 表示
- **EXIF GPS 埋め込み** — 保存される JPEG に GPS / 撮影日時メタデータを書き込み、`PHAsset` にも位置情報を設定

## ビルド & 実行

プロジェクトファイルは [XcodeGen](https://github.com/yonas/xcodegen) で生成します。

```sh
xcodegen generate
open MapCam.xcodeproj
```

1. Signing & Capabilities で自分の Team を選択
2. **実機を選んで Run**(カメラはシミュレータでは動きません)
3. 初回起動時にカメラ・位置情報・写真追加の許可を与える

## 構成

```
MapCam/
├── MapCamApp.swift              # エントリポイント
├── ContentView.swift            # メイン UI(プレビュー / シャッター / トグル / 強度スライダー)
├── Camera/
│   ├── CameraManager.swift      # AVCaptureSession(プレビューフレーム + 写真撮影)
│   └── MetalPreviewView.swift   # MTKView + CIContext によるライブプレビュー
├── Filters/
│   ├── NoirFilm.ci.metal        # Core Image Metal カーネル(黒強調フィルム調)
│   └── NoirFilmFilter.swift     # カーネルラッパー + ビネット
├── Location/
│   └── LocationManager.swift    # CLLocationManager + 逆ジオコーディング
└── Rendering/
    ├── PhotoRenderer.swift      # フィルタ → オーバーレイ/ポラロイド合成 → EXIF GPS 付き JPEG
    └── PhotoSaver.swift         # PHPhotoLibrary 保存
```

メモ: Core Image の Metal カーネルは `MTL_COMPILER_FLAGS: -fcikernel` / `MTLLINKER_FLAGS: -cikernel`(project.yml で設定済み)でビルドされ、`default.metallib` から `CIColorKernel(functionName:fromMetalLibraryData:)` でロードしています。
