#!/usr/bin/env python3
"""CATcam 2.0(毛並みフィルタ/猫ログ化)の App Store Connect メタデータ設定。

環境変数 ASC_ISSUER / ASC_KEY_ID / ASC_P8 が必要。
  python3 tools/asc_catcam_v2.py apply     # バージョン作成+メタデータ
  python3 tools/asc_catcam_v2.py build     # 処理済みビルドの確認と紐付け
"""
import json
import os
import ssl
import sys
import time
import urllib.request
import urllib.error

import certifi
import jwt

BASE = "https://api.appstoreconnect.apple.com"
SSL_CTX = ssl.create_default_context(cafile=certifi.where())
APP_ID = "6779129846"   # CATcam
VERSION = "2.0"
BUILD_NUMBER = "5"

SUBTITLE = "猫の毛並みを引き立てるGPSカメラ"
KEYWORDS = "猫,ねこ,cat,毛並み,動物,GPS,カメラ,地図,写真,フィルム,ポラロイド,exif,animal,map,film,polaroid"
PROMO = "2.0で全面リニューアル。毛並みフィルタ5種+フィルム11種、アプリ内ギャラリー「猫ログ」、ポラロイド額装、28/52/120mmの3段レンズを搭載しました。"

DESCRIPTION = """CATcam は、猫を撮るためのカメラです。
毛並みを引き立てる5種の「毛並みフィルタ」と11種のフィルムシミュレーションを、撮影画面のダイヤルでその場で切替。プレビューにそのまま反映され、見たままが保存されます。撮った一枚は自動でアプリ内ギャラリー「猫ログ」に記録され、いつどこで出会った猫かをあとから振り返れます。

■ 毛並みフィルタ(5種)
局所コントラストで毛の一本一本の流れを立て、明部の階調で毛艶を際立たせるプリセット群。
・SILVER — 銀・サバトラ向き。寒色で毛並みが立つ
・SMOKE — 灰・ロシアンブルー向き。柔らかい銀毛と豊かな中間調
・TSUYA — 黒猫の艶毛向き。強い毛艶と深い黒
・KURO — 黒猫を重厚に。青灰のトーンで沈める
・CHATORA — 茶トラ・キジトラ向き。赤茶の深みと毛先のハイライト

■ 11種のフィルム
STANDARD / VIVID / SOFT / CLASSIC / NEG. STD / NEG. HI / NOSTALGIC / CINEMA / MONO / MONO+R / SEPIA。
効果の強さ・色温度・粒状感は設定で調整できます。

■ 猫を呼ぶ音
猫を振り向かせる短い音(チュチュ/チチチ/ニャー)をワンタップで再生。目線をもらってからシャッターを切れます。

■ 猫ログ(アプリ内ギャラリー)
撮影・取り込みした一枚を端末内に自動記録。日付と撮影地つきの一覧で、出会った猫を「◯匹ぶん」数えながら振り返れます。外部送信は一切ありません。

■ ポラロイド額装
真四角の写真を白フチで額装し、下帯に地名・コメント・日時を印字。4:3 / 16:9 / 1:1 の通常出力とワンタップで切替できます。

■ 3つの単焦点
28mm / 52mm / 120mm(35mm換算)をワンタップで切替。望遠レンズ搭載機では 120mm は実レンズで撮影します。

■ 地図と地名の焼き込み
・地名・座標・日付・国境/都道府県レベルの地図アウトラインを写真に焼き込み(すべて個別にオン/オフ可、初期状態はオフ)
・近くのスポット名の焼き込みにも対応(OpenPOI API / Apple マップ)
・保存写真の EXIF に GPS を記録

■ そのほか
・プレビュー長押しで Before/After 比較
・コメント焼き込み(明朝/ゴシック、最大10行)
・フォトライブラリの写真を取り込んで同じ加工を適用

■ プライバシー
本アプリはデータを収集しません。写真・位置情報の処理は端末内で完結します(地名取得と近くのスポット検索時のみ、座標が Apple / OpenPOI API に送信されます)。旧バージョンの投稿機能「100日マップ」は 2.0 で終了しました。

※ 各シミュレーション名は本アプリ独自の名称であり、特定のメーカー・フィルム製品とは関係ありません。
"""

