#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CodexSwitch"
BUNDLE_ID="in.ashwingopalsamy.codexswitch"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SOURCE_INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/Codex Switcher.icon"
ICON_NAME="Codex Switcher"
ICON_IMAGE="$ICON_SOURCE/Assets/svgviewer-output (13) (1).png"

[[ -d "$ICON_SOURCE" && ! -L "$ICON_SOURCE" ]] || { echo "Icon Composer source is missing or a symlink" >&2; exit 2; }
[[ -f "$ICON_IMAGE" && ! -L "$ICON_IMAGE" ]] || { echo "Icon Composer artwork is missing or a symlink" >&2; exit 2; }
if /usr/bin/find "$ICON_SOURCE" -type l -print -quit | /usr/bin/grep -q .; then
  echo "Refusing an Icon Composer source containing symlinks" >&2
  exit 2
fi

existing_pids="$(pgrep -x "$APP_NAME" || true)"
if [[ -n "$existing_pids" ]]; then
  while IFS= read -r existing_pid; do
    [[ "$existing_pid" =~ ^[0-9]+$ ]] || { echo "Refusing unexpected CodexSwitch pid: $existing_pid" >&2; exit 2; }
    kill -TERM "$existing_pid" 2>/dev/null || true
  done <<< "$existing_pids"
  for _ in {1..40}; do
    still_running="$(pgrep -x "$APP_NAME" || true)"
    [[ -z "$still_running" ]] && break
    sleep 0.1
  done
fi
swift build --product "$APP_NAME"
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
ICON_WORK_DIR="$(mktemp -d /tmp/codex-switch-icon.XXXXXX)"
trap 'rm -rf "$ICON_WORK_DIR"' EXIT
ICON_COMPILED_DIR="$ICON_WORK_DIR/compiled"
mkdir -p "$ICON_COMPILED_DIR"

/usr/bin/sips \
  --cropToHeightWidth 1012 1012 \
  "$ICON_IMAGE" \
  --out "$ICON_WORK_DIR/CodexSwitchMenuBar.png" >/dev/null

xcrun actool \
  --compile "$ICON_COMPILED_DIR" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon "$ICON_NAME" \
  --output-partial-info-plist "$ICON_COMPILED_DIR/partial.plist" \
  "$ICON_SOURCE" >/dev/null

[[ -f "$ICON_COMPILED_DIR/Assets.car" ]] || { echo "actool did not produce Assets.car" >&2; exit 2; }
[[ -f "$ICON_COMPILED_DIR/$ICON_NAME.icns" ]] || { echo "actool did not produce the ICNS app icon" >&2; exit 2; }
[[ -f "$ICON_COMPILED_DIR/partial.plist" ]] || { echo "actool did not produce the icon plist" >&2; exit 2; }

if [[ "$APP_BUNDLE" != "$ROOT_DIR/dist/$APP_NAME.app" || "$SOURCE_INFO_PLIST" != "$ROOT_DIR/Resources/Info.plist" ]]; then
  echo "Refusing unexpected bundle path" >&2
  exit 2
fi

[[ -f "$SOURCE_INFO_PLIST" && ! -L "$SOURCE_INFO_PLIST" ]] || { echo "Maintained Info.plist is missing or a symlink" >&2; exit 2; }
if [[ -e "$APP_BUNDLE" || -L "$APP_BUNDLE" ]]; then
  [[ -d "$APP_BUNDLE" && ! -L "$APP_BUNDLE" ]] || { echo "Refusing unexpected bundle target" >&2; exit 2; }
  if /usr/bin/find "$APP_BUNDLE" -type l -print -quit | /usr/bin/grep -q .; then
    echo "Refusing to remove a bundle containing symlinks" >&2
    exit 2
  fi
  rm -rf "$APP_BUNDLE"
fi
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$SOURCE_INFO_PLIST" "$INFO_PLIST"
cp "$ICON_COMPILED_DIR/Assets.car" "$APP_RESOURCES/Assets.car"
cp "$ICON_COMPILED_DIR/$ICON_NAME.icns" "$APP_RESOURCES/$ICON_NAME.icns"
cp "$ICON_WORK_DIR/CodexSwitchMenuBar.png" "$APP_RESOURCES/CodexSwitchMenuBar.png"

