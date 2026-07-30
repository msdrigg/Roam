#!/usr/bin/env python3
"""Add en-US localizations and USD prices to the tip-jar in-app purchases.

Run after create-tip-iaps.py. Idempotent: existing localizations and price
schedules are left alone.

Wording note: display names and descriptions say "tip"/"support" and never
"donation" — guideline 3.2.2(iv) bars in-app collection of funds for charities
unless you are an approved nonprofit, and review goes by the customer-facing
strings.
"""

import os
import sys
import time
from datetime import datetime, timedelta

import httpx
import jwt

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.msdrigg.roam"
USA = "USA"

# productId suffix -> (display name, description, USD customer price)
# App Store Connect caps the description at 45 characters and the name at 30.
TIERS = {
    "tip.coffee": ("Black Coffee", "A small tip. Unlocks colors and icons.", "3.00"),
    "tip.latte": ("Latte", "A tip. Unlocks colors and icons.", "5.00"),
    "tip.lunch": ("Lunch", "A generous tip. Unlocks colors and icons.", "10.00"),
    "tip.dinner": ("Dinner", "A big tip. Unlocks colors and icons.", "20.00"),
}

for _name, _desc, _ in TIERS.values():
    assert len(_desc) <= 45, (_desc, len(_desc))
    assert len(_name) <= 30, (_name, len(_name))


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


def localize(client, iap_id, name, description):
    existing = client.get(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations").json()
    if any(d["attributes"]["locale"] == "en-US" for d in existing.get("data", [])):
        return "localization already present"

    response = client.post(
        "/v1/inAppPurchaseLocalizations",
        json={
            "data": {
                "type": "inAppPurchaseLocalizations",
                "attributes": {"locale": "en-US", "name": name, "description": description},
                "relationships": {
                    "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}
                },
            }
        },
    )
    if response.status_code >= 300:
        return f"localization FAILED {response.status_code} {response.text[:300]}"
    return "localized"


def set_price(client, iap_id, usd):
    existing = client.get(f"/v2/inAppPurchases/{iap_id}/iapPriceSchedule")
    if existing.status_code < 300 and existing.json().get("data"):
        return "price already scheduled"

    # Price points are per-IAP and paginated ascending, so the higher tiers sit
    # well past the first page — walk `links.next` until the match turns up.
    url = f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]={USA}&limit=200"
    match = None
    seen = 0
    while url and not match:
        page = client.get(url).json()
        for point in page.get("data", []):
            seen += 1
            # Apple trims trailing zeros ("3.0", not "3.00"), so compare numerically.
            if float(point["attributes"]["customerPrice"]) == float(usd):
                match = point
                break
        url = page.get("links", {}).get("next")

    if not match:
        return f"no {usd} USD price point found across {seen} points"

    response = client.post(
        "/v1/inAppPurchasePriceSchedules",
        json={
            "data": {
                "type": "inAppPurchasePriceSchedules",
                "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                    "baseTerritory": {"data": {"type": "territories", "id": USA}},
                    "manualPrices": {
                        "data": [{"type": "inAppPurchasePrices", "id": "${price}"}]
                    },
                },
            },
            "included": [
                {
                    "type": "inAppPurchasePrices",
                    "id": "${price}",
                    "attributes": {"startDate": None},
                    "relationships": {
                        "inAppPurchasePricePoint": {
                            "data": {"type": "inAppPurchasePricePoints", "id": match["id"]}
                        }
                    },
                }
            ],
        },
    )
    if response.status_code >= 300:
        return f"price FAILED {response.status_code} {response.text[:300]}"
    return f"priced at ${usd}"


def all_territories(client):
    """Every App Store territory id, paginated."""
    ids, url = [], "/v1/territories?limit=200"
    while url:
        page = client.get(url).json()
        ids += [t["id"] for t in page.get("data", [])]
        url = page.get("links", {}).get("next")
    return ids


def set_availability(client, iap_id, territories):
    """An IAP stays MISSING_METADATA until territory availability exists.

    Note there is no `availableInAllTerritories` shortcut — the API requires
    the boolean `availableInNewTerritories` plus an explicit list of every
    territory in the `availableTerritories` relationship.
    """
    existing = client.get(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseAvailability")
    if existing.status_code < 300 and existing.json().get("data"):
        return "availability already set"

    response = client.post(
        "/v1/inAppPurchaseAvailabilities",
        json={
            "data": {
                "type": "inAppPurchaseAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "inAppPurchase": {
                        "data": {"type": "inAppPurchases", "id": iap_id}
                    },
                    "availableTerritories": {
                        "data": [
                            {"type": "territories", "id": t} for t in territories
                        ]
                    },
                },
            }
        },
    )
    if response.status_code >= 300:
        return f"availability FAILED {response.status_code} {response.text[:250]}"
    return f"available in {len(territories)} territories"


def main():
    client = httpx.Client(
        base_url=BASE, headers={"Authorization": f"Bearer {token()}"}, timeout=60
    )
    territories = all_territories(client)

    apps = client.get("/v1/apps", params={"filter[bundleId]": BUNDLE_ID}).json()
    app_id = apps["data"][0]["id"]

    iaps = client.get(f"/v1/apps/{app_id}/inAppPurchasesV2", params={"limit": 200}).json()
    by_product = {d["attributes"]["productId"]: d["id"] for d in iaps.get("data", [])}

    for suffix, (name, description, usd) in TIERS.items():
        product_id = f"{BUNDLE_ID}.{suffix}"
        iap_id = by_product.get(product_id)
        if not iap_id:
            print(f"{product_id}: MISSING - run create-tip-iaps.py first")
            continue
        print(f"{product_id}: {localize(client, iap_id, name, description)}; "
              f"{set_price(client, iap_id, usd)}; "
              f"{set_availability(client, iap_id, territories)}")

    print("\nstate:")
    after = client.get(f"/v1/apps/{app_id}/inAppPurchasesV2", params={"limit": 200}).json()
    for d in after.get("data", []):
        if "tip" in d["attributes"]["productId"]:
            print(f"  {d['attributes']['productId']}: {d['attributes'].get('state')}")


if __name__ == "__main__":
    main()
