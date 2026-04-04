#!/usr/bin/env bash
set -euo pipefail

project_path="${PROJECT_PATH:-LonelyPianist.xcodeproj}"
scheme="${SCHEME:-LonelyPianist}"
configuration="${CONFIGURATION:-Debug}"
derived_data_path="${DERIVED_DATA_PATH:-.derivedData}"
app_name="${APP_NAME:-LonelyPianist}"
quit_before_open=1

print_help() {
  cat <<'EOF'
Usage: .github/scripts/build-open.sh [--debug|--release] [--no-quit]

Builds the macOS app via xcodebuild and opens the built .app bundle.

Defaults:
  - Build configuration: Debug
  - If LonelyPianist is running: quit it before opening the new build

Environment overrides:
  PROJECT_PATH       (default: LonelyPianist.xcodeproj)
  SCHEME             (default: LonelyPianist)
  CONFIGURATION      (default: Debug)
  DERIVED_DATA_PATH  (default: .derivedData)
  APP_NAME           (default: LonelyPianist)
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      print_help
      exit 0
      ;;
    --debug)
      configuration="Debug"
      ;;
    --release)
      configuration="Release"
      ;;
    --no-quit)
      quit_before_open=0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "" >&2
      print_help >&2
      exit 2
      ;;
  esac
done

echo "[LonelyPianist] Build configuration: $configuration"
if [[ "$quit_before_open" -eq 1 ]]; then
  echo "[LonelyPianist] Running app handling: quit before open"
else
  echo "[LonelyPianist] Running app handling: no quit"
fi

xcodebuild \
  -project "$project_path" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -derivedDataPath "$derived_data_path" \
  build

app_path="$derived_data_path/Build/Products/$configuration/$app_name.app"
if [[ ! -d "$app_path" ]]; then
  echo "Built app not found at: $app_path" >&2
  exit 1
fi

if [[ "$quit_before_open" -eq 1 ]] && pgrep -x "$app_name" >/dev/null 2>&1; then
  osascript -e "tell application \"$app_name\" to quit" >/dev/null 2>&1 || true

  # Wait a bit for the process to exit (best-effort).
  for _ in {1..30}; do
    if ! pgrep -x "$app_name" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi

open "$app_path"
