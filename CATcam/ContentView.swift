import SwiftUI
import AVFoundation
import CoreLocation

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var nearbyManager = NearbyPlacesManager()
    /// Vision による猫検出(プレビューの頭数バッジ + 焼き込み用)
    @StateObject private var catDetector = CatDetector()
    /// 猫を振り向かせる呼び鈴(合成音を再生)
    @StateObject private var catCaller = CatCaller()

    /// ポラロイドモード(デフォルト ON、切替状態は永続化)
    @AppStorage("polaroid") private var polaroid = true
    /// 地図表示オン/オフ(永続化)
    @AppStorage("mapEnabled") private var mapEnabled = true
    @State private var intensity = 0.8
    @State private var lastThumbnail: UIImage?
    @State private var isSaving = false
    @State private var flashOpacity = 0.0

    /// ライブプレビュー用の国境アウトライン地図
    @State private var mapImage: UIImage?
    /// 地図を最後に生成した位置(10km 以上動いたら再生成)
    @State private var mapImageLocation: CLLocation?
    /// 地図を最後に生成したズーム倍率(変化したら再生成)
    @State private var mapImageZoom: Double?

    /// 地図ズーム倍率(デフォルトでややズーム)
    @AppStorage("mapZoom") private var mapZoom = 2.5

    /// ヘルプシート表示フラグ
    @State private var showHelp = false
    /// 初回起動判定(一度でも表示済みなら true)
    @AppStorage("hasSeenHelp") private var hasSeenHelp = false

    /// 近くのスポット設定シート表示フラグ
    @State private var showPOISettings = false
    /// 近くのスポットのジャンル(永続化、POISettingsView と整合)
    @AppStorage("poiGenre") private var poiGenreRaw = POIGenre.food.rawValue
    /// 近くのスポットの表示件数(永続化)
    @AppStorage("poiCount") private var poiCount = 3

    /// 写真に焼き込むコメント(撮影後も自動クリアしない)
    @State private var commentText = ""

    /// 呼び鈴で選択中のサウンド(永続化)
    @AppStorage("catSound") private var catSoundRaw = CatCaller.Sound.squeak.rawValue
    /// rawValue → Sound 変換
    private var catSound: CatCaller.Sound { CatCaller.Sound(rawValue: catSoundRaw) ?? .squeak }

    /// 現在のジャンル(rawValue → enum)
    private var poiGenre: POIGenre { POIGenre(rawValue: poiGenreRaw) ?? .food }

    /// ピンチ開始時の基準倍率(ジェスチャ中のみ非 nil)
    @State private var gestureBaseZoom: Double?
    /// ピンチ中の連打デバウンス用の直前生成 Task
    @State private var mapRenderTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                preview
                    .frame(maxWidth: .infinity)
                    .aspectRatio(polaroid ? 1.12 / 1.30 : 3.0 / 4.0, contentMode: .fit)
                    .clipped()
                    .animation(.easeInOut(duration: 0.2), value: polaroid)
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
                    .overlay(alignment: .top) {
                        // 猫の頭数バッジ(プレビュー上端中央。ヘルプ/左上 liveOverlay と干渉しない位置)
                        catBadge
                            .padding(.top, 12)
                    }
                    .overlay(alignment: .bottomLeading) {
                        // 呼び鈴ボタン(プレビュー左下。ヘルプ/地図/頭数バッジと干渉しない位置)
                        catCallButton
                            .padding(16)
                    }

                Spacer(minLength: 0)
                controls
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            camera.start()
            // カメラの各フレームを猫検出に渡す(プレビュー/フィルタ経路は変更しない)
            camera.onPixelBuffer = { catDetector.process($0) }
            locationManager.start()
            // 国境データを先読み
            Task.detached { CountryShapes.shared.loadIfNeeded() }
            // 初回起動時にヘルプを自動表示
            if !hasSeenHelp {
                hasSeenHelp = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showHelp = true }
            }
        }
        .sheet(isPresented: $showHelp) { HelpView() }
        .sheet(isPresented: $showPOISettings) { POISettingsView() }
    }

    // MARK: - Preview

    /// プレビュー本体。ポラロイドモードでは保存写真(composePolaroid)と同じ
    /// 白フチ + 下帯キャプションのレイアウトを再現する。
    /// フラッシュ overlay と位置変化による地図再生成は両モード共通。
    @ViewBuilder
    private var preview: some View {
        Group {
            if polaroid {
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

    /// 通常モード: フルフレームの映像 + 左上の liveOverlay と地図(従来レイアウト)
    private var normalPreview: some View {
        ZStack(alignment: .topLeading) {
            cameraLayer(squareCrop: false)

            // 左上: 焼き込み内容(テキスト + その下に地図)のライブ表示
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 10) {
                    liveOverlay
                    if mapEnabled, let mapImage {
                        Image(uiImage: mapImage)
                            .resizable()
                            .frame(width: geo.size.width * 0.36,
                                   height: geo.size.width * 0.36)
                            // 地図領域だけピンチを受ける
                            .contentShape(Rectangle())
                            .gesture(mapZoomGesture)
                    }
                }
                .padding(16)
            }
        }
    }

    /// ポラロイドモード: composePolaroid と同じ寸法でライブプレビューを構成する。
    /// 全体幅 W に対し photoSide = W / 1.12、margin = photoSide * 0.06。
    /// キャンバス比率 = (side*1.12) : (side*1.30) を aspectRatio(1.12/1.30) で枠に収める。
    private var polaroidPreview: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let photoSide = totalWidth / 1.12
            let margin = photoSide * 0.06
            let mapSide = photoSide * 0.34
            let mapPad = photoSide * 0.05

            VStack(alignment: .leading, spacing: 0) {
                // 上部: 上・左・右 margin の白フチ内に正方形カメラ映像。
                // 映像左上に地図を重ね、ピンチズームを維持する。
                ZStack(alignment: .topLeading) {
                    cameraLayer(squareCrop: true)
                        .frame(width: photoSide, height: photoSide)
                        .clipped()

                    // 地図 + その下に近くのスポット(composePolaroid と同じ配置)
                    VStack(alignment: .leading, spacing: photoSide * 0.012) {
                        if mapEnabled, let mapImage {
                            Image(uiImage: mapImage)
                                .resizable()
                                .frame(width: mapSide, height: mapSide)
                                .contentShape(Rectangle())
                                .gesture(mapZoomGesture)
                        }
                        polaroidPlaces(photoSide: photoSide)
                    }
                    .offset(x: mapPad, y: mapPad)
                }
                .padding(.top, margin)
                .padding(.horizontal, margin)

                // 下帯キャプション
                polaroidCaption(photoSide: photoSide)
                    .padding(.leading, margin + photoSide * 0.008)
                    .padding(.top, photoSide * 0.03)

                Spacer(minLength: 0)
            }
            .frame(width: totalWidth, height: geo.size.height, alignment: .topLeading)
            .background(Color(white: 0.97))
        }
    }

    /// composePolaroid の下帯テキスト 3 行(地名コード / 📍地名 / 日時 + 座標)。
    /// フォントサイズは photoSide 基準で composePolaroid (64/36/27 * side/1000) と一致。
    @ViewBuilder
    private func polaroidCaption(photoSide: CGFloat) -> some View {
        let ink = Color(white: 0.22)
        let hasComment = !commentText.isEmpty
        // コメント有無で composePolaroid に合わせてフォントサイズを切り替える
        let codeRatio: CGFloat = hasComment ? 0.056 : 0.064
        let placeRatio: CGFloat = hasComment ? 0.030 : 0.036
        let subtitleRatio: CGFloat = hasComment ? 0.024 : 0.027
        VStack(alignment: .leading, spacing: photoSide * 0.01) {
            if let code = PhotoRenderer.placeCode(from: locationManager.placeName) {
                Text(code)
                    .font(.system(size: photoSide * codeRatio, weight: .heavy))
                    .foregroundStyle(ink)
            }
            if hasComment {
                Text(commentText)
                    .font(.system(size: photoSide * 0.032, weight: .bold))
                    .foregroundStyle(ink)
            }
            if !locationManager.placeName.isEmpty {
                Text("📍 \(locationManager.placeName)")
                    .font(.system(size: photoSide * placeRatio, weight: .bold))
                    .foregroundStyle(ink)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(captionSubtitle(date: context.date))
                    .font(.system(size: photoSide * subtitleRatio, weight: .regular, design: .monospaced))
                    .foregroundStyle(ink.opacity(0.65))
            }
        }
    }

    /// 写真上(地図の下)の近くのスポット表示(composePolaroid の配置に対応)。
    @ViewBuilder
    private func polaroidPlaces(photoSide: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: photoSide * 0.006) {
            ForEach(nearbyManager.places.prefix(6).map(\.display), id: \.self) { place in
                Text("・" + place)
                    .font(.system(size: photoSide * 0.026, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                    .lineLimit(1)
            }
        }
    }

    /// 下帯3行目: 日時 +(座標があれば)"   " + 座標。composePolaroid と同一の組み立て。
    private func captionSubtitle(date: Date) -> String {
        var subtitle = PhotoRenderer.displayDateFormatter.string(from: date)
        if let coordinate = locationManager.location?.coordinate {
            subtitle += "   " + coordinate.displayString
        }
        return subtitle
    }

    /// カメラ映像 or 権限メッセージ。両モード共通。
    @ViewBuilder
    private func cameraLayer(squareCrop: Bool) -> some View {
        switch camera.status {
        case .denied:
            permissionMessage("カメラへのアクセスが許可されていません。\n設定アプリから許可してください。")
        case .failed:
            permissionMessage("カメラを起動できませんでした。")
        default:
            MetalPreviewView(camera: camera,
                             intensity: intensity,
                             squareCrop: squareCrop)
        }
    }

    /// 地図ピンチズーム。開始時の倍率を基準に 1...8 へクランプし、その都度再生成。
    private var mapZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let base = gestureBaseZoom ?? mapZoom
                if gestureBaseZoom == nil { gestureBaseZoom = base }
                mapZoom = min(max(base * value, 1), 8)
                updateMapImageIfNeeded()
            }
            .onEnded { _ in
                gestureBaseZoom = nil
            }
    }

    /// 撮影結果に焼き込まれる内容のライブ表示
    private var liveOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let code = PhotoRenderer.placeCode(from: locationManager.placeName) {
                Text(code)
                    .font(.system(size: 34, weight: .heavy))
            }
            if !commentText.isEmpty {
                Text(commentText)
                    .font(.system(size: 20, weight: .heavy))
            }
            if !locationManager.placeName.isEmpty {
                Text("📍 \(locationManager.placeName)")
                    .font(.system(size: 15, weight: .bold))
            }
            if let coordinate = locationManager.location?.coordinate {
                Text(coordinate.displayString)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(PhotoRenderer.displayDateFormatter.string(from: context.date))
                    .font(.system(size: 13, weight: .medium))
            }
            // 近くのスポット(日時の下)
            ForEach(nearbyManager.places.map(\.display), id: \.self) { place in
                Text("・\(place)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
    }

    /// 猫の頭数バッジ。検出時のみ表示。レトロ調(白文字+影、半透明の暗い角丸背景)。
    @ViewBuilder
    private var catBadge: some View {
        if catDetector.catCount > 0 {
            Text("🐾 \(catDetector.catCount)")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .animation(.easeInOut(duration: 0.2), value: catDetector.catCount)
        }
    }

    /// 呼び鈴ボタン。タップで選択中サウンドを再生、長押しメニューで3種から切替。
    /// レトロ調(半透明の暗い角丸 + 白アイコン+影)。アイコンは選択中サウンドの symbol。
    private var catCallButton: some View {
        Menu {
            // メニューから鳴らすサウンドを選択(永続化)
            Picker("呼び鈴の音", selection: $catSoundRaw) {
                ForEach(CatCaller.Sound.allCases) { sound in
                    Label(sound.label, systemImage: sound.symbol)
                        .tag(sound.rawValue)
                }
            }
        } label: {
            Image(systemName: catSound.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                .frame(width: 48, height: 48)
                .background(Color.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } primaryAction: {
            // タップ(プライマリアクション)で選択中サウンドを再生
            Haptics.tick()
            catCaller.play(catSound)
        }
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
            lensRow

            commentField

            HStack(spacing: 12) {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(.white.opacity(0.7))
                Slider(value: $intensity, in: 0...1)
                    .tint(.white)
                Text(String(format: "%.0f%%", intensity * 100))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 46, alignment: .trailing)
            }
            .padding(.horizontal, 28)

            HStack {
                thumbnail
                    .frame(width: 56, height: 56)

                Spacer()

                shutterButton

                Spacer()

                Button {
                    Haptics.tick()
                    polaroid.toggle()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: polaroid ? "square.fill" : "square")
                            .font(.system(size: 26))
                        Text("Polaroid")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(polaroid ? .yellow : .white)
                    .frame(width: 56, height: 56)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    /// 写真に焼き込むコメント入力欄(ダーク調、入力時のみクリアボタン表示)
    private var commentField: some View {
        HStack(spacing: 8) {
            TextField("", text: $commentText, prompt:
                Text("コメント(写真に焼き込み)")
                    .foregroundColor(.white.opacity(0.4)))
                .foregroundStyle(.white)
                .submitLabel(.done)

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

    /// レンズ切替 + 地図トグルの水平選択行
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

            lensButton(.back1x, label: "1x")
            lensButton(.back3x, label: "3x")
            lensButton(.back5x, label: "5x")
            lensButton(.front, systemImage: "arrow.triangle.2.circlepath.camera")

            Spacer(minLength: 0)

            // 近くのスポット設定(行の右端、地図トグルと同様のカプセル)
            Button {
                Haptics.tick()
                showPOISettings = true
            } label: {
                Image(systemName: "fork.knife")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(poiGenre == .none ? .white : .yellow)
                    .frame(width: 40, height: 32)
                    .background(Color.white.opacity(poiGenre == .none ? 0.18 : 0.0))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 28)
    }

    /// 小さいカプセル状のレンズ選択ボタン。選択中は白背景・黒文字。
    @ViewBuilder
    private func lensButton(_ lens: CameraManager.Lens,
                            label: String? = nil,
                            systemImage: String? = nil) -> some View {
        let selected = camera.currentLens == lens
        Button {
            Haptics.tick()
            camera.select(lens)
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                } else if let label {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(selected ? .black : .white.opacity(0.9))
            .frame(width: 44, height: 32)
            .background(selected ? Color.white : Color.white.opacity(0.18))
            .clipShape(Capsule())
        }
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

    /// タップで写真アプリを開く
    private var thumbnail: some View {
        Button {
            Haptics.tick()
            if let url = URL(string: "photos-redirect://") {
                UIApplication.shared.open(url)
            }
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

        let options = CaptureOptions(polaroid: polaroid,
                                     intensity: intensity,
                                     location: locationManager.location,
                                     placeName: locationManager.placeName,
                                     date: Date(),
                                     mapZoom: mapZoom,
                                     mapEnabled: mapEnabled,
                                     comment: commentText,
                                     nearbyPlaces: nearbyManager.places.map(\.display),
                                     catCount: catDetector.catCount)

        camera.capturePhoto { photo in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let data = PhotoRenderer.shared.render(photo: photo, options: options) else {
                    DispatchQueue.main.async { isSaving = false }
                    return
                }
                let thumbnail = UIImage(data: data)
                PhotoSaver.save(data, location: options.location) { _ in
                    lastThumbnail = thumbnail
                    isSaving = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
