import SwiftUI
import AVFoundation
import CoreLocation

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var nearbyManager = NearbyPlacesManager()

    /// アスペクト比(rawValue を AppStorage で永続化)
    @AppStorage("cropAspect") private var cropAspectRaw = CropAspect.r43.rawValue
    private var cropAspect: CropAspect { CropAspect(rawValue: cropAspectRaw) ?? .r43 }

    /// 地図表示オン/オフ(永続化)
    @AppStorage("mapEnabled") private var mapEnabled = false
    /// フィルム強度(コントラスト/グレイン/減光)。設定シートで調整。
    @AppStorage("filmIntensity") private var intensity = 0.8
    /// 色温度(寒色強度)。0=標準, 1=最大寒色
    @AppStorage("coolness") private var coolness = 0.35
    /// フィルムシミュレーション(rawValue を永続化)
    @AppStorage("filmSim") private var filmSimRaw = FilmSimulation.standard.rawValue
    private var filmSim: FilmSimulation { FilmSimulation(rawValue: filmSimRaw) ?? .standard }
    @State private var lastThumbnail: UIImage?
    @State private var isSaving = false
    @State private var flashOpacity = 0.0
    /// 直近の加工結果を全画面プレビュー表示するフラグ

    /// ライブプレビュー用の国境アウトライン地図
    @State private var mapImage: UIImage?
    /// 地図を最後に生成した位置(10km 以上動いたら再生成)
    @State private var mapImageLocation: CLLocation?
    /// 地図を最後に生成したズーム倍率(変化したら再生成)
    @State private var mapImageZoom: Double?

    /// 地図ズーム倍率(デフォルトでややズーム)
    @AppStorage("mapZoom") private var mapZoom = 2.5

    /// 地名を焼き込むか(コード見出し + 📍行)
    @AppStorage("showPlaceName") private var showPlaceName = false
    /// 座標を焼き込むか
    @AppStorage("showCoordinates") private var showCoordinates = false
    /// 日時を焼き込むか
    @AppStorage("showDateTime") private var showDateTime = false
    /// 焼き込み情報を右端に寄せるか(false=左端)。表示設定と同一キー。
    @AppStorage("infoOnRight") private var infoOnRight = false

    /// ヘルプシート表示フラグ
    @State private var showHelp = false
    /// 初回起動判定(一度でも表示済みなら true)
    @AppStorage("hasSeenHelp") private var hasSeenHelp = false

    /// 近くのスポット設定シート表示フラグ
    @State private var showPOISettings = false
    /// 近くのスポットのジャンル(永続化、POISettingsView と整合)
    @AppStorage("poiGenre") private var poiGenreRaw = POIGenre.none.rawValue
    /// 近くのスポットの表示件数(永続化)
    @AppStorage("poiCount") private var poiCount = 3

    /// 写真に焼き込むコメント(撮影後も自動クリアしない)
    @State private var commentText = ""
    /// コメント入力のフォーカス(キーボード表示制御)
    @FocusState private var commentFocused: Bool
    /// コメント書体(雑誌風)。表示設定と同一キーで同期。
    @AppStorage("commentFont") private var commentFontRaw = CommentFont.minchoEditorial.rawValue
    private var commentFontStyle: CommentFont { CommentFont.resolve(commentFontRaw) }

    /// 端末の向き(情報ブロックの回転に使う。写真自体は無回転)。
    @State private var deviceOrientation: UIDeviceOrientation = .portrait
    /// 出力画像を端末の向きに合わせて回す量(時計回りの90°単位)。横持ち撮影で横向き出力に。
    private var captureQuarterTurns: Int {
        switch deviceOrientation {
        case .landscapeLeft:       return 3
        case .landscapeRight:      return 1
        case .portraitUpsideDown:  return 2
        default:                   return 0
        }
    }
    /// プレビューの文字情報だけを端末の向きに合わせて回す角度(被写体は回転しない)。
    private var infoAngle: Angle {
        switch deviceOrientation {
        case .landscapeLeft:       return .degrees(90)
        case .landscapeRight:      return .degrees(-90)
        case .portraitUpsideDown:  return .degrees(180)
        default:                   return .degrees(0)
        }
    }
    /// 回した情報ブロックのアンカー(左:top-left / 右:top-right)を、向き+左右に対応する隅へ移す平行移動量。
    private func infoOffset(_ size: CGSize) -> CGSize {
        let W = size.width, H = size.height
        if infoOnRight {
            // アンカーはブロックの top-right(= フレーム右上 (W,0))。目的隅 - (W,0)
            switch captureQuarterTurns {
            case 1:  return CGSize(width: -W, height: 0)   // 目的=左上(0,0)
            case 2:  return CGSize(width: -W, height: H)   // 目的=左下(0,H)
            case 3:  return CGSize(width: 0,  height: H)   // 目的=右下(W,H)
            default: return .zero                          // 目的=右上(W,0)
            }
        } else {
            switch captureQuarterTurns {
            case 1:  return CGSize(width: 0, height: H)
            case 2:  return CGSize(width: W, height: H)
            case 3:  return CGSize(width: W, height: 0)
            default: return .zero
            }
        }
    }

    /// 現在のジャンル(rawValue → enum)
    private var poiGenre: POIGenre { POIGenre(rawValue: poiGenreRaw) ?? .none }

    /// ピンチ開始時の基準倍率(ジェスチャ中のみ非 nil)
    @State private var gestureBaseZoom: Double?
    /// ピンチ中の連打デバウンス用の直前生成 Task
    @State private var mapRenderTask: Task<Void, Never>?

    /// フォトライブラリピッカー表示フラグ
    @State private var showPhotoPicker = false

    /// 背面レンズの焦点距離(mm)。タップで 28 → 52 → 120 を巡回。
    @AppStorage("focalMm") private var focalMm = 28
    private var focal: CameraManager.Focal { CameraManager.Focal(rawValue: focalMm) ?? .f28 }

    /// Before/After 比較。プレビュー長押し中だけフィルタを外して素の映像を見せる。
    /// GestureState なので指を離すと自動で false に戻る。
    @GestureState private var isComparing = false

    /// 猫ログ(アプリ内ギャラリー)表示フラグ
    @State private var showNekoLog = false
    /// 猫を振り向かせる呼び音
    @StateObject private var catCaller = CatCaller()
    /// 呼び音の種類(表示設定と同一キー)
    @AppStorage("catSound") private var catSoundRaw = CatCaller.Sound.squeak.rawValue
    private var catSound: CatCaller.Sound { CatCaller.Sound(rawValue: catSoundRaw) ?? .squeak }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                preview
                    .frame(maxWidth: .infinity)
                    .aspectRatio(cropAspect.previewRatio, contentMode: .fit)
                    .clipped()
                    .animation(.easeInOut(duration: 0.2), value: cropAspect.previewRatio)
                    .overlay(alignment: .topTrailing) {
                        // ヘルプボタン(右上、コントロールと干渉しない位置)
                        Button { Haptics.tick(); showHelp = true } label: {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.75))
                                .shadow(color: .black.opacity(0.4), radius: 3)
                        }
                        .padding(16)
                    }
                    .overlay(alignment: .bottom) {
                        // Before/After 比較中の表示
                        if isComparing {
                            Text("ORIGINAL")
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .tracking(2)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Color.white.opacity(0.85), in: Capsule())
                                .padding(.bottom, 14)
                        }
                    }
                    // 長押しでフィルタOFF(Before)、離すとON(After)。
                    // simultaneousGesture なのでピンチ(地図ズーム)やタップと共存する。
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .updating($isComparing) { value, state, _ in
                                if case .second = value { state = true }
                            }
                    )

                Spacer(minLength: 0)
                controls
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            // 左下サムネイル(猫ログ入口)に前回までの最新一枚を出す
            if lastThumbnail == nil, let newest = NekoLogStore.shared.entries.first {
                Task.detached(priority: .utility) {
                    let thumb = NekoLogStore.shared.thumbnail(for: newest, maxPixel: 112)
                    await MainActor.run { if lastThumbnail == nil { lastThumbnail = thumb } }
                }
            }
            camera.select(focal: focal)   // start 前に呼ぶ(同一シリアルキューで順に適用される)
            camera.start()
            locationManager.start()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            // 国境データを先読み
            Task.detached { CountryShapes.shared.loadIfNeeded() }
            // 初回起動時にヘルプを自動表示
            if !hasSeenHelp {
                hasSeenHelp = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showHelp = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let o = UIDevice.current.orientation
            // faceUp/faceDown/unknown は無視して直前の有効な向きを保持
            if o == .portrait || o == .portraitUpsideDown || o == .landscapeLeft || o == .landscapeRight {
                withAnimation(.easeInOut(duration: 0.25)) { deviceOrientation = o }
            }
        }
        .sheet(isPresented: $showHelp) { HelpView() }
        .fullScreenCover(isPresented: $showNekoLog) {
            NekoLogView { showNekoLog = false }
        }
        .sheet(isPresented: $showPOISettings) { POISettingsView() }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoLibraryPicker { image, location, date in
                showPhotoPicker = false
                importFromLibrary(image: image, location: location, date: date)
            } onCancel: {
                showPhotoPicker = false
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        Group {
            if cropAspect == .polaroid {
                polaroidPreview
            } else {
                normalPreview
            }
        }
            .overlay(
                Color.white
                    .opacity(flashOpacity)
                    .allowsHitTesting(false)
            )
            .onChange(of: locationManager.location) { _ in
                updateMapImageIfNeeded()
                updateNearbyPlaces()
            }
            .onChange(of: mapEnabled) { _ in
                updateMapImageIfNeeded()
            }
            .onChange(of: poiGenreRaw) { _ in
                updateNearbyPlaces()
            }
            .onChange(of: poiCount) { _ in
                updateNearbyPlaces()
            }
    }

    /// 現在地・ジャンル・件数で周辺スポットを更新する(マネージャ側で重複取得を判定)。
    private func updateNearbyPlaces() {
        guard let location = locationManager.location else { return }
        nearbyManager.update(for: location, genre: poiGenre, count: poiCount)
    }

    /// 通常モード: 被写体(カメラ)はそのまま、左上の文字情報だけ端末の向きに回転。
    private var normalPreview: some View {
        ZStack(alignment: .topLeading) {
            cameraLayer()

            GeometryReader { geo in
                // 情報の起点コーナー(左:top-left / 右:top-right)を向きに対応する隅へ置き、その隅軸で回転。
                // 出力(回転後画像の左上/右上)と同じ位置・向きになる。被写体は無回転。
                infoLiveBlock(width: geo.size.width)
                    .frame(width: geo.size.width, height: geo.size.height,
                           alignment: infoOnRight ? .topTrailing : .topLeading)
                    .rotationEffect(infoAngle, anchor: infoOnRight ? .topTrailing : .topLeading)
                    .offset(infoOffset(geo.size))
                    .animation(.easeInOut(duration: 0.25), value: captureQuarterTurns)
                    .animation(.easeInOut(duration: 0.25), value: infoOnRight)
            }
        }
        // 地図表示中は写真全体のピンチで地図をズーム
        .contentShape(Rectangle())
        .gesture(mapZoomGesture)
        // プレビュータップでキーボードを閉じる
        .onTapGesture { commentFocused = false }
    }

    /// 左上の焼き込み情報のライブ表示(テキスト + 地図 + コメント)。
    /// width = プレビューの短辺。焼き込みと同じ u=width/1000 の比例サイズで組む。
    private func infoLiveBlock(width: CGFloat) -> some View {
        let u = width / 1000.0
        let cSize = commentFontSize(u: u)
        return VStack(alignment: infoOnRight ? .trailing : .leading, spacing: 8 * u) {
            liveOverlay(u: u)
            if mapEnabled, let mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .frame(width: width * 0.36, height: width * 0.36)
                    .padding(.top, 4 * u)
            }
            // コメント(地図の下)。設定で選んだ雑誌風書体。
            if !commentText.isEmpty {
                Text(commentText)
                    .font(.system(size: cSize,
                                  weight: commentFontStyle.swiftWeight,
                                  design: commentFontStyle.design))
                    .tracking(cSize * commentFontStyle.trackingRatio)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(infoOnRight ? .trailing : .leading)
                    .shadow(color: .black.opacity(0.55), radius: 6 * u, y: 2 * u)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(10)
                    .padding(.top, 6 * u)
            }
        }
        .padding(infoOnRight ? .trailing : .leading, 44 * u)
        .padding(.top, 44 * u)
    }

    /// カメラ映像 or 権限メッセージ。
    @ViewBuilder
    private func cameraLayer(squareCrop: Bool = false) -> some View {
        switch camera.status {
        case .denied:
            permissionMessage("カメラへのアクセスが許可されていません。\n設定アプリから許可してください。")
        case .failed:
            permissionMessage("カメラを起動できませんでした。")
        default:
            MetalPreviewView(camera: camera,
                             intensity: isComparing ? 0 : intensity,
                             coolness: isComparing ? 0 : coolness,
                             sim: filmSim,
                             squareCrop: squareCrop)
        }
    }

    // MARK: - ポラロイドモードのライブプレビュー

    /// composePolaroid と同じ寸法でライブプレビューを構成する。
    /// 全体幅 W に対し photoSide = W / 1.12、margin = photoSide * 0.06。
    /// キャンバス比率 = (side*1.12) : (side*1.30) は body 側の aspectRatio(previewRatio) が担う。
    private var polaroidPreview: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let photoSide = totalWidth / 1.12
            let margin = photoSide * 0.06
            let mapSide = photoSide * 0.34
            let mapPad = photoSide * 0.05

            VStack(alignment: .leading, spacing: 0) {
                // 上部: 上・左・右 margin の白フチ内に正方形カメラ映像。
                // 映像左上(または右上)に地図を重ね、ピンチズームを維持する。
                ZStack(alignment: infoOnRight ? .topTrailing : .topLeading) {
                    cameraLayer(squareCrop: true)
                        .frame(width: photoSide, height: photoSide)
                        .clipped()

                    // 地図 + その下に近くのスポット(composePolaroid と同じ配置)
                    VStack(alignment: infoOnRight ? .trailing : .leading, spacing: photoSide * 0.012) {
                        if mapEnabled, let mapImage {
                            Image(uiImage: mapImage)
                                .resizable()
                                .frame(width: mapSide, height: mapSide)
                                .contentShape(Rectangle())
                                .gesture(mapZoomGesture)
                        }
                        polaroidPlaces(photoSide: photoSide)
                    }
                    .offset(x: infoOnRight ? -mapPad : mapPad, y: mapPad)
                }
                .padding(.top, margin)
                .padding(.horizontal, margin)

                // 下帯キャプション
                polaroidCaption(photoSide: photoSide)
                    .frame(maxWidth: .infinity, alignment: infoOnRight ? .trailing : .leading)
                    .padding(infoOnRight ? .trailing : .leading, margin + photoSide * 0.008)
                    .padding(.top, photoSide * 0.03)

                Spacer(minLength: 0)
            }
            .frame(width: totalWidth, height: geo.size.height, alignment: .topLeading)
            .background(Color(white: 0.97))
        }
        // プレビュータップでキーボードを閉じる
        .onTapGesture { commentFocused = false }
    }

    /// composePolaroid の下帯テキスト(地名コード / コメント / 📍地名 / 日時 + 座標)。
    /// フォントサイズは photoSide 基準で composePolaroid (64/36/27 * side/1000) と一致。
    @ViewBuilder
    private func polaroidCaption(photoSide: CGFloat) -> some View {
        let ink = Color(white: 0.22)
        let hasComment = !commentText.isEmpty
        // コメント有無で composePolaroid に合わせてフォントサイズを切り替える
        let codeRatio: CGFloat = hasComment ? 0.056 : 0.064
        let placeRatio: CGFloat = hasComment ? 0.030 : 0.036
        let subtitleRatio: CGFloat = hasComment ? 0.024 : 0.027
        VStack(alignment: infoOnRight ? .trailing : .leading, spacing: photoSide * 0.01) {
            if showPlaceName, let code = PhotoRenderer.placeCode(from: locationManager.placeName) {
                Text(code)
                    .font(.system(size: photoSide * codeRatio, weight: .heavy))
                    .foregroundStyle(ink)
            }
            if hasComment {
                // composePolaroid と同じ縮小則(1行=32u、行が増えるごとに -5u、最大4行)
                let lines = commentText.split(separator: "\n", omittingEmptySubsequences: false).prefix(4)
                let n = max(1, lines.count)
                let cSize = photoSide * (32 - CGFloat(n - 1) * 5) / 1000.0
                Text(lines.joined(separator: "\n"))
                    .font(.system(size: cSize,
                                  weight: commentFontStyle.swiftWeight,
                                  design: commentFontStyle.design))
                    .tracking(cSize * commentFontStyle.trackingRatio)
                    .foregroundStyle(ink)
                    .multilineTextAlignment(infoOnRight ? .trailing : .leading)
                    .lineLimit(4)
            }
            if showPlaceName, !locationManager.placeName.isEmpty {
                Text("📍 \(locationManager.placeName)")
                    .font(.system(size: photoSide * placeRatio, weight: .bold))
                    .foregroundStyle(ink)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let subtitle = captionSubtitle(date: context.date)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: photoSide * subtitleRatio, weight: .regular, design: .monospaced))
                        .foregroundStyle(ink.opacity(0.65))
                }
            }
        }
    }

    /// 写真上(地図の下)の近くのスポット表示(composePolaroid の配置に対応)。
    @ViewBuilder
    private func polaroidPlaces(photoSide: CGFloat) -> some View {
        VStack(alignment: infoOnRight ? .trailing : .leading, spacing: photoSide * 0.006) {
            ForEach(nearbyManager.places.map(\.display), id: \.self) { place in
                Text("・" + place)
                    .font(.system(size: photoSide * 0.026, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                    .lineLimit(1)
            }
        }
    }

    /// 下帯末尾行: 日時 +(座標があれば)"   " + 座標。composePolaroid と同一の組み立て。
    private func captionSubtitle(date: Date) -> String {
        var parts: [String] = []
        if showDateTime {
            parts.append(PhotoRenderer.displayDateFormatter.string(from: date))
        }
        if showCoordinates, let coordinate = locationManager.location?.coordinate {
            parts.append(coordinate.displayString)
        }
        return parts.joined(separator: "   ")
    }

    /// 地図ピンチズーム。開始時の倍率を基準に 1...8 へクランプし、その都度再生成。
    private var mapZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard mapEnabled else { return }   // 地図表示中のみ有効
                let base = gestureBaseZoom ?? mapZoom
                if gestureBaseZoom == nil { gestureBaseZoom = base }
                mapZoom = min(max(base * value, 1), 8)
                updateMapImageIfNeeded()
            }
            .onEnded { _ in
                gestureBaseZoom = nil
            }
    }

    /// 撮影結果に焼き込まれる内容のライブ表示。焼き込み(PhotoRenderer)と同じ
    /// 短辺基準の比例サイズ(u = 短辺/1000)で組み、出力と一致させる。
    private func liveOverlay(u: CGFloat) -> some View {
        VStack(alignment: infoOnRight ? .trailing : .leading, spacing: 8 * u) {
            if showPlaceName, let code = PhotoRenderer.placeCode(from: locationManager.placeName) {
                Text(code)
                    .font(.system(size: 84 * u, weight: .heavy))
            }
            if showPlaceName, !locationManager.placeName.isEmpty {
                Text("📍 \(locationManager.placeName)")
                    .font(.system(size: 36 * u, weight: .bold))
            }
            if showCoordinates, let coordinate = locationManager.location?.coordinate {
                Text(coordinate.displayString)
                    .font(.system(size: 30 * u, weight: .semibold, design: .monospaced))
            }
            if showDateTime {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(PhotoRenderer.displayDateFormatter.string(from: context.date))
                        .font(.system(size: 30 * u, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            // 近くのスポット(日時の下)
            ForEach(nearbyManager.places.map(\.display), id: \.self) { place in
                Text("・\(place)")
                    .font(.system(size: 26 * u, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.55), radius: 6 * u, y: 2 * u)
    }

    private func permissionMessage(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 20) {
            filmDial

            lensRow

            commentField

            HStack {
                // 左側: サムネイル + ギャラリー取り込みボタン
                VStack(spacing: 6) {
                    thumbnail
                        .frame(width: 56, height: 56)
                    importButton
                }

                Spacer()

                shutterButton

                Spacer()

                // アスペクト比切替ボタン(ポラロイドボタン位置)
                Button {
                    Haptics.tick()
                    let all = CropAspect.allCases
                    let idx = all.firstIndex(of: cropAspect) ?? 0
                    let next = all[(idx + 1) % all.count]
                    cropAspectRaw = next.rawValue
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: cropAspect == .polaroid ? "square.fill" : "aspectratio")
                            .font(.system(size: 22))
                        Text(cropAspect.label)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(cropAspect == .polaroid ? .yellow : .white)
                    .frame(width: 56, height: 56)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    /// 写真に焼き込むコメント入力欄(ダーク調、入力時のみクリアボタン表示)
    private var commentField: some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("", text: $commentText, prompt:
                Text("コメント(改行で最大10行・写真に焼き込み)")
                    .foregroundColor(.white.opacity(0.4)),
                      axis: .vertical)
                .foregroundStyle(.white)
                .lineLimit(1...10)
                .focused($commentFocused)
                .onChange(of: commentText) { _ in capCommentLines() }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完了") { Haptics.tick(); commentFocused = false }
                    }
                }

            if !commentText.isEmpty {
                Button {
                    Haptics.tick()
                    commentText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 28)
    }

    /// コメントを最大 10 行に制限する。
    private func capCommentLines() {
        var lines = commentText.components(separatedBy: "\n")
        guard lines.count > 10 else { return }
        lines = Array(lines.prefix(10))
        commentText = lines.joined(separator: "\n")
    }

    /// コメント文字サイズ。焼き込みと同じ (44 - t*22)*u(行数で縮小)。
    private func commentFontSize(u: CGFloat) -> CGFloat {
        let n = max(1, min(10, commentText.components(separatedBy: "\n").count))
        let t = CGFloat(n - 1) / 9.0
        return (44 - t * 22) * u
    }

    /// レンズ行: 地図トグル / 固定スペック表示 + フロント切替ボタン / 設定ボタン
    /// フィルムシミュレーションの横スクロールダイヤル。
    /// 選択中は琥珀色で塗り、タップで即プレビューに反映される。
    private var filmDial: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilmSimulation.allCases) { sim in
                        let selected = sim == filmSim
                        Button {
                            Haptics.tick()
                            filmSimRaw = sim.rawValue
                        } label: {
                            Text(sim.name)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(selected ? .black : .white.opacity(0.85))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                // 選択色: フィルム系=琥珀 / METAL系=シルバー
                                .background(selected ? (sim.isMetal ? Color(red: 0.80, green: 0.83, blue: 0.87)
                                                                    : Color(red: 0.95, green: 0.75, blue: 0.28))
                                                     : Color.white.opacity(0.14))
                                .clipShape(Capsule())
                        }
                        .id(sim)
                    }
                }
                .padding(.horizontal, 24)
            }
            .onAppear {
                // 起動時に選択中のフィルムを画面内へ
                proxy.scrollTo(filmSim, anchor: .center)
            }
            .onChange(of: filmSimRaw) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(filmSim, anchor: .center)
                }
            }
        }
        .frame(height: 30)
    }

    private var lensRow: some View {
        HStack(spacing: 10) {
            // 地図オン/オフトグル(行の左端)
            Button {
                Haptics.tick()
                mapEnabled.toggle()
            } label: {
                Image(systemName: mapEnabled ? "map.fill" : "map")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(mapEnabled ? .yellow : .white)
                    .frame(width: 40, height: 32)
                    .background(Color.white.opacity(mapEnabled ? 0.0 : 0.18))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            // 猫を振り向かせる呼び音(種類は表示設定で選択)
            Button {
                Haptics.tick()
                catCaller.play(catSound)
            } label: {
                Image(systemName: catSound.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 32)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
            }

            // 焦点距離の切替(28 → 52 → 120 を巡回)
            Button {
                Haptics.tick()
                let all = CameraManager.Focal.allCases
                let idx = all.firstIndex(of: focal) ?? 0
                let next = all[(idx + 1) % all.count]
                focalMm = next.rawValue
                camera.select(focal: next)
            } label: {
                Text(focal.label)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(camera.currentLens == .front ? .white.opacity(0.4) : .white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
            }
            .disabled(camera.currentLens == .front)

            // フロント/バック切替ボタン
            Button {
                Haptics.tick()
                let next: CameraManager.Lens = camera.currentLens == .front ? .back : .front
                camera.select(next)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(camera.currentLens == .front ? .yellow : .white.opacity(0.9))
                    .frame(width: 44, height: 32)
                    .background(camera.currentLens == .front ? Color.white.opacity(0.18) : Color.clear)
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            // 表示設定(行の右端、地図トグルと同様のカプセル)
            Button {
                Haptics.tick()
                showPOISettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(poiGenre == .none ? .white : .yellow)
                    .frame(width: 40, height: 32)
                    .background(Color.white.opacity(poiGenre == .none ? 0.18 : 0.0))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 28)
    }

    private var shutterButton: some View {
        Button(action: capture) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(.white)
                    .frame(width: 62, height: 62)
            }
        }
        .disabled(camera.status != .running || isSaving)
        .opacity(camera.status == .running && !isSaving ? 1 : 0.4)
    }

    /// タップでアプリ内ギャラリー「猫ログ」を開く(直近の一枚をサムネイル表示)
    private var thumbnail: some View {
        Button {
            Haptics.tick()
            showNekoLog = true
        } label: {
            if let lastThumbnail {
                Image(uiImage: lastThumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.4), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.08))
                    .overlay(
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(.white.opacity(0.5))
                    )
            }
        }
    }

    // MARK: - Map preview generation

    /// 初回、前回生成位置から 10km 以上動いた、または zoom が変化したとき地図を再生成する。
    /// ピンチ中の連打対策として直前の生成 Task を cancel してから新 Task を起動する。
    private func updateMapImageIfNeeded() {
        // オフ時は地図をクリアし、次のオン時に確実に再生成されるよう生成状態をリセット
        guard mapEnabled else {
            mapImage = nil
            mapImageLocation = nil
            mapImageZoom = nil
            return
        }
        guard let location = locationManager.location else { return }
        let movedFar = mapImageLocation.map { location.distance(from: $0) >= 10_000 } ?? true
        let zoomChanged = mapImageZoom != mapZoom
        guard movedFar || zoomChanged else { return }

        mapImageLocation = location
        mapImageZoom = mapZoom

        let coordinate = location.coordinate
        let zoom = mapZoom
        mapRenderTask?.cancel()
        mapRenderTask = Task.detached(priority: .utility) {
            let image = MapOutlineRenderer.image(for: coordinate, sidePx: 512, zoom: zoom)
            if Task.isCancelled { return }
            await MainActor.run { self.mapImage = image }
        }
    }

    // MARK: - Capture

    private func capture() {
        isSaving = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.easeIn(duration: 0.05)) { flashOpacity = 0.7 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.25)) { flashOpacity = 0 }
        }

        let aspect = cropAspect
        let options = CaptureOptions(
            aspectW: aspect.w,
            aspectH: aspect.h,
            polaroid: aspect == .polaroid,
            intensity: intensity,
            coolness: coolness,
            sim: filmSim,
            commentFont: commentFontStyle,
            quarterTurns: captureQuarterTurns,
            infoOnRight: infoOnRight,
            location: locationManager.location,
            placeName: locationManager.placeName,
            date: Date(),
            mapZoom: mapZoom,
            mapEnabled: mapEnabled,
            comment: commentText,
            nearbyPlaces: nearbyManager.places.map(\.display),
            showPlaceName: showPlaceName,
            showCoordinates: showCoordinates,
            showDateTime: showDateTime,
            isFront: camera.currentLens == .front)

        camera.capturePhoto { photo in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let data = PhotoRenderer.shared.render(photo: photo, options: options) else {
                    DispatchQueue.main.async { isSaving = false }
                    return
                }
                let thumbnail = UIImage(data: data)
                PhotoSaver.save(data, location: options.location) { saved in
                    if saved {
                        NekoLogStore.shared.add(data: data, date: options.date, place: options.placeName)
                    }
                    lastThumbnail = thumbnail
                    isSaving = false
                }
            }
        }
    }

    // MARK: - Import from Photo Library

    /// ギャラリー取り込みボタン(サムネイルの下に配置)
    private var importButton: some View {
        Button {
            Haptics.tick()
            showPhotoPicker = true
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 56, height: 24)
        }
        .disabled(isSaving)
        .opacity(isSaving ? 0.4 : 1)
    }

    /// PHPicker から取得した画像を ImportProcessor で加工・保存する。
    private func importFromLibrary(image: UIImage, location: CLLocation?, date: Date?) {
        isSaving = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let aspect = cropAspect
        let currentIntensity = intensity
        let currentCoolness = coolness
        let currentSim = filmSim
        let currentCommentFont = commentFontStyle
        let currentMapZoom = mapZoom
        let currentMapEnabled = mapEnabled
        let currentComment = commentText
        let currentGenre = poiGenre
        let currentCount = poiCount
        let currentShowPlaceName = showPlaceName
        let currentShowCoordinates = showCoordinates
        let currentShowDateTime = showDateTime
        let currentInfoOnRight = infoOnRight

        Task {
            let result = await ImportProcessor.process(
                image: image,
                location: location,
                date: date,
                aspectW: aspect.w,
                aspectH: aspect.h,
                polaroid: aspect == .polaroid,
                intensity: currentIntensity,
                coolness: currentCoolness,
                sim: currentSim,
                commentFont: currentCommentFont,
                mapZoom: currentMapZoom,
                mapEnabled: currentMapEnabled,
                comment: currentComment,
                poiGenre: currentGenre,
                poiCount: currentCount,
                showPlaceName: currentShowPlaceName,
                showCoordinates: currentShowCoordinates,
                showDateTime: currentShowDateTime,
                infoOnRight: currentInfoOnRight
            )
            await MainActor.run {
                if let result {
                    lastThumbnail = result
                }
                isSaving = false
            }
        }
    }
}

#Preview {
    ContentView()
}
