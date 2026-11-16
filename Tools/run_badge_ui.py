"""Build/run a UIKit fixture on GitHub Actions; never install or execute QQ."""
import base64
import json
import os
import pathlib
import platform
import plistlib
import shutil
import subprocess
import time

def run(*args, **kwargs):
    kwargs.setdefault("timeout", 120)
    print("Badge fixture command:", " ".join(args[:4]), flush=True)
    try:
        return subprocess.run(args, check=True, text=True, **kwargs)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        if error.stdout:
            print(error.stdout, flush=True)
        if error.stderr:
            print(error.stderr, flush=True)
        raise

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
        "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False,
            "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [{
                "UISceneConfigurationName": "Fixture", "UISceneDelegateClassName": "FixtureScene"}]}},
    }, output)
sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path", capture_output=True).stdout.strip()
arch = platform.machine()
sources = [
    "QARHook", "QARAdapter", "QARTrace", "QARIncoming", "QARUpdateFilter",
    "QARSnapshot", "QARStore", "QARHistory", "QARBadgeRecord", "QARBadge", "QARFlash", "QARSettings", "QARDeviceDiagnostics", "QARControl",
]
run("xcrun", "clang", "-target", f"{arch}-apple-ios15.0-simulator", "-isysroot", sdk,
    "-fobjc-arc", "-DQAR_TESTING", "-Wall", "-Wextra", "-Werror", "-I", "Sources", "-I", "Tests",
    *(f"Sources/{name}.m" for name in sources), "Tests/ModelFixtures.m", "Tests/BadgeUITests.m",
    "-framework", "Foundation", "-framework", "UIKit", "-framework", "CoreGraphics", "-framework", "QuickLook", "-framework", "WebKit", "-framework", "JavaScriptCore",
    "-o", str(app / "QARBadgeFixture"))
run("codesign", "--force", "--sign", "-", str(app))
devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j", capture_output=True).stdout)
preferred_runtime = os.environ.get("QAR_SIMULATOR_RUNTIME", "")
phones = [device for runtime, items in devices["devices"].items() if ".iOS-" in runtime
          and (not preferred_runtime or runtime.endswith(preferred_runtime))
          for device in items if device.get("isAvailable") and device["name"].startswith("iPhone")]
if not phones:
    raise RuntimeError("This runner has no available iPhone simulator")
device = next((p for p in phones if p["state"] == "Booted"),
              next((p for p in phones if p["name"] in ("iPhone 16", "iPhone 17e")), phones[0]))
udid = device["udid"]
if device["state"] != "Booted":
    run("xcrun", "simctl", "boot", udid)
run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=480)
run("xcrun", "simctl", "install", udid, str(app), timeout=300)
container = pathlib.Path(run("xcrun", "simctl", "get_app_container", udid, bundle, "data", capture_output=True).stdout.strip())
run("xcrun", "simctl", "launch", "--terminate-running-process", udid, bundle, timeout=180)
result_file = container / "Documents" / "fixture-result.txt"
deadline = time.monotonic() + 180
result = ""
while time.monotonic() < deadline:
    if result_file.exists():
        current = result_file.read_text()
        if current != result:
            print(current, flush=True)
            result = current
        if result.startswith(("PASS:", "FAIL:")):
            break
    crash_reports = pathlib.Path.home() / "Library" / "Logs" / "DiagnosticReports"
    if list(crash_reports.glob("QARBadgeFixture*.ips")):
        break
    time.sleep(1)
if not result.startswith("PASS: UIKit footer geometry"):
    reports = pathlib.Path.home() / "Library" / "Logs" / "DiagnosticReports"
    for path in sorted(reports.glob("QARBadgeFixture*.ips"))[-2:]:
        print("Synthetic fixture crash report:", path.name, flush=True)
        print(path.read_text(errors="replace")[:20000], flush=True)
    raise RuntimeError("UIKit fixture did not pass: " + (result or "no executable progress file"))
destination = pathlib.Path("dist")
destination.mkdir(exist_ok=True)
for name in ("badge-light.png", "badge-dark.png"):
    shutil.copy2(container / "Documents" / name, destination / name)
    # Synthetic fixture pixels only, for review without running local repository tools.
    print("QAR_BADGE_PREVIEW " + name + " " + base64.b64encode((destination / name).read_bytes()).decode(), flush=True)
(destination / "badge-ui-tests.json").write_text(json.dumps({
    "passed": True, "environment": "synthetic UIKit simulator fixture",
    "real_qq_runtime_verified": False,
    "simulator_runtime_filter": preferred_runtime, "simulator_device": device["name"],
    "xcode": run("xcodebuild", "-version", capture_output=True).stdout.strip(),
    "checks": ["opaque_view_model", "false_bind_result", "actual_delegate_height",
               "unrelated_table_unchanged", "no_height_query_recursion", "footer_geometry", "normal_row", "reuse", "history_disk_restore",
               "dark_mode_render", "disabled", "account_switch", "settings_footer_preserved",
               "chat_flash_replay_twice", "flash_switch_independent", "flash_message_path_isolation",
               "flash_source_deleted", "flash_disable_closes_preview"],
}, indent=2) + "\n")
