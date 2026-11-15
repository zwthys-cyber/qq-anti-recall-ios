"""Build/run a UIKit fixture on GitHub Actions; never install or execute QQ."""
import json
import os
import pathlib
import platform
import plistlib
import shutil
import subprocess

def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)

root = pathlib.Path(os.environ["RUNNER_TEMP"]) / "qar-badge-ui"
app = root / "QARBadgeFixture.app"
app.mkdir(parents=True, exist_ok=True)
bundle = "local.qqantirecall.badgefixture"
with (app / "Info.plist").open("wb") as output:
    plistlib.dump({
        "CFBundleIdentifier": bundle,
        "CFBundleName": "QARBadgeFixture",
        "CFBundleExecutable": "QARBadgeFixture",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
        "CFBundleShortVersionString": "1.0",
        "MinimumOSVersion": "15.0",
        "LSRequiresIPhoneOS": True,
        "UIDeviceFamily": [1],
        "UILaunchScreen": {},
    }, output)
sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path", capture_output=True).stdout.strip()
arch = platform.machine()
sources = [
    "QARHook", "QARAdapter", "QARTrace", "QARIncoming", "QARUpdateFilter",
    "QARSnapshot", "QARStore", "QARHistory", "QARBadgeRecord", "QARBadge",
]
run("xcrun", "clang", "-target", f"{arch}-apple-ios15.0-simulator", "-isysroot", sdk,
    "-fobjc-arc", "-DQAR_TESTING", "-Wall", "-Wextra", "-Werror", "-I", "Sources", "-I", "Tests",
    *(f"Sources/{name}.m" for name in sources), "Tests/ModelFixtures.m", "Tests/BadgeUITests.m",
    "-framework", "Foundation", "-framework", "UIKit", "-framework", "CoreGraphics",
    "-o", str(app / "QARBadgeFixture"))
run("codesign", "--force", "--sign", "-", str(app))
devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j", capture_output=True).stdout)
phones = [device for runtime, items in devices["devices"].items() if ".iOS-" in runtime
          for device in items if device.get("isAvailable") and device["name"].startswith("iPhone")]
if not phones:
    raise RuntimeError("This runner has no available iPhone simulator")
device = next((p for p in phones if p["state"] == "Booted"), phones[0])
udid = device["udid"]
if device["state"] != "Booted":
    run("xcrun", "simctl", "boot", udid)
run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=180)
run("xcrun", "simctl", "install", udid, str(app))
result = run("xcrun", "simctl", "launch", "--console", "--terminate-running-process",
             udid, bundle, capture_output=True, timeout=120)
print(result.stdout)
print(result.stderr)
if "PASS: UIKit footer geometry" not in result.stdout:
    raise RuntimeError("UIKit fixture did not complete its assertions")
container = pathlib.Path(run("xcrun", "simctl", "get_app_container", udid, bundle, "data", capture_output=True).stdout.strip())
destination = pathlib.Path("dist")
destination.mkdir(exist_ok=True)
for name in ("badge-light.png", "badge-dark.png"):
    shutil.copy2(container / "Documents" / name, destination / name)
(destination / "badge-ui-tests.json").write_text(json.dumps({
    "passed": True, "environment": "synthetic UIKit simulator fixture",
    "real_qq_runtime_verified": False,
    "checks": ["footer_geometry", "normal_row", "reuse", "history_disk_restore",
               "dark_mode_render", "disabled", "account_switch"],
}, indent=2) + "\n")
