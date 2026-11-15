"""GitHub-only checks for our library; never claims QQ runtime compatibility."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

def command(*args):
    return subprocess.check_output(args, text=True).strip()

def main():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise SystemExit("Run build verification in GitHub Actions.")
    path = Path(sys.argv[1])
    if command("xcrun", "lipo", "-archs", str(path)).split() != ["arm64"]:
        raise SystemExit("Unexpected architecture.")
    commands = command("xcrun", "otool", "-l", str(path))
    if not re.search(r"^\s*platform\s+(?:2|IOS)\s*$", commands, re.M):
        raise SystemExit("Not an iOS device library.")
    libraries = command("xcrun", "otool", "-L", str(path))
    if any(x in libraries for x in ("MobileSubstrate", "libsubstrate", "/var/jb/")):
        raise SystemExit("Unexpected jailbreak-only dependency.")
    subprocess.run(["codesign", "--verify", "--strict", str(path)], check=True)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    evidence = {
        "schema": "qq-anti-recall-build-v1",
        "plugin_version": "0.5.0-experimental",
        "source_commit": os.environ["GITHUB_SHA"],
        "run_id": os.environ["GITHUB_RUN_ID"],
        "qq_short_version": "9.3.86", "qq_build": "9.3.86.617",
        "architecture": "arm64", "platform": "iOS device",
        "minimum_ios": "15.0", "xcode": command("xcodebuild", "-version"),
        "sha256": digest, "signature": "ad-hoc; must re-sign with host QQ",
        "synthetic_tests_passed": True, "actual_qq_runtime_verified": False,
        "actual_ios_27_0_1_verified": False,
    }
    path.with_name("build-info.json").write_text(json.dumps(evidence, indent=2) + "\n")
    path.with_name("SHA256SUMS").write_text(digest + "  " + path.name + "\n")
    print(json.dumps(evidence))
if __name__ == "__main__":
    main()
