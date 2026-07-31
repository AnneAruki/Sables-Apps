#!/usr/bin/env bash
set -u -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="quick"
LIBRARY_ROOT="${SABLE_SMOKE_LIBRARY_ROOT:-}"

usage() {
  cat >&2 <<'USAGE'
usage: script/sable_smoke_lab.sh [quick|full|tests] [--library-root PATH]

Runs read-only smoke checks and writes a receipt to outputs/smoke-lab.

Modes:
  quick   Config lint, diff check, all three app builds, test bundle compile.
  full    Quick checks plus local helper script compile checks.
  tests   Attempts the Xcode scheme test runner after quick checks.

Options:
  --library-root PATH   Adds a read-only catalog presence check for this library root.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    quick|full|tests)
      MODE="$1"
      shift
      ;;
    --library-root)
      if [[ $# -lt 2 ]]; then
        echo "--library-root needs a path" >&2
        exit 2
      fi
      LIBRARY_ROOT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown Smoke Lab option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

case "$MODE" in
  quick|full|tests) ;;
  *)
    echo "Unknown Smoke Lab mode: $MODE" >&2
    usage
    exit 2
    ;;
esac

REPORT_DIR="${SABLE_SMOKE_REPORT_DIR:-$ROOT_DIR/outputs/smoke-lab}"
STAMP="$(date +"%Y%m%d-%H%M%S")"
REPORT="$REPORT_DIR/smoke-$STAMP.md"
LOG_DIR="$REPORT_DIR/logs-$STAMP"
DEFAULT_DERIVED_DATA_ROOT="${TMPDIR:-/tmp}"
DEFAULT_DERIVED_DATA_ROOT="${DEFAULT_DERIVED_DATA_ROOT%/}"
DERIVED_DATA_DIR="${SABLE_SMOKE_DERIVED_DATA_DIR:-$DEFAULT_DERIVED_DATA_ROOT/SableSmokeLabDerivedData}"
PROJECT_FILE="$ROOT_DIR/Sable's Library.xcodeproj"
CONFIG_FILE="$ROOT_DIR/Sable's Library/App/sable_library_config.json"

mkdir -p "$REPORT_DIR" "$LOG_DIR"

failures=0
warnings=0

append_report() {
  printf '%s\n' "$*" >>"$REPORT"
}

safe_log_name() {
  printf '%s' "$1" | tr '[:upper:] /:' '[:lower:]---' | tr -cd '[:alnum:]_.-'
}

run_required() {
  local title="$1"
  shift
  local log_file="$LOG_DIR/$(safe_log_name "$title").log"
  printf 'Smoke Lab: %s...\n' "$title"
  if "$@" >"$log_file" 2>&1; then
    append_report "- PASS: $title"
  else
    local status=$?
    failures=$((failures + 1))
    append_report "- FAIL: $title"
    append_report "  - Log: $log_file"
    append_report "  - Exit code: $status"
  fi
}

run_optional() {
  local title="$1"
  shift
  local log_file="$LOG_DIR/$(safe_log_name "$title").log"
  printf 'Smoke Lab: %s...\n' "$title"
  if "$@" >"$log_file" 2>&1; then
    append_report "- PASS: $title"
  else
    local status=$?
    warnings=$((warnings + 1))
    append_report "- WARN: $title"
    append_report "  - Log: $log_file"
    append_report "  - Exit code: $status"
  fi
}

prepare_derived_data() {
  case "$DERIVED_DATA_DIR" in
    ""|"/"|"$ROOT_DIR"|"$HOME"|"/tmp"|"/private/tmp"|"$DEFAULT_DERIVED_DATA_ROOT")
      echo "Refusing unsafe derived data path: $DERIVED_DATA_DIR" >&2
      exit 2
      ;;
  esac
  rm -rf "$DERIVED_DATA_DIR"
  mkdir -p "$DERIVED_DATA_DIR"
}

