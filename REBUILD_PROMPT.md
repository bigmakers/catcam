# GPS焼き込みカメラアプリ 再作成プロンプト

> 新しいコンセプトで同仕様のアプリを作るとき、このファイル全体を Claude Code に渡す。
> 冒頭の【プロジェクト設定】だけ書き換えれば、残りはそのまま使える。

---

【プロジェクト設定】← ここだけ毎回書き換える

- アプリ名: ◯◯◯◯
- Bundle ID: com.harasaki.◯�◯◯◯
- コンセプト/世界観: (例: 夜景特化 / フィルム写ルンです風 / 山登りログ風 など)
- フィルタの方向性: (例: 黒が引き立つノワール / 退色フィルム / ビビッド)
- アクセントカラー: (例: オレンジ #FF5A2E)
- アイコンのモチーフ: (例: 地図+レンズ)

---

以下の仕様で iOS カメラアプリをゼロから実装してください。空のディレクトリから始め、各ステップでビルドが通ることを確認しながら進めること。

## 技術スタック・プロジェクト構成

- SwiftUI + AVFoundation + Metal(Core Image カスタムカーネル)+ CoreLocation + MapKit
- iOS 17+、iPhone 専用(TARGETED_DEVICE_FAMILY=1)、縦持ち固定
- **XcodeGen** でプロジェクト生成(.xcodeproj はコミットしない。project.yml がソース)
- project.yml の必須設定:
  - `MTL_COMPILER_FLAGS: -fcikernel` と `MTLLINKER_FLAGS: -cikernel`(Core Image の Metal カーネルに必須)
  - `MARKETING_VERSION: "1.0"` / `CURRENT_PROJECT_VERSION: "1"` を settings に置き、Info.plist は `$(MARKETING_VERSION)` 参照
  - `ITSAppUsesNonExemptEncryption: false`(輸出コンプライアンス自動スキップ)
  - Info.plist: NSCameraUsageDescription / NSLocationWhenInUseUsageDescription / NSPhotoLibraryAddUsageDescription / UILaunchScreen: {}
- ビルド検証: `xcodebuild -project X.xcodeproj -scheme X -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- 実機ビルド: `DEVELOPMENT_TEAM=<TeamID>` を渡す。インストールは `xcrun devicectl device install app --device <UDID> <path>`

## ファイル構成(目安)

```
App/
├── ◯◯App.swift / ContentView.swift / HelpView.swift / POISettingsView.swift / Haptics.swift
├── Camera/CameraManager.swift, MetalPreviewView.swift
├── Filters/<Filter>.ci.metal, <Filter>Filter.swift
├── Location/LocationManager.swift, NearbyPlacesManager.swift
├── MapOutline/CountryShapes.swift, MapOutlineRenderer.swift
├── Rendering/PhotoRenderer.swift, PhotoSaver.swift
├── Resources/countries.min.json   ← tools/build_country_data.py で生成
└── Assets.xcassets/AppIcon.appiconset/icon1024.png ← tools/render_app_icon.swift で生成
tools/build_country_data.py, render_app_icon.swift, resize_screenshots.sh
docs/index.html, privacy.html(GitHub Pages 用・日英)
store/listing.md
```

## 機能仕様

### 1. カメラ(CameraManager)
- AVCaptureSession(.photo)。プレビューは AVCaptureVideoDataOutput(BGRA)→ CIImage、撮影は AVCapturePhotoOutput
- 全 video connection に videoRotationAngle=90(縦固定)
- **レンズ切替**: enum Lens { back1x, back3x, back5x, front }。1x=広角 / 3x=望遠(無ければ wide+zoom3) / 5x=望遠×5/3(14Pro の望遠は3xのため。無ければ wide+zoom5) / front=前面+ミラーリング(automaticallyAdjustsVideoMirroring=false → isVideoMirrored、video/photo 両方)
- 切替は sessionQueue 上で beginConfiguration → removeInput → addInput(失敗時は旧 input を戻す)→ 回転・ミラー・zoom 再設定 → commit

### 2. ライブプレビュー(MetalPreviewView)
- MTKView(framebufferOnly=false, bgra8Unorm, 30fps)+ CIContext(mtlDevice:)
- フレームごとにフィルタ適用 → アスペクトフィット → **黒背景に composited(over:)**(レターボックス部に前フレームが残る対策)→ ciContext.render

### 3. Metal フィルタ
- `.ci.metal` の CIColorKernel(extern "C" float4 f(coreimage::sample_t s, float intensity))。コンセプトに合わせたルックを設計(S字カーブ、シャドウ/ハイライトの転がし、彩度コントロール等)
- Swift 側ラッパー: Bundle の default.metallib を `CIColorKernel(functionName:fromMetalLibraryData:)` でロード + CIVignette を重ねる
- UI: 強度スライダー 0〜100%、プレビューにリアルタイム反映

### 4. 位置情報(LocationManager)
- CLLocationManager(distanceFilter 20m)+ CLGeocoder。**preferredLocale: en_US でアルファベット地名**
- 表示名は「市区町村, 州/県, 国」(locality ?? subAdministrativeArea → administrativeArea → country、重複除去)。200m 以上移動で再ジオコーディング

### 5. 国境アウトライン地図
- **データ**: Natural Earth 50m admin_0 GeoJSON を Python スクリプトで前処理(外輪のみ・座標2桁丸め・連続重複除去・4点未満リング破棄)→ `{"countries":[{iso,name,bbox:[w,s,e,n],polys:[[[lon,lat],...]]}]}` を minify(約1.4MB)してバンドル
- **CountryShapes**: JSONSerialization でロード(NSLock で二重ロード防止)。country(containing:)=bboxプリフィルタ→レイキャスティング(複数ヒットは bbox 面積最小)、nearestCountry(bbox中心+cos緯度補正)、countries(intersecting:)
- **MapOutlineRenderer.image(for:sidePx:zoom:)** 純粋関数→透明背景の正方形 UIImage:
  - ビューポート: 基準国bbox+現在地+8%パディング → メルカトル空間(y=ln(tan(π/4+φ/2))、φ±85°クランプ)で正方形化 → zoom(1〜8)で span/z、現在地中心に取り直し
  - **交差国の判定は正方形化後の範囲を逆メルカトルで緯度経度に戻してから**(縦長国で隣国が欠ける罠)
  - 白ストローク(alpha .95、lineWidth sidePx*0.007、round、黒 soft shadow)。±180跨ぎ(隣接点の経度差>180)で線を切る
  - 現在地マーカー: 白円(r=sidePx*0.05)+アクセント色円(0.72r)+白点(0.26r)
- UI: ピンチで 1〜8 倍ズーム(@AppStorage 永続化、ピンチ中は前回 Task を cancel する簡易デバウンス)、地図オン/オフトグル(@AppStorage、オフ時は生成スキップ+状態クリア)

### 6. 最寄りスポット(NearbyPlacesManager)
- MKLocalPointsOfInterestRequest(500m四方)+ ジャンルフィルタ。距離順に先頭 N 件
- ジャンル enum: なし/すべて/飲食店/カフェ/観光/駅・交通(MKPointOfInterestCategory のセットにマップ)
- 設定シート: ジャンル Picker(.menu)+ 件数 Stepper(1〜6)。@AppStorage("poiGenre"/"poiCount")、デフォルト 飲食店・3件
- 200m未満かつ条件不変ならスキップ。進行中の MKLocalSearch は cancel。@Published は main で反映
- 表示形式: "名前 120m" / "名前 1.2km"

### 7. コメント
- シャッター上に TextField(ダーク調、クリア✕ボタン、submitLabel(.done)、撮影後も保持)
- 焼き込み位置: 3文字コードの直下に太字(下記)

### 8. 写真合成(PhotoRenderer)— u = 幅or辺/1000 の相対寸法
- CaptureOptions: polaroid/intensity/location/placeName/date/mapZoom/mapEnabled/comment/nearbyPlaces
- フロー: AVCapturePhoto → CIImage(applyOrientationProperty)→ フィルタ → CGImage → UIGraphicsImageRenderer 合成 → **EXIF GPS 付き JPEG**(CGImageDestination: GPS緯度経度高度+DateTimeOriginal、品質0.92)→ PHAssetCreationRequest(+ request.location)
- **通常モード**(3:4そのまま、左上に白文字+影):
  1. 地名3文字コード(84u heavy)— placeName 先頭要素の英字3文字を大文字化(例 Setagaya→SET)
  2. コメント(44u heavy)
  3. 📍地名(36u bold) 4. 座標 "35.6462°N, 139.6532°E"(30u mono semibold) 5. 日時 yyyy/MM/dd HH:mm(30u)
  6. 最寄りスポット 各行「・名前 120m」(26u semibold, alpha .9)
  7. その下に地図(幅の36%)
- **ポラロイドモード**(デフォルトON, @AppStorage):
  - 正方形センタークロップ。margin=辺6%(上左右)、下帯=辺24%、背景 white:0.97
  - 写真領域左上(pad 辺5%)に地図(辺34%)、**その直下に最寄りスポット**(白+影、26u semibold)
  - 下帯(ink=white:0.22): コード(64u)/コメント時は 56u+コメント32u bold/📍地名(36u/30u)/日時+座標(27u/24u mono, alpha .65)— コメント有無でサイズを切り替えて帯に収める
- **プレビューは完全 WYSIWYG**: ポラロイドは aspectRatio(1.12/1.30) の GeometryReader で photoSide=W/1.12 から同比率で再現。通常モードも同じ情報を左上に表示

### 9. UI(ContentView)
- 構成(上から): プレビュー(右上に?ヘルプボタン)/ レンズ行 [地図トグル | 1x 3x 5x 前面 | POI設定🍴] / 強度スライダー行 / コメント欄 / [ギャラリーサムネ | シャッター | Polaroidトグル]
- シャッター: 白二重円。撮影時フラッシュ(白 overlay 0.7→0)+ UIImpactFeedbackGenerator(.medium)
- ギャラリーサムネ: 直近の保存画像。タップで `photos-redirect://` を open
- **全ボタンに Haptics.tick()**(UISelectionFeedbackGenerator.selectionChanged + prepare の共通 enum)
- ヘルプシート(HelpView): 各機能をアイコン+見出し+説明で列挙。初回起動時に自動表示(@AppStorage("hasSeenHelp"))

### 10. アプリアイコン
- tools/render_app_icon.swift(macOS AppKit/CoreGraphics, `swift tools/render_app_icon.swift` で実行)で 1024x1024 を生成
- バンドルの countries.min.json から日本周辺をメルカトル投影で白アウトライン描画 + 中央にレンズ(白リング/暗いガラスの放射グラデ/ハイライト/中心にマーカー意匠)— モチーフは【プロジェクト設定】に合わせて変える
- **必ず不透明 PNG**(noneSkipLast。アルファ付きは App Store で拒否される)
- Assets.xcassets は single-size(universal 1024)+ project.yml に `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`

## 公開準備(App Store)

- docs/index.html・privacy.html(日英、ダークデザイン、連絡先 bigmakers@gmail.com)→ GitHub Pages(/docs)
- プライバシー方針: 全処理端末内・開発者サーバー無し → App プライバシーは「データを収集していません」
- store/listing.md に説明文・キーワード・プロモ文の草案
- tools/resize_screenshots.sh: 実機スクショを sips で 6.9インチ枠 1290x2796 に変換(in/→out/)
- アーカイブ→IPA→アップロード(App Store Connect API キーは ~/.appstoreconnect/private_keys/ に配置済みのものを使う。Key ID / Issuer ID は公開リポジトリに書かない):
  ```
  xcodebuild -scheme X -configuration Release -destination 'generic/platform=iOS' -archivePath build/X.xcarchive archive -allowProvisioningUpdates DEVELOPMENT_TEAM=<TeamID>
  xcodebuild -exportArchive -archivePath build/X.xcarchive -exportPath build/export -exportOptionsPlist build/exportOptions.plist(method: app-store-connect, teamID)
  xcrun altool --upload-app -f build/export/X.ipa --type ios --apiKey <KeyID> --apiIssuer <IssuerID>
  ```
- Bundle ID は API で登録可(POST /v1/bundleIds)。**App レコード作成だけは Web のみ**(API は 403)。App Store Connect の入力フォームは textarea/select は JS 注入で反映できるが input[type=text] は不可(shadow DOM)— 手動かガイド付きで

## 既知の罠(必ず守る)

1. CI Metal カーネルは cikernel フラグなしだとロード時に nil になる
2. MTKView レターボックスは黒に composite しないと前フレームが残る
3. ビューポート交差判定は正方形化「後」の範囲で(逆メルカトル)
4. 逆ジオコーディングは preferredLocale 指定しないと端末言語になる
5. アイコン PNG のアルファチャンネル除去
6. ポラロイドのプレビューと焼き込みは寸法定数を共有しないとズレる(WYSIWYG が崩れたらユーザーは必ず気づく)
7. AppStorage のキー名はこの仕様書と同じにする必要はないが、polaroid デフォルトは true
8. 実機 DDI エラー(12040)はデバイス再起動で直る

## 進め方の指示

- 実装フェーズごとにビルドを通す: ①カメラ+フィルタ ②位置情報+焼き込み ③地図 ④ポラロイドWYSIWYG ⑤POI+コメント ⑥アイコン+公開準備
- git init して機能単位でコミット
- 完了したら実機インストールまで行う
