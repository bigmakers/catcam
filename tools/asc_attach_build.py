#!/usr/bin/env python3
"""アップロード済みビルドの処理完了を待ち、提出準備中バージョンに紐付ける。

使い方:
  ASC_ISSUER=... ASC_KEY_ID=... ASC_P8=... \
    python3 tools/asc_attach_build.py <APP_ID> <BUILD_VERSION> [timeout_min]
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


def token():
    with open(os.environ["ASC_P8"]) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER"], "iat": now, "exp": now + 1200,
         "aud": "appstoreconnect-v1"},
        key, algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def api(method, path, body=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, context=SSL_CTX) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or "{}")


def main():
    app_id, build_version = sys.argv[1], sys.argv[2]
    timeout_min = int(sys.argv[3]) if len(sys.argv) > 3 else 40

    deadline = time.time() + timeout_min * 60
    build_id = None
    while time.time() < deadline:
        status, data = api(
            "GET",
            f"/v1/builds?filter[app]={app_id}&filter[version]={build_version}"
            "&sort=-uploadedDate&limit=1")
        items = data.get("data", [])
        if items:
            state = items[0]["attributes"]["processingState"]
            print(f"[{time.strftime('%H:%M:%S')}] build {build_version}: {state}", flush=True)
            if state == "VALID":
                build_id = items[0]["id"]
                break
            if state in ("FAILED", "INVALID"):
                print("❌ ビルド処理が失敗しました")
                sys.exit(1)
        else:
            print(f"[{time.strftime('%H:%M:%S')}] ビルドはまだ ASC に現れていません", flush=True)
        time.sleep(60)

    if not build_id:
        print("❌ タイムアウト: ビルドが VALID になりませんでした")
        sys.exit(1)

    status, data = api(
        "GET",
        f"/v1/apps/{app_id}/appStoreVersions"
        "?filter[appStoreState]=PREPARE_FOR_SUBMISSION&limit=1")
    if status != 200 or not data.get("data"):
        print("❌ 提出準備中バージョンが見つかりません", data)
        sys.exit(1)
    version_id = data["data"][0]["id"]

    status, data = api(
        "PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build",
        {"data": {"type": "builds", "id": build_id}})
    if status in (200, 204):
        print(f"✅ ビルド {build_version} ({build_id}) をバージョンに紐付けました")
    else:
        print(f"❌ 紐付け失敗 (HTTP {status})")
        print(json.dumps(data, ensure_ascii=False, indent=2)[:1500])
        sys.exit(1)


if __name__ == "__main__":
    main()
