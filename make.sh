#!/usr/bin/env bash
# =========================================================
# SingBoxWrapper v12 — one-shot generator + builder
# Sinh toàn bộ source (7 Swift + 6 core JS + 8 module JS + HTML + CSS)
# rồi build IPA. Chạy từ thư mục trống.
# =========================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/SingBoxWrapper"
WEB="$SRC/web"
PROJ="$ROOT/SingBoxWrapper.xcodeproj"
BUILD="$ROOT/build"
DERIVED="$BUILD/DerivedData"
ARCHIVE="$BUILD/SingBoxWrapper.xcarchive"
EXPORT_DIR="$BUILD/export"

BUNDLE_ID="com.tandung.singboxwrapper"
TEAM_ID="${TEAM_ID:-}"
CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Automatic}"
EXPORT_METHOD="${EXPORT_METHOD:-development}"

G='\033[0;32m'; Y='\033[0;33m'; R='\033[0;31m'; N='\033[0m'
log(){  echo -e "${G}[+]${N} $*"; }
warn(){ echo -e "${Y}[!]${N} $*"; }
die(){  echo -e "${R}[x]${N} $*" >&2; exit 1; }

# ---------- Tool check ----------
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild không có — cài Xcode từ App Store"
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    log "Cài xcodegen qua Homebrew"
    brew install xcodegen
  else
    die "Cần xcodegen. Cài Homebrew trước: https://brew.sh"
  fi
fi

# ---------- Clean ----------
log "Dọn build cũ"
rm -rf "$SRC" "$PROJ" "$BUILD"
mkdir -p "$SRC" "$WEB/core" "$WEB/modules" "$BUILD" "$EXPORT_DIR"

# =========================================================
# 1. Info.plist
# =========================================================
log "Sinh Info.plist"
cat > "$SRC/Info.plist" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>SingBoxWrapper</string>
  <key>CFBundleDisplayName</key><string>SingBoxWrapper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>12.0</string>
  <key>CFBundleVersion</key><string>12</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>16.0</string>
  <key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
  <key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
  <key>LSApplicationQueriesSchemes</key>
  <array>
    <string>sing-box</string>
    <string>freefire</string>
    <string>freefiremax</string>
    <string>ff</string>
  </array>
  <key>UIBackgroundModes</key>
  <array><string>fetch</string><string>processing</string></array>
  <key>BGTaskSchedulerPermittedIdentifiers</key>
  <array>
    <string>com.tandung.singboxwrapper.refresh</string>
    <string>com.tandung.singboxwrapper.engine</string>
  </array>
  <key>UIFileSharingEnabled</key><true/>
  <key>LSSupportsOpeningDocumentsInPlace</key><true/>
  <key>UILaunchScreen</key><dict/>
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UIApplicationSupportsMultipleScenes</key><false/>
    <key>UISceneConfigurations</key>
    <dict>
      <key>UIWindowSceneSessionRoleApplication</key>
      <array>
        <dict>
          <key>UISceneConfigurationName</key><string>Default Configuration</string>
          <key>UISceneDelegateClassName</key><string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
        </dict>
      </array>
    </dict>
  </dict>
</dict>
</plist>
PLIST_EOF

# =========================================================
# 2. Entitlements
# =========================================================
log "Sinh entitlements"
cat > "$SRC/SingBoxWrapper.entitlements" <<'ENT_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.application-groups</key>
  <array><string>group.com.tandung.singboxwrapper</string></array>
</dict>
</plist>
ENT_EOF

# =========================================================
# 3. Swift sources
# =========================================================
log "Sinh Swift sources"

cat > "$SRC/SingBoxWrapperApp.swift" <<'SWIFT_EOF'
import UIKit
import BackgroundTasks

@main
final class SingBoxWrapperAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.tandung.singboxwrapper.refresh",
            using: nil
        ) { task in
            guard let t = task as? BGAppRefreshTask else { return }
            NativeBridge.shared.handleBackgroundRefresh(t)
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.tandung.singboxwrapper.engine",
            using: nil
        ) { task in
            guard let t = task as? BGProcessingTask else { return }
            NativeBridge.shared.handleBackgroundEngine(t)
        }
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
SWIFT_EOF

cat > "$SRC/SceneDelegate.swift" <<'SWIFT_EOF'
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: ws)
        window?.rootViewController = WebViewController()
        window?.makeKeyAndVisible()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        NativeBridge.shared.scheduleBackgroundRefresh()
    }
}
SWIFT_EOF

cat > "$SRC/SingBoxBridge.swift" <<'SWIFT_EOF'
import Foundation
import UIKit

final class SingBoxBridge {
    static let shared = SingBoxBridge()
    private init() {}

    private let appGroup = "group.com.tandung.singboxwrapper"
    private let configName = "singbox_config.json"

    @discardableResult
    func writeConfig(_ json: String) -> URL? {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = container.appendingPathComponent(configName)
        do {
            try json.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            print("[SingBox] write failed: \(error.localizedDescription)")
            return nil
        }
    }

    func importConfig(_ url: URL) -> Bool {
        let enc = url.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let candidates = [
            "sing-box://import-local?path=\(enc)",
            "sing-box://import?path=\(enc)",
            "sing-box://import-remote-profile?url=file://\(enc)",
            "sing-box://install-config?url=file://\(enc)"
        ]
        for c in candidates {
            guard let u = URL(string: c), UIApplication.shared.canOpenURL(u) else { continue }
            UIApplication.shared.open(u, options: [:], completionHandler: nil)
            return true
        }
        return false
    }

    func toggleTunnel() -> Bool {
        guard let u = URL(string: "sing-box://toggle"),
              UIApplication.shared.canOpenURL(u) else { return false }
        UIApplication.shared.open(u, options: [:], completionHandler: nil)
        return true
    }

    func isInstalled() -> Bool {
        guard let u = URL(string: "sing-box://") else { return false }
        return UIApplication.shared.canOpenURL(u)
    }

    func launchGame(_ bundle: String) -> Bool {
        guard let u = URL(string: "\(bundle)://"),
              UIApplication.shared.canOpenURL(u) else { return false }
        UIApplication.shared.open(u, options: [:], completionHandler: nil)
        return true
    }
}
SWIFT_EOF

cat > "$SRC/AimBridge.swift" <<'SWIFT_EOF'
import Foundation

final class AimBridge {
    static let shared = AimBridge()
    private init() {}

    private let appGroup = "group.com.tandung.singboxwrapper"
    private let stateFile = "aim_state.json"
    private let queue = DispatchQueue(label: "aim.bridge.queue", attributes: .concurrent)

    private var features: [String: Bool] = [:]
    private var offsets: [String: String] = [:]

    func setFeature(_ key: String, value: Bool, offset: String?) {
        queue.async(flags: .barrier) {
            self.features[key] = value
            if let o = offset { self.offsets[key] = o }
            self.persistLocked()
        }
        print("[Aim] \(key)=\(value)")
    }

    func setAll(_ dict: [String: Bool], offsets off: [String: String]) {
        queue.async(flags: .barrier) {
            self.features = dict
            self.offsets = off
            self.persistLocked()
        }
    }

    func snapshot() -> [String: Any] {
        queue.sync { ["features": features, "offsets": offsets] }
    }

    func activeCount() -> Int {
        queue.sync { features.values.filter { $0 }.count }
    }

    private func persistLocked() {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = container.appendingPathComponent(stateFile)
        let payload: [String: Any] = ["features": features, "offsets": offsets]
        if let d = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) {
            try? d.write(to: url, options: .atomic)
        }
    }
}
SWIFT_EOF

cat > "$SRC/EngineBridge.swift" <<'SWIFT_EOF'
import Foundation

final class EngineBridge {
    static let shared = EngineBridge()
    private init() {}

    private var running = false
    private var pollTimer: Timer?

    var isRunning: Bool { running }

    func start(payload: [String: Any], reply: @escaping ([String: Any]) -> Void) {
        if let aim = payload["aim"] as? [String: Any],
           let feats = aim["features"] as? [String: Bool],
           let offs = aim["offsets"] as? [String: String] {
            AimBridge.shared.setAll(feats, offsets: offs)
        }
        running = true
        UserDefaults.standard.set(true, forKey: "engine_running")
        startPolling()
        reply([
            "event": "started",
            "ok": true,
            "active": AimBridge.shared.activeCount(),
            "ts": Date().timeIntervalSince1970
        ])
        print("[Engine] started")
    }

    func stop(reply: @escaping ([String: Any]) -> Void) {
        running = false
        UserDefaults.standard.set(false, forKey: "engine_running")
        stopPolling()
        reply(["event": "stopped", "ok": true])
        print("[Engine] stopped")
    }

