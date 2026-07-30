#!/usr/bin/env python3
"""Upload the App Store review screenshot to each tip-jar in-app purchase.

Apple requires one review screenshot per IAP showing where the purchase
happens. All four tiers live on the same tip jar screen, so a single capture is
uploaded to all four.

App Store Connect uses a three-step asset flow:
    1. POST  reserve the asset -> returns uploadOperations
    2. PUT   the bytes to each operation's url (may be chunked by offset)
    3. PATCH uploaded=true + sourceFileChecksum (md5) to commit

Usage:
    python3 scripts/upload-iap-screenshots.py path/to/TipJar.png
"""

import hashlib
import os
import sys
import time
from datetime import datetime, timedelta

import httpx
import jwt

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.msdrigg.roam"
SUFFIXES = ["tip.coffee", "tip.latte", "tip.lunch", "tip.dinner"]


def token():
    key_id = os.environ.get("APPSTORECONNECT_API_KEY")
    issuer = os.environ.get("APPSTORECONNECT_API_ISSUER")
    if not key_id or not issuer:
        sys.exit("Set APPSTORECONNECT_API_KEY and APPSTORECONNECT_API_ISSUER.")
    with open(os.path.expanduser(f"~/.private_keys/AuthKey_{key_id}.p8")) as handle:
        key = handle.read()
    exp = int(time.mktime((datetime.now() + timedelta(minutes=20)).timetuple()))
    return jwt.encode(
        {"iss": issuer, "exp": exp, "aud": "appstoreconnect-v1"},
        key,
        headers={"kid": key_id, "typ": "JWT"},
        algorithm="ES256",
    )


def upload_one(client, iap_id, product_id, path, blob):
    # An IAP holds at most one review screenshot; replace any existing one so
    # re-running after a UI tweak doesn't 409.
    existing = client.get(f"/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot")
    if existing.status_code < 300 and existing.json().get("data"):
        old_id = existing.json()["data"]["id"]
        client.delete(f"/v1/inAppPurchaseAppStoreReviewScreenshots/{old_id}")
        print(f"  {product_id}: removed previous screenshot")

    reserve = client.post(
        "/v1/inAppPurchaseAppStoreReviewScreenshots",
        json={
            "data": {
                "type": "inAppPurchaseAppStoreReviewScreenshots",
                "attributes": {
                    "fileName": os.path.basename(path),
                    "fileSize": len(blob),
                },
                "relationships": {
                    "inAppPurchaseV2": {
                        "data": {"type": "inAppPurchases", "id": iap_id}
                    }
                },
            }
        },
    )
    if reserve.status_code >= 300:
        return f"reserve FAILED {reserve.status_code} {reserve.text[:300]}"

    asset = reserve.json()["data"]
    asset_id = asset["id"]

    for op in asset["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        chunk = blob[op["offset"] : op["offset"] + op["length"]]
        put = httpx.request(op["method"], op["url"], content=chunk, headers=headers, timeout=300)
        if put.status_code >= 300:
            return f"upload FAILED {put.status_code} {put.text[:200]}"

    commit = client.patch(
        f"/v1/inAppPurchaseAppStoreReviewScreenshots/{asset_id}",
        json={
            "data": {
                "type": "inAppPurchaseAppStoreReviewScreenshots",
                "id": asset_id,
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
                },
            }
        },
    )
    if commit.status_code >= 300:
        return f"commit FAILED {commit.status_code} {commit.text[:300]}"
    return "uploaded"


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    with open(path, "rb") as handle:
        blob = handle.read()
    print(f"{path} ({len(blob) / 1024:.0f} KB)")

    client = httpx.Client(
        base_url=BASE, headers={"Authorization": f"Bearer {token()}"}, timeout=120
    )
    app_id = client.get("/v1/apps", params={"filter[bundleId]": BUNDLE_ID}).json()["data"][0]["id"]
    iaps = client.get(f"/v1/apps/{app_id}/inAppPurchasesV2", params={"limit": 200}).json()
    by_product = {d["attributes"]["productId"]: d["id"] for d in iaps.get("data", [])}

    for suffix in SUFFIXES:
        product_id = f"{BUNDLE_ID}.{suffix}"
        iap_id = by_product.get(product_id)
        if not iap_id:
            print(f"{product_id}: MISSING")
            continue
        print(f"{product_id}: {upload_one(client, iap_id, product_id, path, blob)}")

    # Re-read state so the caller can see whether MISSING_METADATA cleared.
    after = client.get(f"/v1/apps/{app_id}/inAppPurchasesV2", params={"limit": 200}).json()
    print("\nstate after upload:")
    for d in after.get("data", []):
        if "tip" in d["attributes"]["productId"]:
            print(f"  {d['attributes']['productId']}: {d['attributes'].get('state')}")


if __name__ == "__main__":
    main()