WHATS_NEW = """2.0 で全面リニューアルしました。
・毛並みフィルタ5種(SILVER/SMOKE/TSUYA/KURO/CHATORA)を新搭載。局所コントラストで毛並みと毛艶を引き立てます
・フィルムシミュレーション11種を新搭載
・アプリ内ギャラリー「猫ログ」を新設。撮った猫を日付・場所つきで自動記録(端末内のみ)
・ポラロイド額装が復活。4:3/16:9/1:1 とワンタップ切替
・28/52/120mm の3段レンズ切替
・猫を呼ぶ音はそのまま搭載
・投稿機能「100日マップ」は終了しました。アプリはデータを収集しません
"""


def token():
    with open(os.environ["ASC_P8"]) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER"], "iat": now, "exp": now + 1200,
         "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]})


def call(method, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={"Authorization": f"Bearer {token()}",
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, context=SSL_CTX) as r:
            body = r.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} {method} {path}")
        print(e.read().decode()[:2000])
        raise


def get(path):
    return call("GET", path)


def ensure_version():
    vers = get(f"/v1/apps/{APP_ID}/appStoreVersions?filter[versionString]={VERSION}&limit=1")
    if vers["data"]:
        vid = vers["data"][0]["id"]
        print(f"version {VERSION} exists: {vid}")
        return vid
    created = call("POST", "/v1/appStoreVersions", {
        "data": {"type": "appStoreVersions",
                 "attributes": {"platform": "IOS", "versionString": VERSION,
                                "releaseType": "AFTER_APPROVAL"},
                 "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
    vid = created["data"]["id"]
    print(f"created version {VERSION}: {vid}")
    return vid


def set_version_localization(vid):
    locs = get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")
    ja = next((l for l in locs["data"] if l["attributes"]["locale"] == "ja"), None)
    attrs = {
        "description": DESCRIPTION,
        "keywords": KEYWORDS,
        "promotionalText": PROMO,
        "whatsNew": WHATS_NEW,
        "supportUrl": "https://bigmakers.github.io/catcam/",
    }
    if ja:
        call("PATCH", f"/v1/appStoreVersionLocalizations/{ja['id']}", {
            "data": {"type": "appStoreVersionLocalizations", "id": ja["id"],
                     "attributes": attrs}})
        print("ja version localization updated")
    else:
        call("POST", "/v1/appStoreVersionLocalizations", {
            "data": {"type": "appStoreVersionLocalizations",
                     "attributes": {"locale": "ja", **attrs},
                     "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        print("ja version localization created")


def set_app_info():
    infos = get(f"/v1/apps/{APP_ID}/appInfos?include=appInfoLocalizations&fields[appInfoLocalizations]=locale,name,subtitle,privacyPolicyUrl&fields[appInfos]=appStoreState")
    editable = None
    for i in infos["data"]:
        state = i["attributes"].get("appStoreState")
        if state in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
            editable = i["id"]
    if not editable:
        print("no editable appInfo found (states:",
              [i["attributes"].get("appStoreState") for i in infos["data"]], ")")
        return
    print(f"editable appInfo: {editable}")
    for inc in infos.get("included", []):
        if inc["attributes"]["locale"] != "ja":
            continue
        # この localization が editable 側に属すかは PATCH で判定(読み取り専用なら 409)
        try:
            call("PATCH", f"/v1/appInfoLocalizations/{inc['id']}", {
                "data": {"type": "appInfoLocalizations", "id": inc["id"],
                         "attributes": {"subtitle": SUBTITLE}}})
            print(f"subtitle updated on {inc['id']}")
        except urllib.error.HTTPError:
            pass
    # 年齢レーティング: UGC を false へ(100日マップ廃止)
    decl = get(f"/v1/appInfos/{editable}/ageRatingDeclaration")
    did = decl["data"]["id"]
    call("PATCH", f"/v1/ageRatingDeclarations/{did}", {
        "data": {"type": "ageRatingDeclarations", "id": did,
                 "attributes": {"userGeneratedContent": False}}})
    print("ageRatingDeclaration: userGeneratedContent=false")


def attach_build(vid):
    builds = get(f"/v1/builds?filter[app]={APP_ID}&filter[version]={BUILD_NUMBER}&limit=1")
    if not builds["data"]:
        print(f"build {BUILD_NUMBER} not visible yet")
        return False
    b = builds["data"][0]
    state = b["attributes"]["processingState"]
    print(f"build {BUILD_NUMBER}: {state}")
    if state != "VALID":
        return False
    call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", {
        "data": {"type": "builds", "id": b["id"]}})
    print(f"build {BUILD_NUMBER} attached to version {VERSION}")
    return True


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "apply"
    vid = ensure_version()
    if cmd == "apply":
        set_version_localization(vid)
        set_app_info()
    elif cmd == "build":
        attach_build(vid)