    func launchGame(_ bundle: String) -> Bool {
        SingBoxBridge.shared.launchGame(bundle)
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self, self.running else { return }
            // placeholder attach tick
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
SWIFT_EOF

cat > "$SRC/NativeBridge.swift" <<'SWIFT_EOF'
import Foundation
import UIKit
import BackgroundTasks

final class NativeBridge {
    static let shared = NativeBridge()
    private init() {}

    private weak var replyHandler: (([String: Any]) -> Void)?

    func setReplyHandler(_ h: @escaping ([String: Any]) -> Void) {
        replyHandler = h
    }

    func handle(action: String,
                payload: [String: Any],
                reply: @escaping ([String: Any]) -> Void) {
        switch action {

        case "ready":
            reply(["event": "ready", "ok": true, "version": payload["version"] ?? "?"])

        case "enter_singbox", "import_singbox":
            handleEnterSingBox(payload: payload, reply: reply)

        case "sfi_activate":
            let ok = SingBoxBridge.shared.toggleTunnel()
            reply(["event": "singbox_activated", "ok": ok,
                   "message": ok ? "Sing-box tunnel toggled" : "Toggle scheme unavailable"])

        case "query_status":
            reply(["event": "status", "ok": true,
                   "singBoxInstalled": SingBoxBridge.shared.isInstalled()])

        case "start_all":
            EngineBridge.shared.start(payload: payload, reply: reply)

        case "stop_all":
            EngineBridge.shared.stop(reply: reply)

        case "update_state":
            guard let key = payload["key"] as? String,
                  let val = payload["value"] as? Bool else {
                reply(["event": "error", "ok": false, "message": "missing key/value"])
                return
            }
            AimBridge.shared.setFeature(key, value: val, offset: payload["offset"] as? String)
            reply(["event": "state_updated", "ok": true, "key": key, "value": val])

        case "launch_game":
            let bundle = payload["bundle"] as? String ?? "com.dts.freefireth"
            let ok = EngineBridge.shared.launchGame(bundle)
            reply(["event": "game_launched", "ok": ok, "bundle": bundle])

        case "engine_snapshot":
            reply(["event": "snapshot", "ok": true, "data": AimBridge.shared.snapshot()])

        default:
            reply(["event": "unknown", "ok": false, "message": action])
        }
    }

    private func handleEnterSingBox(payload: [String: Any],
                                    reply: @escaping ([String: Any]) -> Void) {
        guard let json = payload["json"] as? String else {
            reply(["event": "error", "ok": false, "message": "JSON missing"])
            return
        }
        guard (try? JSONSerialization.jsonObject(with: Data(json.utf8))) != nil else {
            reply(["event": "error", "ok": false, "message": "Invalid JSON"])
            return
        }
        let autoActivate = payload["autoActivate"] as? Bool ?? false
        let launch = payload["autoLaunch"] as? Bool ?? true

        guard let url = SingBoxBridge.shared.writeConfig(json) else {
            reply(["event": "error", "ok": false, "message": "Cannot write config"])
            return
        }
        reply(["event": "singbox_written", "ok": true, "path": url.path])

        if launch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if SingBoxBridge.shared.importConfig(url) {
                    reply(["event": "singbox_launched", "ok": true, "path": url.path])
                    if autoActivate {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            let ok = SingBoxBridge.shared.toggleTunnel()
                            reply(["event": "singbox_activated", "ok": ok,
                                   "message": ok ? "toggled" : "unavailable"])
                        }
                    }
                } else {
                    reply(["event": "error", "ok": false, "message": "SFI unavailable"])
                }
            }
        } else if autoActivate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let ok = SingBoxBridge.shared.toggleTunnel()
                reply(["event": "singbox_activated", "ok": ok,
                       "message": ok ? "toggled" : "unavailable"])
            }
        }
    }

    func scheduleBackgroundRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: "com.tandung.singboxwrapper.refresh")
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(req)

        if UserDefaults.standard.bool(forKey: "engine_running") {
            let eng = BGProcessingTaskRequest(identifier: "com.tandung.singboxwrapper.engine")
            eng.requiresNetworkConnectivity = true
            eng.requiresExternalPower = false
            try? BGTaskScheduler.shared.submit(eng)
        }
    }

    func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        task.setTaskCompleted(success: true)
    }

    func handleBackgroundEngine(_ task: BGProcessingTask) {
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        task.setTaskCompleted(success: true)
    }
}
SWIFT_EOF

cat > "$SRC/WebViewController.swift" <<'SWIFT_EOF'
import UIKit
import WebKit

final class WebViewController: UIViewController, WKScriptMessageHandler {
    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "aimwrapper")
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        cfg.defaultWebpagePreferences = prefs

        webView = WKWebView(frame: view.bounds, configuration: cfg)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        view.addSubview(webView)

        NativeBridge.shared.setReplyHandler { [weak self] payload in
            self?.reply(payload)
        }

        guard let htmlURL = Bundle.main.url(forResource: "AimWrapper", withExtension: "html") else {
            presentError("AimWrapper.html missing")
            return
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: Bundle.main.bundleURL)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        let payload = body["payload"] as? [String: Any] ?? [:]
        NativeBridge.shared.handle(action: action, payload: payload) { [weak self] resp in
            self?.reply(resp)
        }
    }

    private func reply(_ payload: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: payload),
              let j = String(data: d, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript("window.AimWrapperCallback(\(j));")
        }
    }

    private func presentError(_ msg: String) {
        let a = UIAlertController(title: "Build error", message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}
SWIFT_EOF

# =========================================================
# 4. web/style.css
# =========================================================
log "Sinh web/style.css"
cat > "$WEB/style.css" <<'CSS_EOF'
:root{
  --bg:#08080b;--card:#121218;--card-2:#1a1a22;
  --line:#22222c;--line-2:#2e2e3a;
  --fg:#f0f0f5;--fg-2:#9a9aa8;--fg-3:#5a5a68;
  --red:#ff453a;--red-2:#ff6b60;--red-glow:rgba(255,69,58,.45);
  --green:#30d158;--green-glow:rgba(48,209,88,.4);
  --blue:#0a84ff;--purple:#bf5af2;--pink:#ff375f;
  --teal:#64d2ff;--orange:#ff9f0a;
  --safe-top:env(safe-area-inset-top,0px);
  --safe-bottom:env(safe-area-inset-bottom,0px);
}
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent;user-select:none;-webkit-user-select:none}
html,body{background:var(--bg);color:var(--fg);font-family:-apple-system,"SF Pro Text",system-ui,sans-serif;font-size:15px;line-height:1.4;min-height:100vh;-webkit-font-smoothing:antialiased}
body{padding:calc(var(--safe-top) + 14px) 14px calc(var(--safe-bottom) + 30px);overflow-x:hidden;overscroll-behavior-y:none}
body::before{content:'';position:fixed;inset:0;pointer-events:none;z-index:0;
  background:radial-gradient(700px circle at 50% -10%,rgba(255,69,58,.10),transparent 50%),
             radial-gradient(500px circle at 50% 110%,rgba(10,132,255,.06),transparent 50%)}
