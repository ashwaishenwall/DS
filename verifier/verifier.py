#!/usr/bin/env python3
import argparse
import os
import sys
import time
import uuid
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def fail(message):
    print(f"VERIFICATION FAILED: {message}", file=sys.stderr)
    raise SystemExit(1)

def wait_for(url, timeout, total_wait):
    deadline = time.time() + total_wait
    while time.time() < deadline:
        try:
            r = requests.get(url, timeout=timeout, verify=False)
            if r.status_code < 500:
                return
        except requests.RequestException:
            pass
        time.sleep(3)
    fail(f"readiness timeout: {url}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app-url", required=True)
    ap.add_argument("--indexer-url", required=True)
    ap.add_argument("--indexer-user", default=os.getenv("INDEXER_USER", "admin"))
    ap.add_argument("--indexer-password", default=os.getenv("INDEXER_PASSWORD"))
    ap.add_argument("--indexer-password-file", default=os.getenv("INDEXER_PASSWORD_FILE"))
    ap.add_argument("--timeout", type=int, default=10)
    ap.add_argument("--wait", type=int, default=120)
    args = ap.parse_args()

    if args.indexer_password_file:
        try:
            with open(args.indexer_password_file, 'r', encoding='utf-8') as fh:
                args.indexer_password = fh.read().strip()
        except OSError as exc:
            fail(f"unable to read indexer password file: {exc}")

    if not args.indexer_password:
        fail("INDEXER_PASSWORD was not supplied")

    # The WAF intentionally exposes only the Juice Shop root; readiness is
    # therefore verified against the real application endpoint.
    wait_for(f"{args.app_url.rstrip('/')}/", args.timeout, args.wait)

    marker = f"FYND_VERIFIER_MARKER-{uuid.uuid4().hex}"
    print(f"Unique marker: {marker}")

    # Benign marker request must pass through the WAF.
    try:
        r = requests.get(
            args.app_url.rstrip("/") + "/",
            params={"marker": marker},
            timeout=args.timeout,
            verify=False,
        )
        if r.status_code >= 400:
            fail(f"marker request returned HTTP {r.status_code}")
    except requests.RequestException as exc:
        fail(f"application request failed: {exc}")

    # Deterministic WAF acceptance test: the CRS should block this SQLi probe.
    try:
        blocked = requests.get(
            args.app_url.rstrip("/") + "/",
            params={"id": "1 OR 1=1"},
            timeout=args.timeout,
            verify=False,
        )
        if blocked.status_code != 403:
            fail(f"WAF blocking test expected HTTP 403, got {blocked.status_code}")
        print("WAF blocking test passed")
    except requests.RequestException as exc:
        fail(f"WAF blocking test failed: {exc}")

    query = {
        "size": 50,
        "query": {
            "query_string": {
                "query": f'"{marker}"'
            }
        }
    }

    deadline = time.time() + args.wait
    indexer = args.indexer_url.rstrip("/")
    indices = ("wazuh-alerts-*", "wazuh-archives-*")
    while time.time() < deadline:
        try:
            for index_pattern in indices:
                r = requests.post(
                    f"{indexer}/{index_pattern}/_search",
                    auth=(args.indexer_user, args.indexer_password),
                    json=query,
                    timeout=args.timeout,
                    verify=False,
                )
                if r.ok:
                    total = r.json().get("hits", {}).get("total", {}).get("value", 0)
                    if total and int(total) > 0:
                        print(f"VERIFICATION PASSED ({index_pattern})")
                        return
        except (requests.RequestException, ValueError, KeyError):
            pass
        time.sleep(5)

    fail("unique marker was not found in Wazuh alerts or archives within timeout")

if __name__ == "__main__":
    main()
