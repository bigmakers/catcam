# App Store 掲載情報(草案)

App Store Connect に貼り付ける用のメタデータ草案。文字数制限はカッコ内。
そのまま使えるが、固有名(メール・URL)は確定後に差し替えること。

---

## 基本情報

| 項目 | 値 |
|---|---|
| App 名(30字) | **CATcam** ※重複時の候補 → 「CATcam – Cat GPS Camera」 |
| サブタイトル(30字) | 猫を数えて記録する GPS カメラ |
| Bundle ID | com.harasaki.CATcam |
| プライマリカテゴリ | 写真/ビデオ |
| セカンダリカテゴリ | ライフスタイル |
| 価格 | ¥100 |
| 年齢レーティング | 4+ |
| 著作権 | 2026 Daisaku Harasaki |

---

## プロモーションテキスト(170字・審査なしで後から変更可)

猫を見つけたら撮るだけ。Vision が自動で頭数を認識し、地名・座標・日付・国境地図とともに一枚に焼き込みます。レトロなフィルム風フィルターとポラロイドモードで、猫との出会いを作品として残せます。

---

## 説明(日本語)

CATcam は、猫を自動で検出・記録しながら「どこで撮ったか」を美しく刻む GPS カメラです。

猫をカメラに向けるだけで、Apple の Vision フレームワークが自動で頭数を認識してプレビューに表示。シャッターを切ると「ここで N 匹見つけた」という記録が、地名・座標・日時・国境アウトライン地図とともに写真に焼き込まれます。近くのスポットの名前と距離も一緒に記録でき、ひとことコメントを添えれば、その瞬間の記憶がまるごと一枚に。

■ 主な機能
・猫を自動検出して頭数を記録 — Vision フレームワークで端末内処理。カメラ映像は外部に送信されません
・位置情報の焼き込み — 地名(アルファベット表記)・座標・日時を写真に記録。EXIF にも GPS を保存
・国境アウトライン地図 — 現在地と国境線を表示。ピンチで 1〜8 倍ズーム、ワンタップで非表示にも
・近くのスポット — 撮影地点の近くのお店などの名前と距離を焼き込み。ジャンルと件数(1〜6件)を選べます
・コメント — 入力した文字が写真の見出しの下にタイポグラフィとして入ります
・レトロ・フィルム風フィルター — 退色プリント調のフィルム感をスライダーで自由に調整
・Polaroid モード — 真四角・白フチのポラロイド風
・レンズ切替 — 1x / 3x / 5x / 前面カメラ

■ プライバシー
猫の検出・写真の撮影・位置情報は、すべてあなたの端末内で処理されます。開発者のサーバーに送信されることはなく、トラッキングも広告もありません。近くのスポット検索には Apple のマップサービスを利用します。

猫との出会いを、地図ごと残そう。

---

## 説明(English)

CATcam is a GPS camera that automatically detects cats and beautifully stamps "where you found them" onto every photo.

Just point the camera at a cat — Apple's Vision framework counts the cats in frame and shows the tally on screen. Press the shutter and "N cats found here" is stamped onto the photo along with the place name, coordinates, date, and a country-outline map. It can also list nearby places with their distances, and a one-line comment of yours becomes part of the typography.

Features
- Cat detection — automatically counts cats using Apple's Vision framework, all on-device
- Location stamping — place name, coordinates, and date on the photo, plus GPS in EXIF
- Country outline map — your location and borders, with 1–8x pinch zoom, one tap to hide
- Nearby places — names and distances of spots around you, with genre and count (1–6) options
- Comment — your words placed under the headline as typography
- Retro film filter — a faded-print film look with adjustable intensity
- Polaroid mode — square photos with a white border
- Lens switch — 1x / 3x / 5x / front camera

Privacy
Cat detection, photos, and location are processed entirely on your device. Nothing is sent to the developer's servers — no tracking, no ads. Nearby place search uses Apple's Maps service.

Log every cat encounter, map and all.

---

## キーワード(100字・カンマ区切り、スペース無しが効率的)

猫,ねこ,cat,動物,GPS,カメラ,位置情報,地図,写真,フィルム,ポラロイド,exif,animal,map,location,film,polaroid

---

## URL

- サポート URL: https://bigmakers.github.io/catcam/
- プライバシーポリシー URL: https://bigmakers.github.io/catcam/privacy.html
- マーケティング URL(任意): (空欄可)

---

## App プライバシー申告(App Store Connect の設問への回答)

- **データを収集していますか?** → いいえ(No, we do not collect data)
  - 開発者のサーバーは無く、猫の検出・写真・位置情報はすべて端末内で処理。トラッキング・解析・広告なし。
  - 逆ジオコーディングおよびスポット検索は Apple の標準機能(開発者によるデータ収集ではない)。
- 結果として「データ収集なし(Data Not Collected)」と表示される。

## 輸出コンプライアンス

- Info.plist に `ITSAppUsesNonExemptEncryption = false` を設定済み。提出時の暗号に関する質問は自動でスキップされる。

## 審査メモ(Review Notes 欄に書くと親切)

このアプリの主要機能(猫の検出・位置情報の焼き込み・地図描画)はカメラと位置情報の許可が前提です。審査時は実機のカメラを使用し、屋外または位置情報シミュレーションを有効にしてご確認ください。アカウント登録やログインは不要です。