body>*{position:relative;z-index:1}
.ic{display:inline-block;vertical-align:middle;flex-shrink:0;line-height:0}
.ic svg{display:block;width:100%;height:100%}
.ic svg *{vector-effect:non-scaling-stroke;stroke-linecap:round;stroke-linejoin:round;fill:none}
.top{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:14px;padding:0 2px}
.brand{display:flex;align-items:center;gap:10px;min-width:0}
.brand-logo{width:40px;height:40px;border-radius:12px;background:linear-gradient(135deg,var(--red),#c1271f);display:flex;align-items:center;justify-content:center;color:#fff;box-shadow:0 6px 20px var(--red-glow);position:relative;overflow:hidden;flex-shrink:0}
.brand-logo::before{content:'';position:absolute;inset:0;background:radial-gradient(circle at 30% 20%,rgba(255,255,255,.25),transparent 60%)}
.brand-logo .ic{width:22px;height:22px;color:#fff;position:relative;z-index:1}
.brand-text h1{font-size:17px;font-weight:800;letter-spacing:-.4px;line-height:1}
.brand-text p{font-size:10.5px;color:var(--fg-2);margin-top:2px;font-weight:500}
.status{display:inline-flex;align-items:center;gap:6px;padding:6px 11px;border-radius:999px;background:var(--card);border:1px solid var(--line);font-size:11px;color:var(--fg-2);font-weight:600;white-space:nowrap;flex-shrink:0}
.dot{width:7px;height:7px;border-radius:50%;background:var(--fg-3);transition:all .25s;flex-shrink:0}
.dot.on{background:var(--green);box-shadow:0 0 10px var(--green-glow)}
.dot.err{background:var(--red);box-shadow:0 0 10px var(--red-glow)}
.dot.warn{background:var(--orange);animation:blink 1.2s infinite}
@keyframes blink{0%,100%{opacity:1}50%{opacity:.4}}
.master{position:relative;background:linear-gradient(135deg,var(--card),var(--card-2));border:1px solid var(--line);border-radius:20px;padding:18px;margin-bottom:12px;display:flex;align-items:center;justify-content:space-between;gap:14px;overflow:hidden;transition:border-color .3s,transform .2s}
.master:active{transform:scale(.995)}
.master::before{content:'';position:absolute;inset:0;background:radial-gradient(circle at top right,var(--red-glow),transparent 60%);opacity:0;transition:opacity .4s;pointer-events:none}
.master.on{border-color:rgba(255,69,58,.4)}
.master.on::before{opacity:.7}
.master-icon{width:44px;height:44px;border-radius:13px;background:var(--card-2);border:1px solid var(--line-2);display:flex;align-items:center;justify-content:center;color:var(--fg-2);flex-shrink:0;position:relative;z-index:1;transition:all .3s}
.master.on .master-icon{background:var(--red);border-color:var(--red-2);color:#fff;box-shadow:0 0 20px var(--red-glow)}
.master-icon .ic{width:22px;height:22px}
.master-info{position:relative;z-index:1;flex:1;min-width:0}
.master-info h2{font-size:16px;font-weight:700;letter-spacing:-.2px;margin-bottom:3px}
.master-info p{font-size:11.5px;color:var(--fg-2);line-height:1.4}
.switch{position:relative;width:58px;height:32px;flex-shrink:0;z-index:1}
.switch input{display:none}
.switch label{display:block;width:100%;height:100%;background:#26262f;border-radius:999px;cursor:pointer;transition:background .3s;position:relative;border:1px solid var(--line-2)}
.switch label::after{content:'';position:absolute;top:3px;left:3px;width:24px;height:24px;background:#fff;border-radius:50%;transition:transform .3s cubic-bezier(.34,1.56,.64,1);box-shadow:0 2px 6px rgba(0,0,0,.4)}
.switch input:checked+label{background:var(--red);border-color:var(--red-2);box-shadow:0 0 18px var(--red-glow)}
.switch input:checked+label::after{transform:translateX(26px)}
.quick{display:flex;gap:8px;margin-bottom:14px}
.quick-btn{flex:1;padding:14px;border-radius:14px;background:var(--card);border:1px solid var(--line);color:var(--fg);font-family:inherit;font-size:13px;font-weight:700;cursor:pointer;transition:all .15s;letter-spacing:.1px;display:flex;align-items:center;justify-content:center;gap:8px;-webkit-appearance:none;appearance:none}
.quick-btn:active{transform:scale(.97);background:var(--card-2)}
.quick-btn .ic{width:17px;height:17px}
.quick-btn.primary{background:linear-gradient(135deg,var(--blue),#0066d6);border-color:#3b9bff;color:#fff;box-shadow:0 6px 18px rgba(10,132,255,.35)}
.quick-btn.success{background:linear-gradient(135deg,var(--green),#20b04a);border-color:#4ee06e;color:#000;box-shadow:0 6px 18px var(--green-glow)}
.pipe{display:flex;gap:4px;padding:5px;background:var(--card);border:1px solid var(--line);border-radius:14px;margin-bottom:14px;overflow-x:auto;scrollbar-width:none}
.pipe::-webkit-scrollbar{display:none}
.p-step{flex:1;min-width:56px;text-align:center;padding:8px 4px;border-radius:9px;font-size:9.5px;font-weight:700;color:var(--fg-3);transition:all .3s;letter-spacing:.2px;position:relative;white-space:nowrap}
.p-step .pi{width:14px;height:14px;margin:0 auto 2px;display:block;color:currentColor}
.p-step.active{background:var(--red);color:#fff;box-shadow:0 4px 14px var(--red-glow)}
.p-step.done{background:rgba(48,209,88,.15);color:var(--green)}
.p-step.done::after{content:'';position:absolute;top:3px;right:3px;width:4px;height:4px;border-radius:50%;background:var(--green);box-shadow:0 0 6px var(--green)}
.acc{background:var(--card);border:1px solid var(--line);border-radius:14px;margin-bottom:8px;overflow:hidden;transition:border-color .2s}
.acc.open{border-color:var(--line-2)}
.acc-head{display:flex;align-items:center;justify-content:space-between;padding:14px 15px;cursor:pointer;transition:background .15s;gap:10px}
.acc-head:active{background:var(--card-2)}
.acc-title{display:flex;align-items:center;gap:11px;flex:1;min-width:0}
.acc-ico{width:34px;height:34px;border-radius:10px;display:flex;align-items:center;justify-content:center;flex-shrink:0;position:relative;transition:all .2s}
.acc-ico .ic{width:18px;height:18px}
.acc-ico.blue{background:rgba(10,132,255,.14);color:var(--blue);border:1px solid rgba(10,132,255,.22)}
.acc-ico.purple{background:rgba(191,90,242,.14);color:var(--purple);border:1px solid rgba(191,90,242,.22)}
.acc-ico.pink{background:rgba(255,55,95,.14);color:var(--pink);border:1px solid rgba(255,55,95,.22)}
.acc-ico.teal{background:rgba(100,210,255,.14);color:var(--teal);border:1px solid rgba(100,210,255,.22)}
.acc-ico.orange{background:rgba(255,159,10,.14);color:var(--orange);border:1px solid rgba(255,159,10,.22)}
.acc-ico.gray{background:rgba(255,255,255,.05);color:var(--fg-2);border:1px solid var(--line-2)}
.acc-ico.green{background:rgba(48,209,88,.14);color:var(--green);border:1px solid rgba(48,209,88,.22)}
.acc-name{font-size:14.5px;font-weight:700;letter-spacing:-.1px;color:var(--fg);line-height:1.2}
.acc-sub{font-size:11px;color:var(--fg-2);margin-top:1px;font-weight:500;line-height:1.3}
.acc-count{font-size:11px;font-weight:700;color:var(--fg-2);padding:3px 9px;border-radius:8px;background:var(--card-2);border:1px solid var(--line);margin-right:4px;font-variant-numeric:tabular-nums;transition:all .2s;flex-shrink:0}
.acc-count.active{background:rgba(48,209,88,.14);color:var(--green);border-color:rgba(48,209,88,.3)}
.acc-arrow{width:14px;height:14px;color:var(--fg-3);transition:transform .3s,color .3s;flex-shrink:0}
.acc.open .acc-arrow{transform:rotate(90deg);color:var(--fg-2)}
.acc-body{max-height:0;overflow:hidden;transition:max-height .35s ease}
.acc.open .acc-body{max-height:2400px}
.acc-inner{border-top:1px solid var(--line);padding:2px 0}
.row{display:flex;align-items:center;justify-content:space-between;padding:12px 15px;gap:12px;transition:background .15s}
.row:active{background:var(--card-2)}
.row+.row{border-top:1px solid var(--line)}
.row-info{flex:1;min-width:0}
.row-name{font-size:13.5px;font-weight:600;letter-spacing:-.1px;color:var(--fg);line-height:1.25}
.row-desc{font-size:10.5px;color:var(--fg-2);font-family:"SF Mono",Menlo,monospace;margin-top:2px;letter-spacing:-.2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:1.35}
.tog{position:relative;width:46px;height:27px;flex-shrink:0}
.tog input{display:none}
.tog label{display:block;width:100%;height:100%;background:#26262f;border-radius:999px;cursor:pointer;transition:background .25s;position:relative;border:1px solid var(--line-2)}
.tog label::after{content:'';position:absolute;top:2.5px;left:2.5px;width:21px;height:21px;background:#fff;border-radius:50%;transition:transform .25s cubic-bezier(.34,1.56,.64,1);box-shadow:0 1px 3px rgba(0,0,0,.4)}
.tog input:checked+label{background:var(--green);border-color:rgba(48,209,88,.6)}
.tog input:checked+label::after{transform:translateX(19px)}
.fab{position:fixed;top:calc(var(--safe-top) + 12px);right:14px;width:40px;height:40px;border-radius:50%;background:var(--card);border:1px solid var(--line-2);display:flex;align-items:center;justify-content:center;cursor:pointer;z-index:50;transition:all .2s;box-shadow:0 4px 12px rgba(0,0,0,.5);color:var(--fg-2);-webkit-appearance:none;appearance:none}
.fab:active{transform:scale(.9)}
.fab.muted{opacity:.35}
.fab .ic{width:18px;height:18px}
.log{background:#050508;border:1px solid var(--line);border-radius:12px;padding:11px;font-family:"SF Mono",Menlo,monospace;font-size:10px;line-height:1.6;color:#8a8a96;max-height:220px;overflow-y:auto;white-space:pre-wrap;word-break:break-all;-webkit-overflow-scrolling:touch}
.log .ok{color:var(--green)}.log .err{color:var(--red)}.log .warn{color:var(--orange)}
.log .info{color:var(--blue)}.log .ts{color:var(--fg-3)}
.log .nat{color:var(--purple)}.log .snd{color:var(--teal)}
.modal-bg{position:fixed;inset:0;background:rgba(0,0,0,.82);backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px);display:none;align-items:center;justify-content:center;z-index:999;padding:20px}
.modal-bg.show{display:flex;animation:fade .2s}
@keyframes fade{from{opacity:0}to{opacity:1}}
.modal{background:var(--card);border:1px solid var(--line-2);border-radius:18px;padding:22px;width:100%;max-width:340px;box-shadow:0 20px 60px rgba(0,0,0,.7);animation:pop .25s cubic-bezier(.34,1.56,.64,1)}
@keyframes pop{from{transform:scale(.95);opacity:0}to{transform:scale(1);opacity:1}}
.modal h3{font-size:17px;font-weight:800;margin-bottom:8px;letter-spacing:-.3px}
.modal p{font-size:13px;color:var(--fg-2);margin-bottom:18px;line-height:1.5}
.modal button{width:100%;padding:13px;border-radius:12px;background:var(--red);border:none;color:#fff;font-size:14px;font-weight:700;font-family:inherit;cursor:pointer;-webkit-appearance:none;appearance:none}
.modal button:active{transform:scale(.97);background:#d63028}
.ver{text-align:center;color:var(--fg-3);font-size:10px;margin-top:20px;letter-spacing:.3px;font-weight:500}
#module-container{display:block}
@media (max-width:360px){body{font-size:14px;padding-left:10px;padding-right:10px}.brand-text h1{font-size:16px}.quick-btn{font-size:12px;padding:12px}.row{padding:11px 13px}.acc-head{padding:12px 13px}.p-step{font-size:9px;min-width:48px}}
@media (min-width:600px){body{max-width:520px;margin:0 auto}}
@media (prefers-reduced-motion:reduce){*{animation-duration:.01ms!important;animation-iteration-count:1!important;transition-duration:.01ms!important}}
CSS_EOF

# =========================================================
# 5. web/core/*.js
# =========================================================
log "Sinh core JS"

cat > "$WEB/core/sound.js" <<'JS_EOF'
window.Sound = (() => {
  let ctx=null,enabled=false;
  function ac(){if(!ctx){const A=window.AudioContext||window.webkitAudioContext;if(!A)return null;ctx=new A()}if(ctx.state==='suspended')ctx.resume();return ctx}
  function tone(f,d,ty='sine',v=.15){if(!enabled)return;const c=ac();if(!c)return;
    const o=c.createOscillator(),g=c.createGain();o.type=ty;
    o.frequency.setValueAtTime(f,c.currentTime);
    g.gain.setValueAtTime(0,c.currentTime);g.gain.linearRampToValueAtTime(v,c.currentTime+.008);
    g.gain.exponentialRampToValueAtTime(.0001,c.currentTime+d);
    o.connect(g);g.connect(c.destination);o.start();o.stop(c.currentTime+d+.02)}
  return {
    toggle:(on)=>{on?tone(880,.08):tone(660,.08)},
    click:()=>tone(1400,.035,'square',.07),
    tap:()=>tone(2200,.02,'sine',.05),
    success:()=>{tone(880,.08);setTimeout(()=>tone(1175,.08),85);setTimeout(()=>tone(1568,.13),170)},
    error:()=>{tone(320,.16,'sawtooth',.12);setTimeout(()=>tone(220,.2,'sawtooth',.12),140)},
    step:()=>tone(660,.05,'triangle',.1),
    launch:()=>{tone(523,.07);setTimeout(()=>tone(784,.07),70);setTimeout(()=>tone(1046,.11),140)},
    on:()=>{tone(660,.06);setTimeout(()=>tone(990,.09),55)},
    off:()=>{tone(520,.06);setTimeout(()=>tone(350,.11),55)},
    setEnabled:(v)=>{enabled=v;if(v)tone(1100,.05)},
    isEnabled:()=>enabled
  };
})();
JS_EOF

cat > "$WEB/core/log.js" <<'JS_EOF'
window.LOG=(m,c='')=>{
  const el=document.getElementById('log');if(!el)return;
  const t=new Date().toTimeString().slice(0,8);
  const l=document.createElement('div');
  l.innerHTML=`<span class="ts">[${t}]</span> <span class="${c}">${m}</span>`;
  el.appendChild(l);el.scrollTop=el.scrollHeight;
  if(el.children.length>300)el.removeChild(el.firstChild);
};
window.setStatus=(t,c='')=>{
  document.getElementById('dot').className='dot'+(c?' '+c:'');
  document.getElementById('stat').textContent=t;
};
window.setStep=(n,st,silent=false)=>{
  const el=document.getElementById('s'+n);if(!el)return;
  el.classList.remove('active','done');
  if(st)el.classList.add('active');
  if(st==='done'){el.classList.remove('active');el.classList.add('done')}
  if(!silent&&st==='active')window.Sound?.step();
};
window.resetPipe=()=>{for(let i=1;i<=5;i++)window.setStep(i,null,true)};
window.showModal=(t,b)=>{
  document.getElementById('modalTitle').textContent=t;
  document.getElementById('modalBody').textContent=b;
  document.getElementById('modalBg').classList.add('show');
  window.Sound?.error();
};
window.hideModal=()=>{
  document.getElementById('modalBg').classList.remove('show');
  window.Sound?.click();
};
JS_EOF

cat > "$WEB/core/native.js" <<'JS_EOF'
window.Native=(()=>{
  function isIOS(){return !!(window.webkit?.messageHandlers?.aimwrapper)}
  function isAndroid(){return !!(window.AimWrapperNative?.execute)}
  function isAvailable(){return isIOS()||isAndroid()}
  let mockMode=false;
  function call(action,payload,opts){
    const msg={action,payload:payload||{},ts:Date.now()};
    const expectReply=opts?.expectReply!==false;
    window.LOG(`→ ${action}`,'nat');
    try{
      if(isIOS()){window.webkit.messageHandlers.aimwrapper.postMessage(msg);return true}
      if(isAndroid()){window.AimWrapperNative.execute(JSON.stringify(msg));return true}
    }catch(e){window.LOG(`call err: ${e.message}`,'err')}
    mockMode=true;
    window.LOG(`[mock] ${action}`,'warn');
    if(expectReply){
      setTimeout(()=>{
        window.AimWrapperCallback({event:'mock_reply',ok:true,action,message:'no native bridge'});
      },60);
    }
    return false;
  }
  return {call,isAvailable,isMock:()=>mockMode,isIOS,isAndroid};
})();
JS_EOF

cat > "$WEB/core/state.js" <<'JS_EOF'
window.State={
  master:false,tun:true,dns:true,
  autoLaunch:true,autoActivate:true,autoExecute:true,autoRecover:false,
  features:{},offsets:{},
  setFeature(key,value,offset){
    this.features[key]=value;
    if(offset)this.offsets[key]=offset;
    if(this.master){
      window.Native.call('update_state',{key,value,offset:offset||this.offsets[key]||''});
    }
  },
  snapshot(){
    return {
      features:{...this.features},
      offsets:{...this.offsets},
      flags:{tun:this.tun,dns:this.dns,autoLaunch:this.autoLaunch,
             autoActivate:this.autoActivate,autoExecute:this.autoExecute,autoRecover:this.autoRecover}
    };
  }
};
window.SINGBOX_CONFIG=JSON.parse(document.getElementById('singbox-config').textContent);
window.AIM_CONFIG=JSON.parse(document.getElementById('aim-config').textContent);
JS_EOF

cat > "$WEB/core/bridge.js" <<'JS_EOF'
window.AimWrapperCallback=function(json){
  try{
    const msg=typeof json==='string'?JSON.parse(json):json;
    window.LOG(`← ${msg.event}`,msg.ok?'nat':'err');
    if(msg.message)window.LOG(`  ${msg.message}`,msg.ok?'':'err');
    const h=window.Bridge?.routes?.[msg.event];
    if(h){h(msg);return}
    if(msg.event!=='mock_reply')window.LOG(`  (no handler for ${msg.event})`,'warn');
  }catch(e){window.LOG(`cb err: ${e.message}`,'err')}
};
window.Bridge={routes:{
  ready:(m)=>window.LOG(`native ready v${m.version}`,'ok'),
  singbox_written:(m)=>{window.setStep(2,'done');window.setStep(3,'active');window.LOG(`JSON ghi vào ${m.path}`,'ok')},
  singbox_launched:()=>{window.Sound?.success();window.setStep(3,'done');window.LOG('Yêu cầu import Sing-box đã gửi','ok')},
  singbox_activated:(m)=>{
    if(!m.ok){window.setStatus('error','err');window.setStep(4,'done');window.showModal('Không thể bật VPN',m.message||'Tunnel toggle fail');return}
    window.Sound?.on();window.setStep(4,'done');window.setStep(5,'active');
    window.LOG(m.message||'Tunnel đã bật','ok');
    if(window.State.autoExecute)window.Engine?.start();
    setTimeout(()=>{
      window.setStep(5,'done');window.setStatus('running','on');window.Sound?.success();
      if(window.State.autoExecute)window.Engine?.launchGame();
    },600);
  },
  status:(m)=>window.LOG(`Sing-box: ${m.singBoxInstalled?'available':'unavailable'}`,m.singBoxInstalled?'ok':'warn'),
  started:(m)=>{window.setStatus('running','on');window.LOG(`engine started · active=${m.active??'?'}`,'ok')},
  stopped:()=>{window.setStatus('idle');window.LOG('engine stopped','warn')},
  state_updated:(m)=>window.LOG(`state ${m.key}=${m.value}`,'info'),
  snapshot:(m)=>window.LOG(`snapshot: ${JSON.stringify(m.data).slice(0,120)}...`,'info'),
  game_launched:(m)=>{window.LOG(`game: ${m.bundle}`,m.ok?'ok':'warn');if(m.ok)window.Sound?.launch()},
  attached:(m)=>{window.LOG(`FF attached pid=${m.pid}`,'ok');window.Sound?.success()},
  error:(m)=>{
    window.setStatus('error','err');window.Sound?.error();
    window.setStep(2,'done');window.setStep(3,'done');window.setStep(4,'done');
    window.showModal('Lỗi',m.message||'unknown');
  },
  unknown:(m)=>window.LOG(`unhandled: ${m.message}`,'warn'),
  mock_reply:(m)=>window.LOG(`  mock reply for ${m.action}`,'warn')
}};
JS_EOF

cat > "$WEB/core/ui.js" <<'JS_EOF'
window.UI={
  accordion({id,icon,color,name,sub,count,rows}){
    const el=document.createElement('div');
    el.className='acc';
    el.id=id;
    el.innerHTML=`
      <div class="acc-head">
        <div class="acc-title">
          <div class="acc-ico ${color}"><span class="ic"><svg><use href="#${icon}"/></svg></span></div>
          <div><div class="acc-name">${name}</div><div class="acc-sub">${sub}</div></div>
        </div>
        ${count!==false?`<span class="acc-count" id="cnt-${id}">0/${rows.length}</span>`:''}
        <span class="acc-arrow ic"><svg><use href="#i-chev"/></svg></span>
      </div>
      <div class="acc-body"><div class="acc-inner" id="${id}-inner"></div></div>
    `;
    document.getElementById('module-container').appendChild(el);
    el.querySelector('.acc-head').addEventListener('click',()=>{
      window.Sound?.tap();el.classList.toggle('open');
    });
    return el;
  },
  row(parentId,{id,label,desc}){
    const wrap=document.createElement('div');
    wrap.className='row';
    wrap.innerHTML=`
      <div class="row-info">
        <div class="row-name">${label}</div>
        <div class="row-desc">${desc}</div>
      </div>
      <div class="tog"><input type="checkbox" id="${id}"><label for="${id}"></label></div>
    `;
    document.getElementById(parentId+'-inner').appendChild(wrap);
    return wrap.querySelector('input');
  },
  updateCount(accId,ids){
    const el=document.getElementById('cnt-'+accId);
    if(!el)return;
    const on=ids.filter(id=>document.getElementById(id)?.checked).length;
    el.textContent=`${on}/${ids.length}`;
    el.classList.toggle('active',on>0);
  }
};
JS_EOF

# =========================================================
# 6. web/modules/*.js
# =========================================================
log "Sinh module JS"

cat > "$WEB/modules/singbox.js" <<'JS_EOF'
window.SingBox=(()=>{
  const rows=[
    {id:'tunToggle',key:'tun',label:'VPN Tunnel',desc:'inbounds.tun-in · gvisor'},
    {id:'dnsToggle',key:'dns',label:'DNS over HTTPS',desc:'dns.final = cloudflare-doh'}
  ];
  function render(){
    UI.accordion({id:'acc-singbox',icon:'i-globe',color:'blue',name:'Sing-box',sub:'Proxy · DNS · Tunnel',rows});
    for(const r of rows){
      const el=UI.row('acc-singbox',r);
      el.checked=State[r.key];
      el.addEventListener('change',e=>{
        State[r.key]=e.target.checked;
        Sound.toggle(e.target.checked);
        LOG(`singbox.${r.key}=${e.target.checked}`,e.target.checked?'ok':'warn');
        UI.updateCount('acc-singbox',rows.map(x=>x.id));
      });
    }
    UI.updateCount('acc-singbox',rows.map(x=>x.id));
  }
  function buildPayload(){
    const sb=JSON.parse(JSON.stringify(SINGBOX_CONFIG));
    if(!State.tun)sb.inbounds=sb.inbounds.filter(i=>i.type!=='tun');
    if(!State.dns){sb.dns.final='local';sb.dns.servers=sb.dns.servers.filter(s=>s.type==='udp')}
    return sb;
  }
  function enter(){
    resetPipe();Sound.launch();
    LOG('▶ VÀO SING-BOX','ok');
    setStep(1,'active');setStatus('building...','warn');
    const sb=buildPayload();
    const j=JSON.stringify(sb,null,2);
    LOG(`config ${j.length}B`,'ok');
    setStep(1,'done');setStep(2,'active');
    Native.call('enter_singbox',{json:j,autoActivate:State.autoActivate,autoLaunch:State.autoLaunch});
  }
  function activate(){
    LOG('▶ BẬT VPN','ok');Sound.on();setStep(4,'active');
    Native.call('sfi_activate',{});
  }
  return {render,enter,activate,buildPayload,rows};
})();
JS_EOF

cat > "$WEB/modules/aim.js" <<'JS_EOF'
window.Aim=(()=>{
  const rows=[
    {id:'aimlockToggle',key:'aimlock',label:'Aimlock',desc:'Bones.Head 0x494'},
    {id:'aimneckToggle',key:'aimneck',label:'Aimneck',desc:'Head 0x494 + bias -0.08'},
    {id:'aimbodyToggle',key:'aimbody',label:'Aimbody',desc:'Spine 0x49C · fallback Hip 0x498'},
    {id:'aimbotVisibleToggle',key:'aimbotVisible',label:'AimbotVisible',desc:'Offsets.AimbotVisible 0x4A4'},
    {id:'aimRotationToggle',key:'aimRotation',label:'AimRotation',desc:'Offsets.AimRotation 0x2E0'},
    {id:'silentFiringToggle',key:'silentFiring',label:'SilentFiring',desc:'Offsets.SilentFiring 0x6C0'},
    {id:'silentHitToggle',key:'silentHit',label:'SilentHit',desc:'Offsets.SilentHit 0x7D0'},
    {id:'silentsToggle',key:'silents',label:'Silents',desc:'Offsets.Silents 0x38'},
    {id:'silentrToggle',key:'silentr',label:'Silentr',desc:'Offsets.Silentr 0x2C'}
  ];
  function render(){
    UI.accordion({id:'acc-aim',icon:'i-target',color:'purple',name:'Aim',sub:'Aimlock · Aimneck · Silent',rows});
    for(const r of rows){
      const el=UI.row('acc-aim',r);
      el.addEventListener('change',e=>{
        Sound.toggle(e.target.checked);
        LOG(`aim.${r.key}=${e.target.checked}  [${r.desc}]`,e.target.checked?'ok':'warn');
        State.setFeature(r.key,e.target.checked,r.desc);
        UI.updateCount('acc-aim',rows.map(x=>x.id));
      });
    }
    UI.updateCount('acc-aim',rows.map(x=>x.id));
  }
  return {render,rows};
})();
JS_EOF

cat > "$WEB/modules/weapon.js" <<'JS_EOF'
window.Weapon=(()=>{
  const rows=[
    {id:'weaponRecoilToggle',key:'weaponRecoil',label:'WeaponRecoil',desc:'0xC → 0'},
    {id:'noReloadToggle',key:'noReload',label:'NoReload',desc:'0x99 → 1'},
    {id:'unlimitedAmmoToggle',key:'unlimitedAmmo',label:'UnlimitedAmmo',desc:'Offsets.UnlimitedAmmo 0xE0'},
    {id:'isFiringToggle',key:'isFiring',label:'IsFiring',desc:'Offsets.IS_FIRING 0x540'},
    {id:'weaponInfoToggle',key:'weaponInfo',label:'WeaponInfo',desc:'Offsets.WeaponInfo 0x64'},
    {id:'weaponIDToggle',key:'weaponID',label:'WeaponID',desc:'Offsets.WeaponID 0x14'},
    {id:'weaponOnHandToggle',key:'weaponOnHand',label:'WeaponOnHand',desc:'Offsets.WeaponOnHand 0x54'},
    {id:'gunTipToggle',key:'gunTip',label:'GunTipPosition',desc:'Offsets.guntipposition 0x38'},
    {id:'bulletHitToggle',key:'bulletHit',label:'BulletHit',desc:'Offsets.bullet_hit 0x2C'}
  ];
  function render(){
    UI.accordion({id:'acc-weapon',icon:'i-gun',color:'pink',name:'Weapon',sub:'Recoil · Reload · Ammo',rows});
    for(const r of rows){
      const el=UI.row('acc-weapon',r);
      el.addEventListener('change',e=>{
        Sound.toggle(e.target.checked);
        LOG(`weapon.${r.key}=${e.target.checked}  [${r.desc}]`,e.target.checked?'ok':'warn');
        State.setFeature(r.key,e.target.checked,r.desc);
        UI.updateCount('acc-weapon',rows.map(x=>x.id));
      });
    }
    UI.updateCount('acc-weapon',rows.map(x=>x.id));
  }
  return {render,rows};
})();
JS_EOF

cat > "$WEB/modules/esp.js" <<'JS_EOF'
window.ESP=(()=>{
  const rows=[
    {id:'playerNameToggle',key:'playerName',label:'Player_Name',desc:'Offsets.Player_Name 0x380'},
    {id:'playerIsDeadToggle',key:'playerIsDead',label:'Player_IsDead',desc:'Offsets.Player_IsDead 0x7C'},
    {id:'avatarVisibleToggle',key:'avatarVisible',label:'Avatar_IsVisible',desc:'Offsets.Avatar_IsVisible 0xC1'},
    {id:'avatarTeamToggle',key:'avatarTeam',label:'Avatar_Data_IsTeam',desc:'Offsets.Avatar_Data_IsTeam 0x74'},
    {id:'isBotToggle',key:'isBot',label:'isBotOffs',desc:'Offsets.isBotOffs 0x1B0'},
    {id:'headColliderToggle',key:'headCollider',label:'HeadCollider',desc:'Offsets.HeadCollider 0x360'}
  ];
  function render(){
    UI.accordion({id:'acc-esp',icon:'i-eye',color:'teal',name:'ESP',sub:'Names · Team · Bot',rows});
    for(const r of rows){
      const el=UI.row('acc-esp',r);
      el.addEventListener('change',e=>{
        Sound.toggle(e.target.checked);
        LOG(`esp.${r.key}=${e.target.checked}  [${r.desc}]`,e.target.checked?'ok':'warn');
        State.setFeature(r.key,e.target.checked,r.desc);
        UI.updateCount('acc-esp',rows.map(x=>x.id));
      });
    }
    UI.updateCount('acc-esp',rows.map(x=>x.id));
  }
  return {render,rows};
})();
JS_EOF

cat > "$WEB/modules/map.js" <<'JS_EOF'
window.MapMod=(()=>{
  const rows=[
    {id:'viewMatrixToggle',key:'viewMatrix',label:'ViewMatrix',desc:'Offsets.ViewMatrix 0xE4'},
    {id:'fixedDeltaToggle',key:'fixedDelta',label:'FixedDeltaTime',desc:'Offsets.FixedDeltaTime 0x24'},
    {id:'snowDashToggle',key:'snowDash',label:'InSnowSlideWayDashing',desc:'0x15E8'},
    {id:'bigMapToggle',key:'bigMap',label:'BigMap',desc:'Offsets.BigMap 0x218'},
    {id:'mapMarkToggle',key:'mapMark',label:'MapMarkController',desc:'Offsets.MapMarkController 0x90'},
    {id:'markedToggle',key:'marked',label:'marked',desc:'Offsets.marked 0x58'}
  ];
  function render(){
    UI.accordion({id:'acc-map',icon:'i-map',color:'orange',name:'Map / Movement',sub:'View · Dash · BigMap',rows});
    for(const r of rows){
      const el=UI.row('acc-map',r);
      el.addEventListener('change',e=>{
        Sound.toggle(e.target.checked);
        LOG(`map.${r.key}=${e.target.checked}  [${r.desc}]`,e.target.checked?'ok':'warn');
        State.setFeature(r.key,e.target.checked,r.desc);
        UI.updateCount('acc-map',rows.map(x=>x.id));
      });
    }
    UI.updateCount('acc-map',rows.map(x=>x.id));
  }
  return {render,rows};
})();
JS_EOF

cat > "$WEB/modules/engine.js" <<'JS_EOF'
window.Engine=(()=>{
  function start(){
    const snap=State.snapshot();
    Native.call('start_all',{
      aim:{features:snap.features,offsets:snap.offsets},
      flags:snap.flags
    });
  }
  function stop(){Native.call('stop_all',{})}
  function launchGame(bundle='com.dts.freefireth'){Native.call('launch_game',{bundle})}
  return {start,stop,launchGame};
})();
JS_EOF

cat > "$WEB/modules/auto.js" <<'JS_EOF'
window.Auto=(()=>{
  const rows=[
    {id:'autoLaunchToggle',key:'autoLaunch',label:'Auto-launch Sing-box',desc:'Bật SFI khi master on'},
    {id:'autoActivateToggle',key:'autoActivate',label:'Auto-activate VPN',desc:'sing-box://toggle sau 3s'},
    {id:'autoExecuteToggle',key:'autoExecute',label:'Auto-execute on game',desc:'poll FF → tự attach engine'},
    {id:'autoRecoverToggle',key:'autoRecover',label:'Auto-recover',desc:'Tự re-attach khi FF restart'}
  ];
  function render(){
    UI.accordion({id:'acc-auto',icon:'i-run',color:'purple',name:'Auto Execute',sub:'Tắt chạy khi vào game',rows});
    for(const r of rows){
      const el=UI.row('acc-auto',r);
      el.checked=State[r.key];
      el.addEventListener('change',e=>{
        State[r.key]=e.target.checked;
        Sound.toggle(e.target.checked);
        LOG(`auto.${r.key}=${e.target.checked}`);
      });
    }
    document.getElementById('acc-auto').classList.add('open');
  }
  return {render,rows};
})();
JS_EOF

cat > "$WEB/modules/log.js" <<'JS_EOF'
window.LogMod=(()=>{
  function render(){
    const el=document.createElement('div');
    el.className='acc';
    el.id='acc-log';
    el.innerHTML=`
      <div class="acc-head">
        <div class="acc-title">
          <div class="acc-ico gray"><span class="ic"><svg><use href="#i-doc"/></svg></span></div>
          <div><div class="acc-name">Log</div><div class="acc-sub">Hoạt động và ghi nhận lỗi</div></div>
        </div>
        <span class="acc-arrow ic"><svg><use href="#i-chev"/></svg></span>
      </div>
      <div class="acc-body"><div class="acc-inner" style="padding:12px"><div class="log" id="log"></div></div></div>
    `;
    document.getElementById('module-container').appendChild(el);
    el.querySelector('.acc-head').addEventListener('click',()=>{
      window.Sound?.tap();el.classList.toggle('open');
    });
  }
  function clear(){const e=document.getElementById('log');if(e)e.innerHTML=''}
  function exportText(){const e=document.getElementById('log');return e?e.innerText:''}
  return {render,clear,exportText};
})();
JS_EOF

# =========================================================
# 7. web/boot.js
# =========================================================
log "Sinh web/boot.js"
cat > "$WEB/boot.js" <<'JS_EOF'
(function boot(){
  'use strict';
  const renderOrder=[
    ['Auto','render'],['SingBox','render'],['Aim','render'],
    ['Weapon','render'],['ESP','render'],['MapMod','render'],['LogMod','render']
  ];
  for(const [mod,fn] of renderOrder){
    const m=window[mod];
    if(m&&typeof m[fn]==='function'){try{m[fn]()}catch(e){console.error(`[boot] ${mod}.${fn}`,e)}}
    else console.warn(`[boot] missing ${mod}.${fn}`);
  }

  const mEl=document.getElementById('masterToggle');
  const mCard=document.getElementById('masterCard');
  const mTitle=document.getElementById('masterTitle');
  const mSub=document.getElementById('masterSub');
  if(mEl){
    mEl.addEventListener('change',e=>{
      State.master=e.target.checked;
      mCard.classList.toggle('on',State.master);
      Sound.toggle(State.master);
      if(State.master){
        mTitle.textContent='Đang chạy';
        mSub.textContent='Engine chạy · vào game là tự động';
        LOG('=== MASTER ON ===','ok');
        if(State.autoLaunch)SingBox.enter();
        if(State.autoExecute)Engine.start();
        setStatus('running','on');
      } else {
        mTitle.textContent='Chạm để chạy';
        mSub.textContent='Auto: config → SFI → VPN → engine → vào game là chạy';
        LOG('=== MASTER OFF ===','warn');
        Engine.stop();
        setStatus('idle');
        resetPipe();
      }
    });
  }

  const btnSfi=document.getElementById('btnSfi');
  const btnVpn=document.getElementById('btnVpn');
  if(btnSfi)btnSfi.addEventListener('click',()=>SingBox.enter());
  if(btnVpn)btnVpn.addEventListener('click',()=>SingBox.activate());

  const fab=document.getElementById('soundFab');
  const fabIcon=document.getElementById('fabIcon');
  if(fab&&fabIcon){
    fab.addEventListener('click',()=>{
      const on=!Sound.isEnabled();
      Sound.setEnabled(on);
      fabIcon.innerHTML=`<svg><use href="${on?'#i-vol':'#i-mute'}"/></svg>`;
      fab.classList.toggle('muted',!on);
      LOG(`sound=${on}`,'snd');
    });
  }

  const modalOk=document.getElementById('modalOk');
  if(modalOk)modalOk.addEventListener('click',hideModal);

  document.body.addEventListener('touchstart',()=>{
    const A=window.AudioContext||window.webkitAudioContext;
    if(A)new A().resume();
  },{once:true});

  LOG('AimWrapper v12 · modular','ok');
  LOG(`sing-box: ${SINGBOX_CONFIG.dns.servers.length} DNS · ${SINGBOX_CONFIG.inbounds.length} inbounds`);
  LOG(`aim: ${Object.keys(AIM_CONFIG.Offsets).length} offsets · ${Object.keys(AIM_CONFIG.Bones).length} bones`);
  const fc=(Aim?.rows?.length||0)+(Weapon?.rows?.length||0)+(ESP?.rows?.length||0)+(MapMod?.rows?.length||0)+(SingBox?.rows?.length||0)+(Auto?.rows?.length||0);
  LOG(`features: ${fc} · auto: ${Auto?.rows?.length||0}`);

  if(Native.isIOS())LOG('bridge: iOS WKWebView','ok');
  else if(Native.isAndroid())LOG('bridge: Android WebView','ok');
  else LOG('bridge: MOCK','warn');

  Native.call('query_status',{});
  Native.call('ready',{version:'12.0'});

  setInterval(()=>{
    if(State.master&&State.autoRecover)Native.call('engine_snapshot',{},{expectReply:false});
  },15000);

  document.addEventListener('visibilitychange',()=>{
    if(!document.hidden&&State.master){
      LOG('app foreground · re-check','info');
      Native.call('query_status',{},{expectReply:false});
    }
  });
})();
JS_EOF

# =========================================================
# 8. AimWrapper.html
# =========================================================
log "Sinh AimWrapper.html"
cat > "$SRC/AimWrapper.html" <<'HTML_EOF'
<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>AimWrapper</title>
<link rel="stylesheet" href="web/style.css">
</head>
<body>

<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>
  <symbol id="i-logo" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.8"/><circle cx="12" cy="12" r="3.5" stroke="currentColor" stroke-width="1.8"/><line x1="12" y1="1" x2="12" y2="5" stroke="currentColor" stroke-width="1.8"/><line x1="12" y1="19" x2="12" y2="23" stroke="currentColor" stroke-width="1.8"/><line x1="1" y1="12" x2="5" y2="12" stroke="currentColor" stroke-width="1.8"/><line x1="19" y1="12" x2="23" y2="12" stroke="currentColor" stroke-width="1.8"/></symbol>
  <symbol id="i-power" viewBox="0 0 24 24"><path d="M12 3v9" stroke="currentColor" stroke-width="2"/><path d="M6.5 6.5a8 8 0 1 0 11 0" stroke="currentColor" stroke-width="2"/></symbol>
  <symbol id="i-globe" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9.2" stroke="currentColor" stroke-width="1.8"/><ellipse cx="12" cy="12" rx="4" ry="9.2" stroke="currentColor" stroke-width="1.8"/><line x1="3" y1="9" x2="21" y2="9" stroke="currentColor" stroke-width="1.6"/><line x1="3" y1="15" x2="21" y2="15" stroke="currentColor" stroke-width="1.6"/></symbol>
  <symbol id="i-target" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.8"/><circle cx="12" cy="12" r="5.5" stroke="currentColor" stroke-width="1.8"/><circle cx="12" cy="12" r="1.5" fill="currentColor" stroke="none"/></symbol>
  <symbol id="i-gun" viewBox="0 0 24 24"><path d="M3 9h15l3 3v2h-3l-1 3h-3l-1-3h-4v3H6v-3H3z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/></symbol>
  <symbol id="i-eye" viewBox="0 0 24 24"><path d="M2 12s3.8-7 10-7 10 7 10 7-3.8 7-10 7S2 12 2 12z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><circle cx="12" cy="12" r="3.2" stroke="currentColor" stroke-width="1.8"/></symbol>
  <symbol id="i-map" viewBox="0 0 24 24"><path d="M3 6l6-2 6 2 6-2v14l-6 2-6-2-6 2V6z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><line x1="9" y1="4" x2="9" y2="20" stroke="currentColor" stroke-width="1.6"/><line x1="15" y1="4" x2="15" y2="20" stroke="currentColor" stroke-width="1.6"/></symbol>
  <symbol id="i-doc" viewBox="0 0 24 24"><path d="M6 2h9l5 5v15a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M15 2v5h5" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></symbol>
  <symbol id="i-vol" viewBox="0 0 24 24"><path d="M3 9v6h4l6 4V5L7 9H3z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M16.5 8.5a5 5 0 0 1 0 7" stroke="currentColor" stroke-width="1.8"/><path d="M19 6a8.5 8.5 0 0 1 0 12" stroke="currentColor" stroke-width="1.8"/></symbol>
  <symbol id="i-mute" viewBox="0 0 24 24"><path d="M3 9v6h4l6 4V5L7 9H3z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><line x1="16" y1="9" x2="22" y2="15" stroke="currentColor" stroke-width="1.8"/><line x1="22" y1="9" x2="16" y2="15" stroke="currentColor" stroke-width="1.8"/></symbol>
  <symbol id="i-chev" viewBox="0 0 24 24"><path d="M9 6l6 6-6 6" stroke="currentColor" stroke-width="2.2"/></symbol>
  <symbol id="i-slider" viewBox="0 0 24 24"><line x1="4" y1="6" x2="20" y2="6" stroke="currentColor" stroke-width="1.8"/><circle cx="9" cy="6" r="2.2" fill="currentColor" stroke="none"/><line x1="4" y1="12" x2="20" y2="12" stroke="currentColor" stroke-width="1.8"/><circle cx="15" cy="12" r="2.2" fill="currentColor" stroke="none"/><line x1="4" y1="18" x2="20" y2="18" stroke="currentColor" stroke-width="1.8"/><circle cx="11" cy="18" r="2.2" fill="currentColor" stroke="none"/></symbol>
  <symbol id="i-disk" viewBox="0 0 24 24"><path d="M4 4h13l3 3v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><rect x="8" y="4" width="8" height="6" stroke="currentColor" stroke-width="1.6"/><rect x="7" y="14" width="10" height="6" stroke="currentColor" stroke-width="1.6"/></symbol>
  <symbol id="i-shield" viewBox="0 0 24 24"><path d="M12 2.5l8 3v6c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10v-6l8-3z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M9 12l2 2 4-4" stroke="currentColor" stroke-width="2"/></symbol>
  <symbol id="i-run" viewBox="0 0 24 24"><path d="M14 3c4 0 7 3 7 7 0 3-2 5-4 6l-1 5-2-2-3 1-1-3-3-1 1-3-2-2 5-1c1-2 3-4 6-4z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><circle cx="15" cy="9" r="1.6" stroke="currentColor" stroke-width="1.6"/></symbol>
</defs></svg>

<button class="fab muted" id="soundFab"><span class="ic" id="fabIcon"><svg><use href="#i-mute"/></svg></span></button>

<div class="top">
  <div class="brand">
    <div class="brand-logo"><span class="ic"><svg><use href="#i-logo"/></svg></span></div>
    <div class="brand-text"><h1>AimWrapper</h1><p>v12 · modular</p></div>
  </div>
  <div class="status"><span class="dot" id="dot"></span><span id="stat">idle</span></div>
</div>

<div class="master" id="masterCard">
  <div class="master-icon"><span class="ic"><svg><use href="#i-power"/></svg></span></div>
  <div class="master-info">
    <h2 id="masterTitle">Chạm để chạy</h2>
    <p id="masterSub">Auto: config → SFI → VPN → engine → vào game là chạy</p>
  </div>
  <div class="switch"><input type="checkbox" id="masterToggle"><label for="masterToggle"></label></div>
</div>

<div class="quick">
  <button class="quick-btn primary" id="btnSfi"><span class="ic"><svg><use href="#i-globe"/></svg></span>Mở Sing-box</button>
  <button class="quick-btn success" id="btnVpn"><span class="ic"><svg><use href="#i-shield"/></svg></span>Bật VPN</button>
</div>

<div class="pipe">
  <div class="p-step" id="s1"><span class="pi ic"><svg><use href="#i-slider"/></svg></span>Config</div>
  <div class="p-step" id="s2"><span class="pi ic"><svg><use href="#i-disk"/></svg></span>Write</div>
  <div class="p-step" id="s3"><span class="pi ic"><svg><use href="#i-globe"/></svg></span>SFI</div>
  <div class="p-step" id="s4"><span class="pi ic"><svg><use href="#i-shield"/></svg></span>VPN</div>
  <div class="p-step" id="s5"><span class="pi ic"><svg><use href="#i-run"/></svg></span>Run</div>
</div>

<div id="module-container"></div>

<div class="ver">AimWrapper · v12 · Tấn Dũng</div>

<div class="modal-bg" id="modalBg">
  <div class="modal">
    <h3 id="modalTitle">Thông báo</h3>
    <p id="modalBody">Thông báo lỗi</p>
    <button id="modalOk">Đã hiểu</button>
  </div>
</div>

<script type="application/json" id="singbox-config">
{
  "log": { "level": "warn", "timestamp": true },
  "dns": {
    "servers": [
      { "type": "udp", "tag": "local", "server": "1.1.1.1" },
      { "type": "udp", "tag": "local-alt", "server": "8.8.8.8" },
      { "type": "https", "tag": "cloudflare-doh", "server": "1.1.1.1", "domain_resolver": "local" },
      { "type": "https", "tag": "google-doh", "server": "8.8.8.8", "domain_resolver": "local-alt" }
    ],
    "final": "cloudflare-doh", "strategy": "prefer_ipv4"
  },
  "inbounds": [
    { "type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30","fdfe:dcba:9876::1/126"], "mtu": 9000, "auto_route": true, "stack": "gvisor", "udp_timeout": "5m" },
    { "type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 2080 }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" }, { "type": "block", "tag": "block" } ],
  "route": { "final": "direct", "auto_detect_interface": true },
  "experimental": { "clash_api": { "external_controller": "127.0.0.1:9090" } }
}
</script>

<script type="application/json" id="aim-config">
{
  "Offsets": {
    "InitBase":"0xA342EFC","StaticClass":"0x5C","LocalPlayer":"0xC8","Player_Data":"0x78",
    "AvatarManager":"0x320","Avatar":"0xD0","Avatar_Data":"0x30","Avatar_Data_IsTeam":"0x74",
    "Avatar_IsVisible":"0xC1","AimRotation":"0x2E0","AimbotVisible":"0x4A4",
    "SilentFiring":"0x6C0","SilentHit":"0x7D0","Silents":"0x38","Silentr":"0x2C",
    "Weapon":"0x2C0","WeaponData":"0x68","WeaponRecoil":"0xC","NoReload":"0x99",
    "IS_FIRING":"0x540","WeaponInfo":"0x64","WeaponID":"0x14","WeaponOnHand":"0x54",
    "guntipposition":"0x38","bullet_hit":"0x2C","UnlimitedAmmo":"0xE0",
    "Player_Name":"0x380","Player_IsDead":"0x7C","isBotOffs":"0x1B0","HeadCollider":"0x360",
    "ViewMatrix":"0xE4","FixedDeltaTime":"0x24","InSnowSlideWayDashing":"0x15E8",
    "BigMap":"0x218","MapMarkController":"0x90","marked":"0x58"
  },
  "Bones": {
    "Head":"0x494","Spine":"0x49C","Hip":"0x498","Root":"0x4A8",
    "LeftAnkle":"0x4B0","RightAnkle":"0x4B4","LeftFoot":"0x4B8","RightFoot":"0x4BC",
    "LeftShoulder":"0x4C8","RightShoulder":"0x4CC","RightHand":"0x4D0","LeftHand":"0x4D4",
    "RightElbow":"0x4D8","LeftElbow":"0x4DC"
  }
}
</script>

<script src="web/core/sound.js"></script>
<script src="web/core/log.js"></script>
<script src="web/core/native.js"></script>
<script src="web/core/state.js"></script>
<script src="web/core/bridge.js"></script>
<script src="web/core/ui.js"></script>

<script src="web/modules/auto.js"></script>
<script src="web/modules/singbox.js"></script>
<script src="web/modules/aim.js"></script>
<script src="web/modules/weapon.js"></script>
<script src="web/modules/esp.js"></script>
<script src="web/modules/map.js"></script>
<script src="web/modules/engine.js"></script>
<script src="web/modules/log.js"></script>

<script src="web/boot.js"></script>
</body>
</html>
HTML_EOF

# =========================================================
# 9. project.yml
# =========================================================
log "Sinh project.yml"
cat > "$ROOT/project.yml" <<YAML_EOF
name: SingBoxWrapper
options:
  bundleIdPrefix: com.tandung
  deploymentTarget:
    iOS: "16.0"
  createIntermediateGroups: true
  developmentLanguage: en
  xcodeVersion: "15.0"

settings:
  base:
    SWIFT_VERSION: "5.0"
    IPHONEOS_DEPLOYMENT_TARGET: "16.0"
    TARGETED_DEVICE_FAMILY: "1"
    ENABLE_BITCODE: "NO"
    GENERATE_INFOPLIST_FILE: "NO"
    CODE_SIGN_STYLE: "$CODE_SIGN_STYLE"
    DEVELOPMENT_TEAM: "$TEAM_ID"
    PRODUCT_BUNDLE_IDENTIFIER: "$BUNDLE_ID"
    INFOPLIST_FILE: "SingBoxWrapper/Info.plist"
    CODE_SIGN_ENTITLEMENTS: "SingBoxWrapper/SingBoxWrapper.entitlements"
    SWIFT_OPTIMIZATION_LEVEL: "-O"
    GCC_OPTIMIZATION_LEVEL: "s"
    ONLY_ACTIVE_ARCH: "NO"
    VALIDATE_PRODUCT: "YES"

targets:
  SingBoxWrapper:
    type: application
    platform: iOS
    sources:
      - path: SingBoxWrapper
        includes:
          - "*.swift"
          - "*.plist"
          - "*.entitlements"
      - path: SingBoxWrapper/AimWrapper.html
        buildPhase: resources
      - path: SingBoxWrapper/web
        type: folder
        buildPhase: resources
    settings:
      base:
        PRODUCT_NAME: SingBoxWrapper
        CURRENT_PROJECT_VERSION: "12"
        MARKETING_VERSION: "12.0"
    info:
      path: SingBoxWrapper/Info.plist
    entitlements:
      path: SingBoxWrapper/SingBoxWrapper.entitlements
YAML_EOF

# =========================================================
# 10. Generate + build
# =========================================================
log "Chạy xcodegen"
cd "$ROOT"
xcodegen generate --spec project.yml --project "$PROJ" >/dev/null
[[ -d "$PROJ" ]] || die "xcodegen fail"

if [[ -z "$TEAM_ID" ]]; then
  warn "TEAM_ID chưa set — auto-detect"
  TEAM_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -oE '\([A-Z0-9]{10}\)' | head -1 | tr -d '()' || true)
  [[ -n "$TEAM_ID" ]] && log "Auto TEAM_ID=$TEAM_ID" || warn "Không có TEAM_ID — signing sẽ fail"
fi

log "Archive arm64 Release"
xcodebuild \
  -project "$PROJ" \
  -scheme SingBoxWrapper \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED" \
  -archivePath "$ARCHIVE" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE="$CODE_SIGN_STYLE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  clean archive 2>&1 | tail -40

[[ -d "$ARCHIVE" ]] || die "Archive thất bại"

log "Kiểm tra resource bundle"
APP_PATH="$ARCHIVE/Products/Applications/SingBoxWrapper.app"
for f in AimWrapper.html web/style.css web/boot.js web/core/sound.js web/core/ui.js web/modules/aim.js web/modules/log.js; do
  [[ -f "$APP_PATH/$f" ]] || die "Thiếu $f trong bundle"
done
log "Resource OK"

log "Sinh ExportOptions.plist"
cat > "$BUILD/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$EXPORT_METHOD</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>stripSwiftSymbols</key><true/>
  <key>compileBitcode</key><false/>
  <key>destination</key><string>export</string>
</dict>
</plist>
EOF

log "Export IPA ($EXPORT_METHOD)"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD/ExportOptions.plist" \
  -allowProvisioningUpdates 2>&1 | tail -30

IPA=$(find "$EXPORT_DIR" -name "*.ipa" -maxdepth 1 | head -1)
[[ -n "$IPA" ]] || die "Không có IPA"

log "XONG"
ls -lh "$IPA"

cat <<EOF

─────────────────────────────────────────────
IPA: $IPA
Cài: Sideloadly / AltStore / TrollStore
─────────────────────────────────────────────
EOF