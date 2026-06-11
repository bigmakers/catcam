#!/bin/bash
# 実機(iPhone 14 Pro = 1179x2556 など)で撮ったスクショを、
# App Store の 6.9 インチ枠(1290x2796)に変換する。
#
# 使い方:
#   1. 撮ったスクショ(PNG)を store/screenshots/in/ に入れる
#   2. bash tools/resize_screenshots.sh
#   3. 変換後が store/screenshots/out/ に出る。それを App Store Connect にアップロード
#
# アスペクト比を保ったまま長辺を 2796 に合わせ、足りない分は黒で中央パディングする。
# (iPhone 14 Pro のスクショはこの枠とほぼ同比率なので、ほぼ余白なしで収まる)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IN="$ROOT/store/screenshots/in"
OUT="$ROOT/store/screenshots/out"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# App Store 6.9 インチ枠
W=1290
H=2796
PAD=000000  # パディング色(黒)

mkdir -p "$IN" "$OUT"

shopt -s nullglob nocaseglob
files=("$IN"/*.png "$IN"/*.jpg "$IN"/*.jpeg)
if [ ${#files[@]} -eq 0 ]; then
  echo "⚠️  $IN に画像がありません。スクショ(PNG)を入れてから再実行してください。"
  exit 0
fi

count=0
for f in "${files[@]}"; do
  base="$(basename "${f%.*}")"
  tmp="$TMP/$base.png"
  # 長辺を H に合わせてアスペクト維持で縮小/拡大
  sips -Z "$H" "$f" --out "$tmp" >/dev/null
  # WxH キャンバスに中央配置で黒パディング(はみ出しは中央クロップ)
  sips -p "$H" "$W" --padColor "$PAD" "$tmp" --out "$OUT/$base.png" >/dev/null 2>&1
  dims="$(sips -g pixelWidth -g pixelHeight "$OUT/$base.png" | awk '/pixel/{printf $2" "}')"
  echo "✓ $base.png → ${dims}(${W}x${H} 枠)"
  count=$((count + 1))
done

echo ""
echo "完了: $count 枚を $OUT に出力しました。"
echo "App Store Connect の「6.9インチディスプレイ」スクリーンショット欄にアップロードしてください。"
