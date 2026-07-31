#!/usr/bin/env bash
set -euo pipefail

MODE="run"
APP_TARGET="${SABLE_LIBRARY_APP_TARGET:-library}"
for arg in "$@"; do
  case "$arg" in
    --clinic|clinic)
      APP_TARGET="clinic"
      ;;
    --covers|covers)
      APP_TARGET="covers"
      ;;
    --library|library)
      APP_TARGET="library"
      ;;
    *)
      MODE="$arg"
      ;;
  esac
done

case "$APP_TARGET" in
  clinic)
    APP_NAME="Sable's Clinic"
    BUNDLE_ID="com.annearuki.Sables-Clinic"
    SCHEME="Sable's Clinic"
    PACKAGE_BASENAME="Sables-Clinic-macOS-local.zip"
    ;;
  covers)
    APP_NAME="Sable's Covers"
    BUNDLE_ID="com.annearuki.Sables-Covers"
    SCHEME="Sable's Covers"
    PACKAGE_BASENAME="Sables-Covers-macOS-local.zip"
    ;;
  library)
    APP_NAME="Sable's Library"
    BUNDLE_ID="com.annearuki.Sables-Library"
    SCHEME="Sable's Library"
    PACKAGE_BASENAME="Sables-Library-macOS-local.zip"
    ;;
  *)
    echo "Unknown app target: $APP_TARGET" >&2
    exit 2
    ;;
esac

PROJECT_FILE="Sable's Library.xcodeproj"
CONFIGURATION="Debug"
DESTINATION="platform=macOS"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_DERIVED_DATA_ROOT="${TMPDIR:-/tmp}"
DEFAULT_DERIVED_DATA_ROOT="${DEFAULT_DERIVED_DATA_ROOT%/}"
case "$APP_TARGET" in
  clinic)
    DEFAULT_DERIVED_DATA_NAME="SableClinicDerivedData"
    ;;
  covers)
    DEFAULT_DERIVED_DATA_NAME="SableCoversDerivedData"
    ;;
  library)
    DEFAULT_DERIVED_DATA_NAME="SableLibraryDerivedData"
    ;;
esac
DERIVED_DATA_DIR="${SABLE_LIBRARY_DERIVED_DATA_DIR:-$DEFAULT_DERIVED_DATA_ROOT/$DEFAULT_DERIVED_DATA_NAME}"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
PACKAGE_DIR="${SABLE_LIBRARY_PACKAGE_DIR:-$ROOT_DIR/outputs}"
PACKAGE_ZIP="$PACKAGE_DIR/$PACKAGE_BASENAME"

case "$MODE" in
  --signing|signing|--package|package)
    CONFIGURATION="Release"
    APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
    APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
esac

usage() {
  echo "usage: $0 [library|clinic|covers] [run|--debug|--logs|--telemetry|--verify|--signing|--package|--test|--focused-tests]" >&2
}

kill_existing() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -f "$APP_BINARY" >/dev/null 2>&1 || true
}

freshen_derived_data() {
  case "$DERIVED_DATA_DIR" in
    ""|"/"|"$ROOT_DIR"|"$HOME"|"/tmp"|"/private/tmp"|"$DEFAULT_DERIVED_DATA_ROOT")
      echo "Refusing to clean unsafe derived data path: $DERIVED_DATA_DIR" >&2
      exit 2
      ;;
  esac

  rm -rf "$DERIVED_DATA_DIR"
}

build_app() {
  freshen_derived_data
  if [[ "$CONFIGURATION" == "Debug" && "$APP_TARGET" != "covers" ]]; then
    xcodebuild \
      -project "$ROOT_DIR/$PROJECT_FILE" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED_DATA_DIR" \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY=- \
      DEVELOPMENT_TEAM= \
      CODE_SIGN_ENTITLEMENTS= \
      CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
      build
    return
  fi

  if ! xcodebuild \
      -project "$ROOT_DIR/$PROJECT_FILE" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED_DATA_DIR" \
      -allowProvisioningUpdates \
      build; then
    if [[ "$APP_TARGET" == "covers" && "$CONFIGURATION" == "Debug" ]]; then
      echo >&2
      echo "Sable's Covers needs one signed Run from Xcode before the local build can use Keychain." >&2
      echo "Open $PROJECT_FILE, choose the Sable's Covers scheme, and press Run once." >&2
    fi
    return 1
  fi
}

test_app() {
  freshen_derived_data
  xcodebuild \
    -project "$ROOT_DIR/$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    test
}

focused_tests() {
  freshen_derived_data
  xcodebuild \
    -project "$ROOT_DIR/$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -only-testing:"Sable's LibraryTests/SableLibraryFileSafetyTests/testAppleBooksRepairRejectsUnsafeArchiveEntryNames" \
    -only-testing:"Sable's LibraryTests/SableLibraryFileSafetyTests/testAppleBooksArchiveSnapshotRejectsUnsafeZipRecords" \
    -only-testing:"Sable's LibraryTests/SableLibraryFileSafetyTests/testNameCollisionNeedsExplicitMoveAsideResolutionBeforeApply" \
    -only-testing:"Sable's LibraryTests/SableLibraryFileSafetyTests/testDuplicateMoveAsideNeedsExplicitDuplicateReasonBeforeApply" \
    -only-testing:"Sable's LibraryTests/SableLibraryFileSafetyTests/testVideoRawPreparationRunsBeforeAnimeInfoCreation" \
    -only-testing:"Sable's LibraryTests/SableLibraryFileSafetyTests/testRestoreLastApplyMovesAppliedFileBackToOriginalPath" \
    -only-testing:"Sable's LibraryTests/SableLibraryFileSafetyTests/testRestoreLastApplySkipsWhenOriginalPathIsOccupied" \
    test
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_app() {
  pgrep -x "$APP_NAME" >/dev/null 2>&1 || pgrep -f "$APP_BINARY" >/dev/null 2>&1
}

inspect_signing() {
  echo "== App bundle =="
  echo "$APP_BUNDLE"
  echo
  echo "== Info.plist =="
  plutil -p "$APP_BUNDLE/Contents/Info.plist"
  echo
  echo "== Code signature and entitlements =="
  codesign -dvvv --entitlements - "$APP_BUNDLE"
  echo
  echo "== Code signature verification =="
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  echo
  echo "== Gatekeeper assessment =="
  spctl -a -vv "$APP_BUNDLE" || true
}

package_app() {
  mkdir -p "$PACKAGE_DIR"
  rm -rf "$PACKAGE_DIR/$APP_NAME.app" "$PACKAGE_ZIP"
  /usr/bin/ditto "$APP_BUNDLE" "$PACKAGE_DIR/$APP_NAME.app"
  /usr/bin/ditto -c -k --keepParent "$PACKAGE_DIR/$APP_NAME.app" "$PACKAGE_ZIP"
  test -s "$PACKAGE_ZIP"
  echo "Created $PACKAGE_ZIP"
  echo
  inspect_signing
}

kill_existing

case "$MODE" in
  --test|test)
    test_app
    exit 0
    ;;
  --focused-tests|focused-tests)
    focused_tests
    exit 0
    ;;
  *)
    build_app
    ;;
esac

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
    sleep 2
    verify_app
    ;;
  --signing|signing)
    inspect_signing
    ;;
  --package|package)
    package_app
    ;;
  *)
    usage
    exit 2
    ;;
esac
