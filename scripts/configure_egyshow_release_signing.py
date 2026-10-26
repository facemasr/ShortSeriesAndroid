#!/usr/bin/env python3
"""Configure release signing with the ORIGINAL EGYSHOW 2.0.0 Android key.

Run only inside the short-lived CI runner, after flutter create.
The private key must be provided using masked GitHub Actions secrets.
An unsigned or differently signed APK must never be uploaded as an update.
"""
import base64
import hashlib
import os
from pathlib import Path
import subprocess
import sys

EXPECTED_SIGNER_SHA256 = "77a1db62a9596a58be7e42b50a72933c215a504391c200fe6dbce95a77f176cb"

def required(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise RuntimeError(f"Missing {name}; original EGYSHOW signing key is required")
    return value

def main():
    encoded = required("EGYSHOW_RELEASE_KEYSTORE_BASE64")
    store_password = required("EGYSHOW_RELEASE_STORE_PASSWORD")
    key_alias = required("EGYSHOW_RELEASE_KEY_ALIAS")
    required("EGYSHOW_RELEASE_KEY_PASSWORD")
    key_file = Path("android/app/egyshow-release.jks")
    if not key_file.parent.is_dir():
        raise RuntimeError("Generate Android shell with flutter create first")
    key_bytes = base64.b64decode(encoded, validate=True)
    if len(key_bytes) < 100:
        raise RuntimeError("Release keystore is invalid")
    key_file.write_bytes(key_bytes)
    key_file.chmod(0o600)
    cert = subprocess.run(
        ["keytool", "-exportcert", "-alias", key_alias,
         "-keystore", str(key_file), "-storepass", store_password],
        capture_output=True, check=True,
    ).stdout
    fingerprint = hashlib.sha256(cert).hexdigest()
    if fingerprint != EXPECTED_SIGNER_SHA256:
        key_file.unlink(missing_ok=True)
        raise RuntimeError(
            "The supplied key does NOT match installed EGYSHOW 2.0.0: "
            + fingerprint + " != " + EXPECTED_SIGNER_SHA256
        )
    gradle = Path("android/app/build.gradle.kts")
    source = gradle.read_text()
    if source.count('signingConfig = signingConfigs.getByName("debug")') != 1:
        raise RuntimeError("Unexpected Flutter Kotlin build config; refusing unsafe signing")
    if source.count("    buildTypes {") != 1:
        raise RuntimeError("Unexpected Flutter Kotlin signing configuration")
    config = '''    signingConfigs {
        create("egyshowRelease") {
            storeFile = file("egyshow-release.jks")
            storePassword = System.getenv("EGYSHOW_RELEASE_STORE_PASSWORD")
            keyAlias = System.getenv("EGYSHOW_RELEASE_KEY_ALIAS")
            keyPassword = System.getenv("EGYSHOW_RELEASE_KEY_PASSWORD")
        }
    }
    buildTypes {'''
    source = source.replace("    buildTypes {", config, 1)
    source = source.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = signingConfigs.getByName("egyshowRelease")', 1
    )
    gradle.write_text(source)
    print("EGYSHOW original release signing key verified; safe signing configured")

if __name__ == "__main__":
    try:
        main()
    except Exception as err:
        print("Release signing blocked: " + str(err), file=sys.stderr)
        sys.exit(1)
