#!/usr/bin/env python3
"""Create the four tip-jar in-app purchases in App Store Connect.

Deliberately worded as a "tip"/"support" everywhere, never a "donation":
guideline 3.2.2(iv) forbids collecting funds for charities in-app unless you
are an approved nonprofit, and reviewers go by the display name and metadata.

Credentials follow the same convention as the other scripts in this directory:
    APPSTORECONNECT_API_KEY / APPSTORECONNECT_API_ISSUER, with the .p8 in
    ~/.private_keys/AuthKey_<key id>.p8

Idempotent: an IAP whose productId already exists is skipped, not duplicated.
"""

import os
import sys
import time
from datetime import datetime, timedelta

import httpx
import jwt

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.msdrigg.roam"

# (productId suffix, reference name, customer-facing name, USD price)
TIERS = [
    ("tip.coffee", "Tip - Black Coffee", "Black Coffee", "3.00"),
    ("tip.latte", "Tip - Latte", "Latte", "5.00"),
    ("tip.lunch", "Tip - Lunch", "Lunch", "10.00"),
    ("tip.dinner", "Tip - Dinner", "Dinner", "20.00"),
]

REVIEW_NOTE = (
    "Optional tip supporting development of this free app. Any tier unlocks the "
    "same cosmetic extras (custom accent colours and alternate app icons). "
    "No functional feature is gated. Reachable from Settings > Buy me a coffee."
)


def token():
    key_id = os.environ.get("APPSTORECONNECT_API_KEY")
    issuer = os.environ.get("APPSTORECONNECT_API_ISSUER")
    if not key_id or not issuer:
        sys.exit(
            "Set APPSTORECONNECT_API_KEY and APPSTORECONNECT_API_ISSUER.\n"
            "Per scripts/export.py the working pair is ZWF866Z497 / "
            "cbcdbb0a-aae2-46de-af95-4700664fad72."
        )
    key_path = os.path.expanduser(f"~/.private_keys/AuthKey_{key_id}.p8")
    with open(key_path) as handle:
        key = handle.read()
    exp = int(time.mktime((datetime.now() + timedelta(minutes=20)).timetuple()))
    return jwt.encode(
        {"iss": issuer, "exp": exp, "aud": "appstoreconnect-v1"},
        key,
        headers={"kid": key_id, "typ": "JWT"},
        algorithm="ES256",
    )


def main():
    client = httpx.Client(
        base_url=BASE,
        headers={"Authorization": f"Bearer {token()}"},
        timeout=60,
    )

    apps = client.get("/v1/apps", params={"filter[bundleId]": BUNDLE_ID}).json()
    if not apps.get("data"):
        sys.exit(f"No app found for bundle id {BUNDLE_ID}: {apps}")
    app_id = apps["data"][0]["id"]
    print(f"app id {app_id}")

    existing = client.get(
        f"/v1/apps/{app_id}/inAppPurchasesV2", params={"limit": 200}
    ).json()
    have = {
        item["attributes"]["productId"]: item["id"]
        for item in existing.get("data", [])
    }

    for suffix, ref_name, display_name, price in TIERS:
        product_id = f"{BUNDLE_ID}.{suffix}"
        if product_id in have:
            print(f"skip {product_id} (already exists, id {have[product_id]})")
            continue

        payload = {
            "data": {
                "type": "inAppPurchases",
                "attributes": {
                    "name": ref_name,
                    "productId": product_id,
                    "inAppPurchaseType": "NON_CONSUMABLE",
                    "reviewNote": REVIEW_NOTE,
                    "familySharable": False,
                },
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}}
                },
            }
        }
        response = client.post("/v2/inAppPurchases", json=payload)
        if response.status_code >= 300:
            print(f"FAILED {product_id}: {response.status_code} {response.text}")
            continue
        iap_id = response.json()["data"]["id"]
        print(f"created {product_id} -> {iap_id}  (needs ${price} price + localization)")

    print(
        "\nNext, in App Store Connect (or a follow-up script):\n"
        "  - add an en-US localization (display name + description) per IAP\n"
        "  - set the price tier, then submit each IAP for review\n"
        "Display names must say tip/support, never 'donation'."
    )


if __name__ == "__main__":
    main()
