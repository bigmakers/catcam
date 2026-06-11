# CATcam

猫を自動検出して頭数を記録する、GPS 情報オーバーレイ付きカメラアプリ(iOS / SwiftUI / Metal)。

## 機能

- **猫の自動検出** — Apple Vision フレームワークによるオンデバイス猫認識。プレビューにリアルタイムで頭数を表示し、撮影すると「N 匹」が写真に記録される
- **GPS オーバーレイ** — 逆ジオコーディングした地名(例: `📍 Selangor, Malaysia`)+ 座標 + 撮影日時を写真左上に焼き込み
- **Metal フィルタ** — Core Image カスタムカーネル(`RetroFilm.ci.metal`)によるレトロ・フィルム風(退色プリント調)フィルター。スライダーで強度 0–100% 調整
- **ポラロイドモード(オンオフ)** — 真四角クロップ + 白フチ + 下帯に地名・日時キャプション
- **ライブプレビュー** — MTKView + CIContext(Metal) でフィルタ適用済み映像を 30fps 表示
- **EXIF GPS 埋め込み** — 保存される JPEG に GPS / 撮影日時メタデータを書き込み、`PHAsset` にも位置情報を設定
- **国境アウトライン地図** — 現在地と国境線をオーバーレイ。ピンチで 1〜8 倍ズーム、ワンタップで非表示
- **近くのスポット** — Apple Maps を使って周辺スポットの名前と距離を焼き込み

## ビルド & 実行

プロジェクトファイルは [XcodeGen](https://github.com/yonas/xcodegen) で生成します。

```sh
xcodegen generate
open CATcam.xcodeproj
```

1. Signing & Capabilities で自分の Team を選択
2. scheme **CATcam** を選択して **実機で Run**(カメラはシミュレータでは動きません)
3. 初回起動時にカメラ・位置情報・写真追加の許可を与える

## 構成

```
CATcam/
├── CATcamApp.swift              # エントリポイント
├── ContentView.swift            # メイン UI(プレビュー / シャッター / トグル / 強度スライダー)
├── Camera/
│   ├── CameraManager.swift      # AVCaptureSession(プレビューフレーム + 写真撮影)
│   └── MetalPreviewView.swift   # MTKView + CIContext によるライブプレビュー
├── Filters/
│   ├── RetroFilm.ci.metal       # Core Image Metal カーネル(レトロフィルム調)
│   └── RetroFilmFilter.swift    # カーネルラッパー + ビネット
├── Vision/
│   └── CatDetector.swift        # Vision フレームワークによる猫検出
├── Location/
│   └── LocationManager.swift    # CLLocationManager + 逆ジオコーディング
└── Rendering/
    ├── PhotoRenderer.swift      # フィルタ → オーバーレイ/ポラロイド合成 → EXIF GPS 付き JPEG
    └── PhotoSaver.swift         # PHPhotoLibrary 保存
```

メモ: Core Image の Metal カーネルは `MTL_COMPILER_FLAGS: -fcikernel` / `MTLLINKER_FLAGS: -cikernel`(project.yml で設定済み)でビルドされ、`default.metallib` から `CIColorKernel(functionName:fromMetalLibraryData:)` でロードしています。
