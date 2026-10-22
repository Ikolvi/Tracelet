#!/usr/bin/env python3
"""Mint Ed25519-signed licenses for the Tracelet crash-model unlock Worker (#183).

A license key is:  base64url(payload_json) + "." + base64url(ed25519_signature)

The Worker holds only the PUBLIC key (to verify). The PRIVATE key lives only on
your machine — whoever has it can mint licenses, so guard it like a signing key.

Subcommands:
  keygen                       Generate an Ed25519 keypair (prints pub/priv base64url).
  mint  --pkg <id> [...]       Mint a signed license for an app package id.

Examples:
  # 1. one-time: create the signing keypair (store priv safely, never commit)
  python3 scripts/mint_license.py keygen > license_keys.txt

  # 2. per customer: mint a 1-year pro license bound to their app id
  python3 scripts/mint_license.py mint \
      --priv "$(grep PRIVATE license_keys.txt | cut -d' ' -f2)" \
      --pkg com.acme.driver --plan pro --days 365

The Worker secret LICENSE_PUBLIC_KEY = the printed PUBLIC value.
"""
from __future__ import annotations

import argparse
import base64
import json
import sys
import time
import uuid

try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import (
        Ed25519PrivateKey,
        Ed25519PublicKey,
    )
    from cryptography.hazmat.primitives import serialization
except ImportError:
    sys.exit("Missing dependency: pip install cryptography")


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def b64url_decode(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)


def cmd_keygen(_args: argparse.Namespace) -> int:
    priv = Ed25519PrivateKey.generate()
    pub = priv.public_key()
    priv_raw = priv.private_bytes(
        serialization.Encoding.Raw,
        serialization.PrivateFormat.Raw,
        serialization.NoEncryption(),
    )
    pub_raw = pub.public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    )
    print(f"PUBLIC  {b64url(pub_raw)}")
    print(f"PRIVATE {b64url(priv_raw)}")
    print("\n# Set the Worker secret:  npx wrangler secret put LICENSE_PUBLIC_KEY", file=sys.stderr)
    print("# (paste the PUBLIC value). Keep PRIVATE offline — never commit it.", file=sys.stderr)
    return 0


def cmd_mint(args: argparse.Namespace) -> int:
    priv = Ed25519PrivateKey.from_private_bytes(b64url_decode(args.priv))

    # Prod licenses MUST bind a signing cert (they require Play Integrity at the
    # Worker). Dev licenses skip attestation so they work in debug builds.
    if args.scope == "prod" and not args.cert_sha256:
        sys.exit("prod licenses require --cert-sha256 (the app signing-cert SHA-256)")

    now = int(time.time())
    payload: dict[str, object] = {
        "pkg": args.pkg,
        "plan": args.plan,
        "scope": args.scope,
        "iat": now,
        "lic": args.lic or str(uuid.uuid4()),
    }
    if args.days > 0:
        payload["exp"] = now + args.days * 86400
    if args.cert_sha256:
        # Phase B binding (hex, lowercase, no colons).
        payload["certSha256"] = args.cert_sha256.lower().replace(":", "")

    # Sign the base64url payload string bytes (avoids JSON canonicalization issues —
    # the Worker verifies over the exact same payload segment).
    payload_b64 = b64url(
        json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
    )
    signature = priv.sign(payload_b64.encode())
    license_key = f"{payload_b64}.{b64url(signature)}"

    print(license_key)
    print(f"\n# scope: {args.scope}  (license id for revocation: {payload['lic']})", file=sys.stderr)
    if args.scope == "dev":
        print("# dev license: bound to the app id; works in debug builds and emulators.", file=sys.stderr)
    else:
        # #439: prod no longer needs a Play Integrity token — it is bound to the
        # app id and, on Android, the signing cert(s) the SDK reports.
        print("# prod license: bound to the app id and, on Android, the signing cert.", file=sys.stderr)
    if "exp" in payload:
        print(f"# expires: {time.strftime('%Y-%m-%d', time.gmtime(payload['exp']))}", file=sys.stderr)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Mint Ed25519-signed crash-model licenses.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("keygen", help="Generate an Ed25519 keypair.").set_defaults(
        func=cmd_keygen
    )

    m = sub.add_parser("mint", help="Mint a signed license.")
    m.add_argument("--priv", required=True, help="Ed25519 private key (base64url).")
    m.add_argument("--pkg", required=True, help="App package id / bundle id.")
    m.add_argument("--plan", default="pro", help="Plan label (default: pro).")
    m.add_argument(
        "--scope",
        choices=["dev", "prod"],
        default="dev",
        help="dev = works in debug builds (no Play Integrity); "
        "prod = requires Play Integrity + --cert-sha256 (default: dev).",
    )
    m.add_argument("--days", type=int, default=365, help="Validity in days (0 = perpetual).")
    m.add_argument("--lic", default="", help="License id (default: random UUID).")
    m.add_argument(
        "--cert-sha256",
        default="",
        help="App signing-cert SHA-256 to bind (hex). Required for --scope prod.",
    )
    m.set_defaults(func=cmd_mint)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
