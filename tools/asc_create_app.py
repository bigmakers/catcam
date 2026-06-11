#!/usr/bin/env python3
"""App Store Connect API で App レコードを作成するヘルパー。

秘密情報はソースに置かず、環境変数で渡す:
  ASC_ISSUER  … Issuer ID
  ASC_KEY_ID  … Key ID
  ASC_P8      … AuthKey_*.p8 のパス

使い方:
  ASC_ISSUER=... ASC_KEY_ID=... ASC_P8=... \
    python3 tools/asc_create_app.py check
  ... python3 tools/asc_create_app.py create "MapCam" "com.harasaki.MapCam" "mapcam-001" ja
"""
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
    issuer = os.environ["ASC_ISSUER"]
    key_id = os.environ["ASC_KEY_ID"]
    p8 = os.environ["ASC_P8"]
    with open(p8) as f:
        private_key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def api(method: str, path: str, body=None):
    url = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, context=SSL_CTX) as resp:
            return resp.status, json.loads(resp.read() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or "{}")


def find_bundle_id(identifier: str):
    status, data = api(
        "GET", f"/v1/bundleIds?filter[identifier]={identifier}&limit=200"
    )
    if status != 200:
        return None, (status, data)
    for item in data.get("data", []):
        if item["attributes"]["identifier"] == identifier:
            return item["id"], None
    return None, None


def main():
    if len(sys.argv) < 2:
        print("usage: check | create <name> <bundleIdentifier> <sku> <locale>")
        sys.exit(2)

    cmd = sys.argv[1]

    if cmd == "check":
        identifier = sys.argv[2] if len(sys.argv) > 2 else "com.harasaki.MapCam"
        bid, err = find_bundle_id(identifier)
        if err:
            print("API エラー:", err)
            sys.exit(1)
        if bid:
            print(f"OK: Bundle ID '{identifier}' は登録済み (resource id: {bid})")
        else:
            print(f"NG: Bundle ID '{identifier}' が App Store Connect に未登録")
            sys.exit(1)

    elif cmd == "seeds":
        status, data = api("GET", "/v1/bundleIds?limit=8&fields[bundleIds]=identifier,seedId,name")
        if status != 200:
            print("API エラー:", (status, data))
            sys.exit(1)
        for item in data.get("data", []):
            a = item["attributes"]
            print(f"  seedId={a.get('seedId')}  {a.get('identifier')}  ({a.get('name')})")

    elif cmd == "create-bundle":
        identifier, name = sys.argv[2], sys.argv[3]
        body = {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": identifier,
                    "name": name,
                    "platform": "IOS",
                },
            }
        }
        status, data = api("POST", "/v1/bundleIds", body)
        if status in (200, 201):
            print(f"✅ Bundle ID 作成: {identifier} (id: {data['data']['id']}, seedId: {data['data']['attributes'].get('seedId')})")
        else:
            print(f"Bundle ID 作成失敗 (HTTP {status}):")
            print(json.dumps(data, ensure_ascii=False, indent=2))
            sys.exit(1)

    elif cmd == "create":
        name, identifier, sku, locale = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
        bid, err = find_bundle_id(identifier)
        if err:
            print("API エラー:", err)
            sys.exit(1)
        if not bid:
            print(f"NG: Bundle ID '{identifier}' 未登録。先に登録が必要")
            sys.exit(1)
        body = {
            "data": {
                "type": "apps",
                "attributes": {
                    "name": name,
                    "primaryLocale": locale,
                    "sku": sku,
                },
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bid}}
                },
            }
        }
        status, data = api("POST", "/v1/apps", body)
        if status in (200, 201):
            app = data["data"]
            print(f"✅ App 作成成功: {app['attributes']['name']} (id: {app['id']})")
        else:
            print(f"作成失敗 (HTTP {status}):")
            print(json.dumps(data, ensure_ascii=False, indent=2))
            sys.exit(1)

    else:
        print("unknown command:", cmd)
        sys.exit(2)


if __name__ == "__main__":
    main()
