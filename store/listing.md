# App Store 掲載情報(草案)

App Store Connect に貼り付ける用のメタデータ草案。文字数制限はカッコ内。
そのまま使えるが、固有名(メール・URL)は確定後に差し替えること。

---

## 基本情報

| 項目 | 値 |
|---|---|
| App 名(30字) | **MapCam** ※重複時の候補 → 「MapCam – Travel GPS Camera」 |
| サブタイトル(30字) | 旅を刻む GPS フォトカメラ |
| Bundle ID | com.harasaki.MapCam |
| プライマリカテゴリ | 写真/ビデオ |
| セカンダリカテゴリ | 旅行 |
| 価格 | ¥100 |
| 年齢レーティング | 4+ |
| 著作権 | 2026 Daisaku Harasaki |

> **App 名の注意**: 「MapCam」は一般的な語で他社が取得済みの可能性があります。登録時に弾かれたら上記の候補名(または「MapCam Journey」等)に切り替えてください。

---

## プロモーションテキスト(170字・審査なしで後から変更可)

撮った瞬間に、地名・座標・日付、国境地図、近くのお店までを一枚に焼き込む旅のカメラ。ひとことコメントも添えられます。黒が映えるフィルム調フィルターと真四角のポラロイドモードで、移動の記録が作品になります。

---

## 説明(日本語)

MapCam は、写真に「どこで撮ったか」を美しく刻む GPS カメラです。

旅の途中、空港や車窓から一枚撮るだけで、地名・座標・日時に加えて、現在地を示す国境アウトライン地図が写真に焼き込まれます。近くのお店やスポットの名前と距離も一緒に記録でき、ひとことコメントを添えれば、その瞬間の記憶がまるごと一枚に。

■ 主な機能
・位置情報の焼き込み — 地名(アルファベット表記)・座標・日時を写真に記録。EXIF にも GPS を保存
・国境アウトライン地図 — 現在地と国境線を表示。ピンチで 1〜8 倍ズーム、ワンタップで非表示にも
・近くのスポット — 撮影地点の近くのお店などの名前と距離を焼き込み。ジャンルと件数(1〜6件)を選べます
・コメント — 入力した文字が写真の見出しの下にタイポグラフィとして入ります
・黒が引き立つフィルム調フィルター — 強度をスライダーで自由に調整
・Polaroid モード — 真四角・白フチのポラロイド風
・レンズ切替 — 1x / 3x / 5x / 前面カメラ

■ プライバシー
撮影した写真と位置情報は、すべてあなたの端末内で処理されます。開発者のサーバーに送信されることはなく、トラッキングも広告もありません。近くのスポット検索には Apple のマップサービスを利用します。

旅の記憶を、地図ごと持ち帰ろう。

---

## 説明(English)

MapCam is a GPS camera that beautifully stamps "where you were" onto every photo.

Snap a shot from an airport or a train window, and MapCam stamps the place name, coordinates, date, and a country-outline map of your location right onto the image. It can also list nearby places with their distances, and a one-line comment of yours becomes part of the typography.

Features
- Location stamping — place name, coordinates, and date on the photo, plus GPS in EXIF
- Country outline map — your location and borders, with 1–8x pinch zoom, one tap to hide
- Nearby places — names and distances of spots around you, with genre and count (1–6) options
- Comment — your words placed under the headline as typography
- Black-forward film filter — adjust the intensity with a slider
- Polaroid mode — square photos with a white border
- Lens switch — 1x / 3x / 5x / front camera

Privacy
Your photos and location are processed entirely on your device. Nothing is sent to the developer's servers — no tracking, no ads. Nearby place search uses Apple's Maps service.

Bring your travel memories home, map and all.

---

## キーワード(100字・カンマ区切り、スペース無しが効率的)

GPS,カメラ,位置情報,地図,旅,旅行,写真,フィルム,ポラロイド,exif,travel,map,location,film,polaroid

---

## URL(GitHub Pages 公開後に確定)

- サポート URL: https://bigmakers.github.io/mapcam/
- プライバシーポリシー URL: https://bigmakers.github.io/mapcam/privacy.html
- マーケティング URL(任意): (空欄可)

---

## App プライバシー申告(App Store Connect の設問への回答)

- **データを収集していますか?** → いいえ(No, we do not collect data)
  - 開発者のサーバーは無く、写真・位置情報はすべて端末内で処理。トラッキング・解析・広告なし。
  - 逆ジオコーディングは Apple の標準機能(開発者によるデータ収集ではない)。
- 結果として「データ収集なし(Data Not Collected)」と表示される。

## 輸出コンプライアンス

- Info.plist に `ITSAppUsesNonExemptEncryption = false` を設定済み。提出時の暗号に関する質問は自動でスキップされる。

## 審査メモ(Review Notes 欄に書くと親切)

このアプリの主要機能(位置情報の焼き込み・地図描画)は位置情報の許可が前提です。審査時は屋外または位置情報シミュレーションを有効にしてご確認ください。アカウント登録やログインは不要です。