check_root_catalog() {
  local root="$1"
  local catalog="$root/Sable Library Catalog.csv"
  if [[ ! -d "$root" ]]; then
    echo "Library root does not exist: $root" >&2
    return 1
  fi
  if [[ ! -s "$catalog" ]]; then
    echo "Root catalog is missing or empty: $catalog" >&2
    return 1
  fi
  local header
  header="$(head -n 1 "$catalog")"
  case "$header" in
    kind,form,series_title,preferred_title,local_title,series_path,file_name,file_path,file_extension,file_count,year,source_provider,source_id,sidecar,updated_at*)
      return 0
      ;;
    *)
      echo "Root catalog has an unexpected header: $header" >&2
      return 1
      ;;
  esac
}

lint_config_json() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$CONFIG_FILE" >/dev/null
  elif command -v ruby >/dev/null 2>&1; then
    ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "$CONFIG_FILE"
  else
    echo "Neither python3 nor ruby is available for JSON linting." >&2
    return 1
  fi
}

compile_shelf_smoke_script() {
  swiftc \
    "$ROOT_DIR/Sable's Library/App/Core/SableLibraryShelfTagClassifier.swift" \
    "$ROOT_DIR/Sable's Library/App/Core/SableLibraryShelfCatalog.swift" \
    "$ROOT_DIR/script/ranobedb_shelf_smoke.swift" \
    -o "$DERIVED_DATA_DIR/ranobedb_shelf_smoke"
}

compile_local_audit_script() {
  swiftc \
    "$ROOT_DIR/Sable's Library/App/Core/SableLibraryShelfTagClassifier.swift" \
    "$ROOT_DIR/Sable's Library/App/Core/SableLibraryShelfCatalog.swift" \
    "$ROOT_DIR/script/local_shelf_review_audit.swift" \
    -o "$DERIVED_DATA_DIR/local_shelf_review_audit"
}

cat >"$REPORT" <<EOF
# Sable Smoke Lab

- Created: $(date -Iseconds)
- Mode: $MODE
- Root: $ROOT_DIR
- Library root: ${LIBRARY_ROOT:-not checked}

## Checks
EOF

prepare_derived_data

run_required "Config JSON lint" lint_config_json
run_required "Git diff whitespace check" git -C "$ROOT_DIR" diff --check

run_required "Build Sable's Library" xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "Sable's Library" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_DIR/library" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build

run_required "Build Sable's Clinic" xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "Sable's Clinic" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_DIR/clinic" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build

run_required "Build Sable's Covers" xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "Sable's Covers" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_DIR/covers" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build

run_required "Compile test bundle" xcodebuild \
  build \
  -project "$PROJECT_FILE" \
  -target "Sable's LibraryTests" \
  -configuration Debug \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO

if [[ -n "$LIBRARY_ROOT" ]]; then
  run_optional "Root catalog presence" check_root_catalog "$LIBRARY_ROOT"
fi

if [[ "$MODE" == "full" || "$MODE" == "tests" ]]; then
  run_optional "Compile RanobeDB shelf smoke helper" compile_shelf_smoke_script
  run_optional "Compile local shelf audit helper" compile_local_audit_script
fi

if [[ "$MODE" == "tests" ]]; then
  run_optional "Run Xcode scheme tests" xcodebuild \
    test \
    -project "$PROJECT_FILE" \
    -scheme "Sable's Library" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_DIR/scheme-tests" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO
fi

append_report ""
append_report "## Result"
append_report ""
append_report "- Failures: $failures"
append_report "- Warnings: $warnings"
append_report "- Logs: $LOG_DIR"

if [[ "$failures" -gt 0 ]]; then
  append_report ""
  append_report "Smoke Lab found required failures. Fix those before trusting a release."
  printf 'Smoke Lab finished with failures. Receipt: %s\n' "$REPORT" >&2
  exit 1
fi

if [[ "$warnings" -gt 0 ]]; then
  append_report ""
  append_report "Smoke Lab passed required checks, with warnings for optional checks."
else
  append_report ""
  append_report "Smoke Lab passed required checks."
fi

printf 'Smoke Lab receipt: %s\n' "$REPORT"