for icon_resource in \
  "$APP_RESOURCES/Assets.car" \
  "$APP_RESOURCES/$ICON_NAME.icns" \
  "$APP_RESOURCES/CodexSwitchMenuBar.png"; do
  [[ -f "$icon_resource" && ! -L "$icon_resource" ]] || {
    echo "Required icon resource is missing or a symlink: $icon_resource" >&2
    exit 2
  }
done

[[ "$(/usr/bin/plutil -extract CFBundleIconName raw -o - "$INFO_PLIST")" == "$ICON_NAME" ]] || {
  echo "Info.plist CFBundleIconName does not match the compiled icon" >&2
  exit 2
}
[[ "$(/usr/bin/plutil -extract CFBundleIconFile raw -o - "$INFO_PLIST")" == "$ICON_NAME" ]] || {
  echo "Info.plist CFBundleIconFile does not match the compiled icon" >&2
  exit 2
}

codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    open_app
    open_app
    sleep 1
    process_count="$(pgrep -x "$APP_NAME" | wc -l | tr -d '[:space:]')"
    if [[ "$process_count" != "1" ]]; then
      echo "Expected one $APP_NAME process after repeated opens; found $process_count" >&2
      exit 1
    fi
    app_pid="$(pgrep -x "$APP_NAME")"
    [[ "$app_pid" =~ ^[0-9]+$ ]]
    lsappinfo_output="$(/usr/bin/lsappinfo info -only CFBundleIdentifier,ApplicationType,LSUIElement -app "$APP_NAME")"
    grep -q 'CFBundleIdentifier.*in.ashwingopalsamy.codexswitch' <<< "$lsappinfo_output"
    grep -q 'ApplicationType.*Foreground' <<< "$lsappinfo_output"
    ! grep -q 'LSUIElement.*true' <<< "$lsappinfo_output"
    menubar_pid="$(/usr/bin/defaults read "$BUNDLE_ID" CodexSwitchMenuBarPID 2>/dev/null || true)"
    [[ "$menubar_pid" == "$app_pid" ]]
    window_count="0"
    stable_window_samples="0"
    for _ in {1..40}; do
      window_count="$(/usr/bin/swift - <<'SWIFT'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let count = windows.filter { ($0[kCGWindowOwnerName as String] as? String) == "CodexSwitch" }.count
print(count)
SWIFT
)"
      if [[ "$window_count" == "1" ]]; then
        stable_window_samples=$((stable_window_samples + 1))
        [[ "$stable_window_samples" -ge 5 ]] && break
      else
        stable_window_samples="0"
      fi
      sleep 0.1
    done
    if [[ "$window_count" != "1" || "$stable_window_samples" -lt 5 ]]; then
      echo "Expected one stable visible management window after repeated opens; found $window_count" >&2
      exit 1
    fi
    ui_soak_seconds="${CODEX_SWITCH_UI_SOAK_SECONDS:-30}"
    [[ "$ui_soak_seconds" =~ ^[0-9]+$ ]] || { echo "CODEX_SWITCH_UI_SOAK_SECONDS must be an integer" >&2; exit 2; }
    (( ui_soak_seconds >= 1 && ui_soak_seconds <= 120 )) || { echo "CODEX_SWITCH_UI_SOAK_SECONDS must be between 1 and 120" >&2; exit 2; }
    ui_soak_samples=$((ui_soak_seconds * 4))
    for ((sample = 0; sample < ui_soak_samples; sample++)); do
      if ! kill -0 "$app_pid" 2>/dev/null; then
        echo "$APP_NAME exited during the ${ui_soak_seconds}-second idle-window soak" >&2
        exit 1
      fi
      current_pids="$(pgrep -x "$APP_NAME" || true)"
      [[ "$current_pids" == "$app_pid" ]] || {
        echo "Expected the original single $APP_NAME process throughout the idle-window soak" >&2
        exit 1
      }
      sleep 0.25
    done
    echo "PASS foreground single-process, single-window launch and ${ui_soak_seconds}-second idle-window soak"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
