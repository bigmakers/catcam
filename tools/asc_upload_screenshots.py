#!/usr/bin/env python3
"""App Store Connect API でスクリーンショットをアップロードする。

使い方:
  ASC_ISSUER=... ASC_KEY_ID=... ASC_P8=... python3 tools/asc_upload_screenshots.py \
    <APP_ID> <DISPLAY_TYPE> <file1.png> [file2.png ...]

DISPLAY_TYPE 例: APP_IPHONE_65 (1284x2778), APP_IPHONE_67 (1290x2796),
                 APP_IPAD_PRO_3GEN_129 (2048x2732 / 2064x2752)

フロー: 提出準備中バージョン取得 → ja ローカリゼーション → スクリーンショットセット
get-or-create → 予約作成 → バイナリ PUT → md5 でコミット。
"""
import hashlib
import json
import os
import ssl
import sys
import time
import urllib.request
import urllib.error

import certifi
import jwt  # PyJWT

BASE = "https://api.appstoreconnect.apple.com"
SSL_CTX = ssl.create_default_context(cafile=certifi.where())


def token() -> str:
    with open(os.environ["ASC_P8"]) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER"], "iat": now, "exp": now + 1200,
         "aud": "appstoreconnect-v1"},
        key, algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def api(method, path, body=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
    )
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, context=SSL_CTX) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or "{}")


def die(msg, detail=None):
    print("❌", msg)
    if detail:
        print(json.dumps(detail, ensure_ascii=False, indent=2)[:2000])
    sys.exit(1)


def main():
    app_id, display_type, files = sys.argv[1], sys.argv[2], sys.argv[3:]
    if not files:
        die("ファイルを指定してください")

    # 1. 提出準備中のバージョン
    status, data = api("GET", f"/v1/apps/{app_id}/appStoreVersions"
                              "?filter[appStoreState]=PREPARE_FOR_SUBMISSION&limit=1")
    if status != 200 or not data.get("data"):
        die("提出準備中バージョンが見つからない", data)
    version_id = data["data"][0]["id"]
    print(f"バージョン: {version_id}")

    # 2. ja ローカリゼーション
    status, data = api("GET", f"/v1/appStoreVersions/{version_id}"
                              "/appStoreVersionLocalizations?limit=10")
    if status != 200 or not data.get("data"):
        die("ローカリゼーションが見つからない", data)
    loc = next((d for d in data["data"] if d["attributes"]["locale"].startswith("ja")),
               data["data"][0])
    loc_id = loc["id"]
    print(f"ロケール: {loc['attributes']['locale']} ({loc_id})")

    # 3. スクリーンショットセット get-or-create
    status, data = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}"
                              "/appScreenshotSets?limit=50")
    sets = {d["attributes"]["screenshotDisplayType"]: d["id"]
            for d in data.get("data", [])}
    if display_type in sets:
        set_id = sets[display_type]
        print(f"既存セット: {set_id}")
    else:
        status, data = api("POST", "/v1/appScreenshotSets", {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {"appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}},
            }})
        if status not in (200, 201):
            die("セット作成失敗", data)
        set_id = data["data"]["id"]
        print(f"セット作成: {set_id}")

    # 4. 各ファイル: 予約 → PUT → コミット
    for path in files:
        name = os.path.basename(path)
        blob = open(path, "rb").read()
        status, data = api("POST", "/v1/appScreenshots", {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": name, "fileSize": len(blob)},
                "relationships": {"appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": set_id}}},
            }})
        if status not in (200, 201):
            die(f"{name}: 予約作成失敗", data)
        shot = data["data"]
        shot_id = shot["id"]

        for op in shot["attributes"]["uploadOperations"]:
            chunk = blob[op["offset"]:op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], data=chunk,
                                         method=op["method"])
            for h in op.get("requestHeaders", []):
                req.add_header(h["name"], h["value"])
            with urllib.request.urlopen(req, context=SSL_CTX) as resp:
                if resp.status not in (200, 201, 204):
                    die(f"{name}: バイナリアップロード失敗 HTTP {resp.status}")

        status, data = api("PATCH", f"/v1/appScreenshots/{shot_id}", {
            "data": {
                "type": "appScreenshots",
                "id": shot_id,
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
                },
            }})
        if status != 200:
            die(f"{name}: コミット失敗", data)
        print(f"✅ {name} アップロード完了 ({len(blob)} bytes)")

    print("🎉 すべて完了")


if __name__ == "__main__":
    main()
