#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

DEFAULT_FIRST_PARTY_REGEX=""
DEFAULT_SUSPICIOUS_SYMBOL_REGEX='Authorization|Authorizer|AuthWay|AuthType|Session|SessionKeychain|Keychain|Passcode|Biometric|Cryptographer|Crypto|Encryption|Secret|Private|Token|JWT|Bearer|Password|Recovery|TFA|2FA|MFA|Repository|Environment|Config|Internal|Debug|Staging|Admin|Payment|Certificate|Pinning|Jailbreak|Frida|Cycript|Objection|Hook|Sentry|Firebase|Amplitude|Mixpanel|Logger|EventReporter'
DEFAULT_SUSPICIOUS_STRING_REGEX='https?://|wss?://|api\.|/api/|graphql|token|secret|password|passwd|apikey|api_key|client_secret|bearer|firebase|sentry|amplitude|mixpanel|segment|debug|staging|dev\.|test\.|localhost|127\.0\.0\.1|internal|admin|feature.?flag|jailbreak|frida|cycript|objection|certificate|pinning'
DEFAULT_JWT_REGEX='[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
DEFAULT_FRIDA_REGEX='frida|FridaGadget|FRIDA_SERVER|cycript|libcycript|objection|substrate|cydia|jailbreak|fishhook'

INPUT=""
OUT_DIR=""
CONFIG_FILE=""
KEEP_WORK="no"
QUIET="no"

CLI_FIRST_PARTY_REGEX=""
CLI_SUSPICIOUS_SYMBOL_REGEX=""
CLI_SUSPICIOUS_STRING_REGEX=""
CLI_JWT_REGEX=""
CLI_FRIDA_REGEX=""

CLI_FIRST_PARTY_REGEX_SET="no"
CLI_SUSPICIOUS_SYMBOL_REGEX_SET="no"
CLI_SUSPICIOUS_STRING_REGEX_SET="no"
CLI_JWT_REGEX_SET="no"
CLI_FRIDA_REGEX_SET="no"

FIRST_PARTY_REGEX="${FIRST_PARTY_REGEX:-$DEFAULT_FIRST_PARTY_REGEX}"
SUSPICIOUS_SYMBOL_REGEX="${SUSPICIOUS_SYMBOL_REGEX:-$DEFAULT_SUSPICIOUS_SYMBOL_REGEX}"
SUSPICIOUS_STRING_REGEX="${SUSPICIOUS_STRING_REGEX:-$DEFAULT_SUSPICIOUS_STRING_REGEX}"
JWT_REGEX="${JWT_REGEX:-$DEFAULT_JWT_REGEX}"
FRIDA_REGEX="${FRIDA_REGEX:-$DEFAULT_FRIDA_REGEX}"

SUMMARY=""
TOOL_LOG=""
REPORTS_DIR=""
MACHO_REPORTS_DIR=""
MACHO_INDEX=""
SKIPPED_MACHO_LIST=""
ALL_SUSPICIOUS_STRINGS=""
ALL_SUSPICIOUS_SYMBOLS=""
ALL_JWT_CANDIDATES=""
ALL_FRIDA_CANDIDATES=""
ALL_ENCRYPTION=""

PLIST_BUDDY="/usr/libexec/PlistBuddy"
APP_PATH=""
INFO_PLIST=""
EXECUTABLE=""
BUNDLE_ID=""
APP_VERSION=""
BUILD_VERSION=""
APP_NAME=""
MAIN_BINARY=""

public_usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME --input path/to/App.ipa [--output output_dir] [options]
  $SCRIPT_NAME --input path/to/App.app [--output output_dir] [options]
  $SCRIPT_NAME --input path/to/App.xcarchive [--output output_dir] [options]

Options:
  --input PATH                         IPA, .app, or .xcarchive to analyze
  --output DIR                         Output directory
  --config FILE                        Literal KEY=VALUE config file
  --first-party-regex REGEX            Include matching Mach-O paths in analysis
  --suspicious-symbol-regex REGEX      Symbol grep pattern
  --suspicious-string-regex REGEX      String grep pattern
  --jwt-regex REGEX                    JWT candidate grep pattern
  --frida-regex REGEX                  Frida/Cycript candidate grep pattern
  --keep-work                          Keep temporary extraction files in output/work
  --quiet                              Suppress INFO progress logs
  -h, --help                           Show this help

Config keys:
  FIRST_PARTY_REGEX
  SUSPICIOUS_SYMBOL_REGEX
  SUSPICIOUS_STRING_REGEX
  JWT_REGEX
  FRIDA_REGEX

Precedence:
  CLI flags override config values, config overrides environment variables,
  environment variables override built-in defaults.

Examples:
  $SCRIPT_NAME --input App.ipa
  $SCRIPT_NAME --input App.app --output analysis_out
  $SCRIPT_NAME --input App.xcarchive --output analysis_out
  $SCRIPT_NAME --input App.ipa --config analyze_ipa_macho.config
EOF
}

public_die() {
  echo "ERROR: $*" >&2
  exit 1
}

public_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

public_unquote() {
  local value="$1"
  if (( ${#value} >= 2 )); then
    if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  printf '%s' "$value"
}

public_require_value() {
  local flag="$1"
  local value="${2:-}"

  if [[ -z "$value" ]]; then
    public_die "$flag requires a value"
  fi
}

public_parse_args() {
  while (($#)); do
    case "$1" in
      --input)
        public_require_value "$1" "${2:-}"
        INPUT="$2"
        shift 2
        ;;
      --input=*)
        INPUT="${1#*=}"
        shift
        ;;
      --output)
        public_require_value "$1" "${2:-}"
        OUT_DIR="$2"
        shift 2
        ;;
      --output=*)
        OUT_DIR="${1#*=}"
        shift
        ;;
      --config)
        public_require_value "$1" "${2:-}"
        CONFIG_FILE="$2"
        shift 2
        ;;
      --config=*)
        CONFIG_FILE="${1#*=}"
        shift
        ;;
      --first-party-regex)
        public_require_value "$1" "${2:-}"
        CLI_FIRST_PARTY_REGEX="$2"
        CLI_FIRST_PARTY_REGEX_SET="yes"
        shift 2
        ;;
      --first-party-regex=*)
        CLI_FIRST_PARTY_REGEX="${1#*=}"
        CLI_FIRST_PARTY_REGEX_SET="yes"
        shift
        ;;
      --suspicious-symbol-regex)
        public_require_value "$1" "${2:-}"
        CLI_SUSPICIOUS_SYMBOL_REGEX="$2"
        CLI_SUSPICIOUS_SYMBOL_REGEX_SET="yes"
        shift 2
        ;;
      --suspicious-symbol-regex=*)
        CLI_SUSPICIOUS_SYMBOL_REGEX="${1#*=}"
        CLI_SUSPICIOUS_SYMBOL_REGEX_SET="yes"
        shift
        ;;
      --suspicious-string-regex)
        public_require_value "$1" "${2:-}"
        CLI_SUSPICIOUS_STRING_REGEX="$2"
        CLI_SUSPICIOUS_STRING_REGEX_SET="yes"
        shift 2
        ;;
      --suspicious-string-regex=*)
        CLI_SUSPICIOUS_STRING_REGEX="${1#*=}"
        CLI_SUSPICIOUS_STRING_REGEX_SET="yes"
        shift
        ;;
      --jwt-regex)
        public_require_value "$1" "${2:-}"
        CLI_JWT_REGEX="$2"
        CLI_JWT_REGEX_SET="yes"
        shift 2
        ;;
      --jwt-regex=*)
        CLI_JWT_REGEX="${1#*=}"
        CLI_JWT_REGEX_SET="yes"
        shift
        ;;
      --frida-regex)
        public_require_value "$1" "${2:-}"
        CLI_FRIDA_REGEX="$2"
        CLI_FRIDA_REGEX_SET="yes"
        shift 2
        ;;
      --frida-regex=*)
        CLI_FRIDA_REGEX="${1#*=}"
        CLI_FRIDA_REGEX_SET="yes"
        shift
        ;;
      --keep-work)
        KEEP_WORK="yes"
        shift
        ;;
      --quiet)
        QUIET="yes"
        shift
        ;;
      -h|--help)
        public_usage
        exit 0
        ;;
      --)
        shift
        (($# == 0)) || public_die "positional arguments are not supported; use --input and --output"
        ;;
      -*)
        public_die "unknown option: $1"
        ;;
      *)
        public_die "positional arguments are not supported; use --input and --output"
        ;;
    esac
  done

  return 0
}

public_apply_config_value() {
  local key="$1"
  local value="$2"

  case "$key" in
    FIRST_PARTY_REGEX)
      FIRST_PARTY_REGEX="$value"
      ;;
    SUSPICIOUS_SYMBOL_REGEX)
      SUSPICIOUS_SYMBOL_REGEX="$value"
      ;;
    SUSPICIOUS_STRING_REGEX)
      SUSPICIOUS_STRING_REGEX="$value"
      ;;
    JWT_REGEX)
      JWT_REGEX="$value"
      ;;
    FRIDA_REGEX)
      FRIDA_REGEX="$value"
      ;;
    *)
      public_die "unsupported config key '$key' in $CONFIG_FILE"
      ;;
  esac
}

public_load_config() {
  local file="$1"
  local line trimmed key value line_number=0

  [[ -f "$file" ]] || public_die "config file does not exist: $file"
  [[ -r "$file" ]] || public_die "config file is not readable: $file"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    trimmed="$(public_trim "$line")"

    if [[ -z "$trimmed" || "${trimmed:0:1}" == "#" ]]; then
      continue
    fi

    if [[ "$trimmed" != *=* ]]; then
      public_die "invalid config line $line_number in $file: expected KEY=VALUE"
    fi

    key="$(public_trim "${trimmed%%=*}")"
    value="$(public_trim "${trimmed#*=}")"
    value="$(public_unquote "$value")"

    if [[ -z "$key" ]]; then
      public_die "invalid config line $line_number in $file: empty key"
    fi

    public_apply_config_value "$key" "$value"
  done < "$file"

  return 0
}

public_apply_cli_overrides() {
  [[ "$CLI_FIRST_PARTY_REGEX_SET" == "yes" ]] && FIRST_PARTY_REGEX="$CLI_FIRST_PARTY_REGEX"
  [[ "$CLI_SUSPICIOUS_SYMBOL_REGEX_SET" == "yes" ]] && SUSPICIOUS_SYMBOL_REGEX="$CLI_SUSPICIOUS_SYMBOL_REGEX"
  [[ "$CLI_SUSPICIOUS_STRING_REGEX_SET" == "yes" ]] && SUSPICIOUS_STRING_REGEX="$CLI_SUSPICIOUS_STRING_REGEX"
  [[ "$CLI_JWT_REGEX_SET" == "yes" ]] && JWT_REGEX="$CLI_JWT_REGEX"
  [[ "$CLI_FRIDA_REGEX_SET" == "yes" ]] && FRIDA_REGEX="$CLI_FRIDA_REGEX"

  return 0
}

public_validate_input() {
  if [[ -z "$INPUT" ]]; then
    public_usage >&2
    exit 1
  fi

  [[ -e "$INPUT" ]] || public_die "input does not exist: $INPUT"

  case "$INPUT" in
    *.ipa|*.app|*.xcarchive)
      ;;
    *)
      public_die "unsupported input type: $INPUT. Expected .ipa, .app, or .xcarchive"
      ;;
  esac

  if [[ -z "$OUT_DIR" ]]; then
    OUT_DIR="ipa_analysis_$(date +%Y%m%d_%H%M%S)"
  fi

  return 0
}

public_setup_output_paths() {
  mkdir -p "$OUT_DIR/work" "$OUT_DIR/raw"

  REPORTS_DIR="$OUT_DIR/reports"
  MACHO_REPORTS_DIR="$OUT_DIR/macho"

  mkdir -p "$REPORTS_DIR" "$MACHO_REPORTS_DIR"

  SUMMARY="$OUT_DIR/summary.md"
  TOOL_LOG="$REPORTS_DIR/tool.log"

  MACHO_INDEX="$REPORTS_DIR/macho_files.tsv"
  SKIPPED_MACHO_LIST="$REPORTS_DIR/macho_skipped_non_first_party.txt"

  ALL_SUSPICIOUS_STRINGS="$REPORTS_DIR/all_suspicious_strings.txt"
  ALL_SUSPICIOUS_SYMBOLS="$REPORTS_DIR/all_suspicious_symbols.txt"
  ALL_JWT_CANDIDATES="$REPORTS_DIR/all_jwt_candidates.txt"
  ALL_FRIDA_CANDIDATES="$REPORTS_DIR/all_frida_cycript_candidates.txt"
  ALL_ENCRYPTION="$REPORTS_DIR/all_encryption.txt"

  : > "$SUMMARY"
  : > "$TOOL_LOG"
  : > "$MACHO_INDEX"
  : > "$SKIPPED_MACHO_LIST"

  : > "$ALL_SUSPICIOUS_STRINGS"
  : > "$ALL_SUSPICIOUS_SYMBOLS"
  : > "$ALL_JWT_CANDIDATES"
  : > "$ALL_FRIDA_CANDIDATES"
  : > "$ALL_ENCRYPTION"
}

public_cleanup() {
  if [[ "$KEEP_WORK" != "yes" && -n "${OUT_DIR:-}" && -d "$OUT_DIR/work" ]]; then
    rm -rf "$OUT_DIR/work"
  fi
}

public_log_info() {
  if [[ -n "${TOOL_LOG:-}" ]]; then
    echo "INFO: $*" >> "$TOOL_LOG"
  fi

  if [[ "$QUIET" != "yes" ]]; then
    echo "INFO: $*" >&2
  fi
}

public_log_warn() {
  echo "WARN: $*" >&2
  if [[ -n "${TOOL_LOG:-}" ]]; then
    echo "WARN: $*" >> "$TOOL_LOG"
  fi
}

public_log_limit() {
  if [[ -n "${TOOL_LOG:-}" ]]; then
    echo "LIMIT: $*" >> "$TOOL_LOG"
  fi
}

public_log_error() {
  echo "ERROR: $*" >&2
  if [[ -n "${TOOL_LOG:-}" ]]; then
    echo "ERROR: $*" >> "$TOOL_LOG"
  fi
}

public_has_command() {
  command -v "$1" >/dev/null 2>&1
}

public_require_command() {
  local cmd="$1"
  local reason="$2"

  if ! public_has_command "$cmd"; then
    public_log_error "Required command not found: $cmd. $reason"
    return 1
  fi

  return 0
}

public_optional_command() {
  local cmd="$1"
  local reason="$2"

  if ! public_has_command "$cmd"; then
    public_log_warn "Optional command not found: $cmd. $reason"
    return 1
  fi

  return 0
}

public_run_to_file() {
  local output_file="$1"
  local description="$2"
  shift 2

  {
    echo "# $description"
    echo ""
    echo "\$ $*"
    echo ""
  } > "$output_file"

  if "$@" >> "$output_file" 2>&1; then
    return 0
  else
    local exit_code=$?
    public_log_warn "Command failed [$exit_code]: $description. Output: $output_file. Command: $*"
    return "$exit_code"
  fi
}

public_run_to_file_with_encryption_context() {
  local output_file="$1"
  local description="$2"
  local encrypted="$3"
  shift 3

  {
    echo "# $description"
    echo ""
    echo "\$ $*"
    echo ""
  } > "$output_file"

  if "$@" >> "$output_file" 2>&1; then
    return 0
  else
    local exit_code=$?
    if [[ "$encrypted" == "yes" ]]; then
      public_log_limit "Command failed [$exit_code] on encrypted Mach-O: $description. Output: $output_file. Command: $*"
    else
      public_log_warn "Command failed [$exit_code]: $description. Output: $output_file. Command: $*"
    fi
    return "$exit_code"
  fi
}

public_count_non_empty_lines() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "0"
    return
  fi

  # grep -c returns exit code 1 for zero matches; awk avoids broken TSV cells.
  awk 'NF { count++ } END { print count + 0 }' "$file" 2>/dev/null || echo "0"
}

public_section() {
  echo "" >> "$SUMMARY"
  echo "## $1" >> "$SUMMARY"
  echo "" >> "$SUMMARY"
}

public_kv() {
  echo "- **$1:** $2" >> "$SUMMARY"
}

public_read_plist_value() {
  local key="$1"
  local plist="$2"

  if [[ ! -x "$PLIST_BUDDY" ]]; then
    public_log_warn "PlistBuddy not found/executable at $PLIST_BUDDY. Cannot read $key from plist."
    echo ""
    return
  fi

  "$PLIST_BUDDY" -c "Print :$key" "$plist" 2>/dev/null || echo ""
}

public_safe_name() {
  echo "$1" \
    | sed 's#^/##' \
    | sed 's#[/ :]#_#g' \
    | sed 's#[^a-zA-Z0-9._-]#_#g'
}

public_relative_path() {
  local path="$1"
  local base="$2"

  if public_has_command python3; then
    python3 - "$path" "$base" <<'PY'
import os
import sys

path = sys.argv[1]
base = sys.argv[2]

try:
    print(os.path.relpath(path, base))
except Exception:
    print(path)
PY
  else
    public_log_warn "python3 not found. Relative paths may be less readable."
    echo "$path"
  fi
}

public_find_app_path() {
  local input="$1"

  if [[ "$input" == *.ipa ]]; then
    public_require_command "unzip" "Needed to extract IPA." || return 1

    public_log_info "Unzipping IPA..."
    if ! unzip -q "$input" -d "$OUT_DIR/work/unzipped"; then
      public_log_error "Failed to unzip IPA: $input"
      return 1
    fi

    find "$OUT_DIR/work/unzipped/Payload" -type d -name "*.app" -print 2>/dev/null | head -n 1
    return
  fi

  if [[ "$input" == *.app ]]; then
    echo "$input"
    return
  fi

  if [[ "$input" == *.xcarchive ]]; then
    find "$input/Products/Applications" -type d -name "*.app" -print 2>/dev/null | head -n 1
    return
  fi

  echo ""
}

public_find_swift_demangle() {
  if public_has_command swift-demangle; then
    echo "swift-demangle"
    return
  fi

  if public_has_command xcrun && xcrun --find swift-demangle >/dev/null 2>&1; then
    echo "xcrun swift-demangle"
    return
  fi

  echo ""
}

public_demangle_file() {
  local input_file="$1"
  local output_file="$2"

  local demangler
  demangler="$(public_find_swift_demangle)"

  if [[ -z "$demangler" ]]; then
    public_log_warn "swift-demangle not found. Symbols will remain mangled: $input_file"
    cp "$input_file" "$output_file" 2>/dev/null || true
    return
  fi

  if [[ "$demangler" == "swift-demangle" ]]; then
    swift-demangle < "$input_file" > "$output_file" 2>/dev/null || {
      public_log_warn "swift-demangle failed for $input_file. Falling back to raw symbols."
      cp "$input_file" "$output_file" 2>/dev/null || true
    }
  else
    xcrun swift-demangle < "$input_file" > "$output_file" 2>/dev/null || {
      public_log_warn "xcrun swift-demangle failed for $input_file. Falling back to raw symbols."
      cp "$input_file" "$output_file" 2>/dev/null || true
    }
  fi
}

public_extract_dyld_export_symbols() {
  local input_file="$1"
  local output_file="$2"

  if [[ ! -f "$input_file" ]]; then
    : > "$output_file"
    return
  fi

  awk '
    $1 ~ /^0x[0-9a-fA-F]+$/ {
      for (i = 2; i <= NF; i++) {
        if ($i !~ /^\[/) {
          print $i
          break
        }
      }
    }
  ' "$input_file" | sort -u > "$output_file" 2>/dev/null || : > "$output_file"
}

public_extract_nm_symbols() {
  local input_file="$1"
  local output_file="$2"

  if [[ ! -f "$input_file" ]]; then
    : > "$output_file"
    return
  fi

  awk '
    function emit(symbol) {
      if (symbol != "") {
        print symbol
      }
    }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)

      if (line == "" || line ~ /^nm:/) {
        next
      }

      if (match(line, /<[^>]+>/)) {
        emit(substr(line, RSTART, RLENGTH))
        next
      }

      count = split(line, fields, /[[:space:]]+/)
      for (i = count; i >= 1; i--) {
        token = fields[i]
        if (token ~ /^[_$][A-Za-z0-9_.$]+$/) {
          emit(token)
          next
        }
      }
    }
  ' "$input_file" | sort -u > "$output_file" 2>/dev/null || : > "$output_file"
}

public_is_first_party_macho() {
  local rel_path="$1"

  if [[ "$rel_path" == "$EXECUTABLE" ]]; then
    return 0
  fi

  if [[ "$rel_path" =~ \.appex/ ]]; then
    return 0
  fi

  if [[ -n "$FIRST_PARTY_REGEX" && "$rel_path" =~ $FIRST_PARTY_REGEX ]]; then
    return 0
  fi

  return 1
}

public_analyze_macho() {
  local binary="$1"
  local index="$2"

  local rel_path
  rel_path="$(public_relative_path "$binary" "$APP_PATH")"

  local safe
  safe="$(printf "%03d_%s" "$index" "$(public_safe_name "$rel_path")")"

  local dir="$MACHO_REPORTS_DIR/$safe"
  mkdir -p "$dir"

  local meta_file="$dir/meta.txt"
  local file_file="$dir/file.txt"
  local lipo_file="$dir/lipo.txt"
  local size_file="$dir/size.txt"
  local encryption_file="$dir/encryption.txt"
  local linked_file="$dir/linked_libraries.txt"
  local exports_file="$dir/dyld_exports.txt"
  local imports_file="$dir/dyld_imports.txt"
  local symbols_raw_file="$dir/symbols_raw.txt"
  local nm_symbols_file="$dir/nm_symbols.txt"
  local dyld_export_symbols_file="$dir/dyld_export_symbols.txt"
  local symbols_collected_raw_file="$dir/symbols_collected_raw.txt"
  local symbols_demangled_file="$dir/symbols_demangled.txt"
  local suspicious_symbols_file="$dir/suspicious_symbols.txt"
  local strings_file="$dir/strings_all.txt"
  local suspicious_strings_file="$dir/suspicious_strings.txt"
  local jwt_file="$dir/jwt_candidates.txt"
  local frida_file="$dir/frida_cycript_candidates.txt"

  {
    echo "Binary: $binary"
    echo "Relative path: $rel_path"
    echo "Scope: first_party"
    echo "Report directory: $dir"
  } > "$meta_file"

  if public_has_command file; then
    public_run_to_file "$file_file" "file info for $rel_path" file "$binary" || true
  else
    public_log_error "Required command missing during analysis: file. Skipping binary detection details for $rel_path."
  fi

  if public_optional_command lipo "Needed to list Mach-O architectures."; then
    public_run_to_file "$lipo_file" "lipo info for $rel_path" lipo -info "$binary" || true
  fi

  if public_optional_command size "Needed to report Mach-O segment sizes."; then
    public_run_to_file "$size_file" "binary size for $rel_path" size "$binary" || true
  fi

  local encrypted="unknown"

  if public_optional_command otool "Needed for encryption check and linked libraries."; then
    {
      echo "# Encryption"
      echo ""
      otool -l "$binary" 2>&1 \
        | grep -A6 -E "LC_ENCRYPTION_INFO|LC_ENCRYPTION_INFO_64" \
        || true
    } > "$encryption_file"

    {
      echo "================================================================================"
      echo "$rel_path"
      echo "================================================================================"
      cat "$encryption_file"
      echo ""
    } >> "$ALL_ENCRYPTION"

    if grep -q "cryptid 1" "$encryption_file"; then
      encrypted="yes"
    elif grep -q "cryptid 0" "$encryption_file"; then
      encrypted="no"
    else
      encrypted="n/a"
    fi

    public_run_to_file "$linked_file" "linked libraries for $rel_path" otool -L "$binary" || true
  else
    echo "otool not available; encryption check skipped." > "$encryption_file"
    encrypted="unknown"
  fi

  if public_has_command xcrun && xcrun --find dyld_info >/dev/null 2>&1; then
    public_run_to_file_with_encryption_context "$exports_file" "dyld exports for $rel_path" "$encrypted" xcrun dyld_info -exports "$binary" || true
    public_run_to_file_with_encryption_context "$imports_file" "dyld imports for $rel_path" "$encrypted" xcrun dyld_info -imports "$binary" || true
  else
    public_log_warn "dyld_info not found through xcrun. Import/export reports skipped for $rel_path."
  fi

  local all_symbols_count=0
  local suspicious_symbols_count=0
  local nm_exit_code=0
  local symbol_sources=""

  public_extract_dyld_export_symbols "$exports_file" "$dyld_export_symbols_file"

  if public_optional_command nm "Needed to extract symbols."; then
    if nm -m "$binary" > "$symbols_raw_file" 2>&1; then
      public_extract_nm_symbols "$symbols_raw_file" "$nm_symbols_file"
      if [[ -s "$nm_symbols_file" ]]; then
        symbol_sources="nm"
      fi
    else
      nm_exit_code=$?
      : > "$nm_symbols_file"
      if [[ "$encrypted" == "yes" ]]; then
        public_log_limit "nm failed [$nm_exit_code] on encrypted Mach-O for $rel_path. nm output unavailable; dyld exports will be used if available. See $symbols_raw_file"
      else
        public_log_warn "nm failed [$nm_exit_code] for $rel_path. nm output unavailable; dyld exports will be used if available. See $symbols_raw_file"
      fi
    fi
  else
    : > "$symbols_raw_file"
    : > "$nm_symbols_file"
  fi

  if [[ -s "$dyld_export_symbols_file" ]]; then
    if [[ -n "$symbol_sources" ]]; then
      symbol_sources="$symbol_sources,dyld_exports"
    else
      symbol_sources="dyld_exports"
    fi
  fi

  awk 'NF' "$nm_symbols_file" "$dyld_export_symbols_file" 2>/dev/null \
    | sort -u \
    > "$symbols_collected_raw_file" \
    || : > "$symbols_collected_raw_file"

  if [[ -s "$symbols_collected_raw_file" ]]; then
    public_demangle_file "$symbols_collected_raw_file" "$symbols_demangled_file"
    sort -u -o "$symbols_demangled_file" "$symbols_demangled_file" 2>/dev/null || true
  else
    : > "$symbols_demangled_file"
  fi

  all_symbols_count="$(public_count_non_empty_lines "$symbols_demangled_file")"

  {
    grep -Ei "$SUSPICIOUS_SYMBOL_REGEX" "$symbols_demangled_file" \
      | sort -u \
      || true
  } > "$suspicious_symbols_file"

  suspicious_symbols_count="$(public_count_non_empty_lines "$suspicious_symbols_file")"

  if [[ -z "$symbol_sources" ]]; then
    symbol_sources="none"
  fi

  {
    echo "================================================================================"
    echo "$rel_path"
    echo "================================================================================"
    cat "$suspicious_symbols_file" 2>/dev/null || true
    echo ""
  } >> "$ALL_SUSPICIOUS_SYMBOLS"

  local all_strings_count=0
  local suspicious_strings_count=0
  local jwt_count=0
  local frida_count=0

  if public_optional_command strings "Needed to extract printable strings."; then
    if strings -a "$binary" > "$strings_file" 2>/dev/null; then
      all_strings_count="$(public_count_non_empty_lines "$strings_file")"

      {
        grep -Eai "$SUSPICIOUS_STRING_REGEX" "$strings_file" \
          | sort -u \
          || true
      } > "$suspicious_strings_file"

      {
        grep -Eao "$JWT_REGEX" "$strings_file" \
          | sort -u \
          || true
      } > "$jwt_file"

      {
        grep -Eai "$FRIDA_REGEX" "$strings_file" \
          | sort -u \
          || true
      } > "$frida_file"

      suspicious_strings_count="$(public_count_non_empty_lines "$suspicious_strings_file")"
      jwt_count="$(public_count_non_empty_lines "$jwt_file")"
      frida_count="$(public_count_non_empty_lines "$frida_file")"
    else
      public_log_warn "strings failed for $rel_path. Strings unavailable."
      echo "" > "$strings_file"
      echo "" > "$suspicious_strings_file"
      echo "" > "$jwt_file"
      echo "" > "$frida_file"
    fi

    {
      echo "================================================================================"
      echo "$rel_path"
      echo "================================================================================"
      cat "$suspicious_strings_file" 2>/dev/null || true
      echo ""
    } >> "$ALL_SUSPICIOUS_STRINGS"

    {
      echo "================================================================================"
      echo "$rel_path"
      echo "================================================================================"
      cat "$jwt_file" 2>/dev/null || true
      echo ""
    } >> "$ALL_JWT_CANDIDATES"

    {
      echo "================================================================================"
      echo "$rel_path"
      echo "================================================================================"
      cat "$frida_file" 2>/dev/null || true
      echo ""
    } >> "$ALL_FRIDA_CANDIDATES"
  else
    echo "" > "$strings_file"
    echo "" > "$suspicious_strings_file"
    echo "" > "$jwt_file"
    echo "" > "$frida_file"
  fi

  local row
  row="$(printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s" \
    "$index" \
    "$rel_path" \
    "$encrypted" \
    "$all_strings_count" \
    "$suspicious_strings_count" \
    "$all_symbols_count" \
    "$suspicious_symbols_count" \
    "$jwt_count" \
    "$frida_count" \
    "$symbol_sources")"

  echo "$row" >> "$MACHO_INDEX"
}

public_write_summary_header() {
  public_section "IPA Analysis Summary"
  public_kv "Input" "$INPUT"
  public_kv "Output directory" "$OUT_DIR"
  public_kv "Config file" "${CONFIG_FILE:-none}"
  public_kv "App path" "$APP_PATH"
  public_kv "App name" "${APP_NAME:-unknown}"
  public_kv "Bundle ID" "${BUNDLE_ID:-unknown}"
  public_kv "Version" "${APP_VERSION:-unknown}"
  public_kv "Build" "${BUILD_VERSION:-unknown}"
  public_kv "Executable" "$EXECUTABLE"
  public_kv "Main binary" "$MAIN_BINARY"
  public_kv "Analysis scope" "first-party Mach-O files only"
  public_kv "First-party regex" "${FIRST_PARTY_REGEX:-none; main executable and app extensions only}"
  public_kv "Tool log" "reports/tool.log"
}

public_write_tool_availability() {
  public_section "Tool Availability"

  {
    echo "| Tool | Status | Purpose |"
    echo "|---|---|---|"

    for tool in file unzip plutil codesign security otool nm strings lipo size xcrun swift-demangle python3 awk grep sort sed; do
      if public_has_command "$tool"; then
        echo "| \`$tool\` | available |  |"
      else
        echo "| \`$tool\` | missing | some reports may be skipped |"
      fi
    done
  } >> "$SUMMARY"
}

public_write_static_app_reports() {
  public_section "Code Signing"

  if public_optional_command codesign "Needed for code signing and entitlements reports."; then
    public_run_to_file "$REPORTS_DIR/app_codesign.txt" "codesign details" codesign -dvvv "$APP_PATH" || true
    public_run_to_file "$REPORTS_DIR/app_entitlements.plist" "codesign entitlements" codesign -d --entitlements :- "$APP_PATH" || true

    public_kv "Codesign report" "reports/app_codesign.txt"
    public_kv "Entitlements" "reports/app_entitlements.plist"
  else
    public_kv "Codesign report" "skipped: codesign not found"
    public_kv "Entitlements" "skipped: codesign not found"
  fi

  public_section "Info.plist Checks"

  local info_checks="$REPORTS_DIR/app_info_plist_checks.txt"

  {
    echo "# Info.plist checks"
    echo ""

    echo "## Bundle URL Types"
    if [[ -x "$PLIST_BUDDY" ]]; then
      "$PLIST_BUDDY" -c "Print :CFBundleURLTypes" "$INFO_PLIST" 2>/dev/null || echo "Not found"
    else
      echo "Skipped: PlistBuddy not found"
    fi

    echo ""
    echo "## App Transport Security"
    if [[ -x "$PLIST_BUDDY" ]]; then
      "$PLIST_BUDDY" -c "Print :NSAppTransportSecurity" "$INFO_PLIST" 2>/dev/null || echo "Not found"
    else
      echo "Skipped: PlistBuddy not found"
    fi

    echo ""
    echo "## Permissions / Usage Descriptions"
    if public_has_command plutil; then
      plutil -p "$INFO_PLIST" 2>/dev/null \
        | grep -E "UsageDescription|NSCamera|NSMicrophone|NSPhoto|NSLocation|NSBluetooth|NSContacts|NSCalendars|NSFaceID|NSSpeech|NSMotion|NSHealth" \
        || true
    else
      echo "Skipped: plutil not found"
    fi

    echo ""
    echo "## Background Modes"
    if [[ -x "$PLIST_BUDDY" ]]; then
      "$PLIST_BUDDY" -c "Print :UIBackgroundModes" "$INFO_PLIST" 2>/dev/null || echo "Not found"
    else
      echo "Skipped: PlistBuddy not found"
    fi
  } > "$info_checks"

  public_kv "Info.plist checks" "reports/app_info_plist_checks.txt"

  public_section "Provisioning Profile"

  local provision_file="$APP_PATH/embedded.mobileprovision"
  local provision_report="$REPORTS_DIR/app_embedded_mobileprovision.plist"

  if [[ -f "$provision_file" ]]; then
    if public_optional_command security "Needed to decode embedded.mobileprovision."; then
      if security cms -D -i "$provision_file" > "$provision_report" 2>> "$TOOL_LOG"; then
        public_kv "embedded.mobileprovision" "reports/app_embedded_mobileprovision.plist"
      else
        public_log_warn "Failed to decode embedded.mobileprovision"
        public_kv "embedded.mobileprovision" "found, but decoding failed"
      fi
    else
      public_kv "embedded.mobileprovision" "found, but security tool missing"
    fi
  else
    public_kv "embedded.mobileprovision" "not found"
  fi
}

public_discover_and_analyze_macho() {
  local tsv_header="index	relative_path	encrypted	all_strings	suspicious_strings	all_symbols	suspicious_symbols	jwt_candidates	frida_cycript_candidates	symbol_sources"
  local macho_list="$REPORTS_DIR/macho_discovered.txt"
  local first_party_macho_list="$REPORTS_DIR/macho_first_party.txt"
  local macho_count
  local first_party_macho_count
  local skipped_macho_count
  local index
  local rel_path

  echo "$tsv_header" > "$MACHO_INDEX"

  public_section "Mach-O Discovery"

  : > "$macho_list"
  : > "$first_party_macho_list"
  : > "$SKIPPED_MACHO_LIST"

  public_log_info "Finding Mach-O files inside app bundle..."

  while IFS= read -r file_path; do
    if file "$file_path" 2>/dev/null | grep -q "Mach-O"; then
      echo "$file_path" >> "$macho_list"
      rel_path="$(public_relative_path "$file_path" "$APP_PATH")"
      if public_is_first_party_macho "$rel_path"; then
        echo "$file_path" >> "$first_party_macho_list"
      else
        echo "$rel_path" >> "$SKIPPED_MACHO_LIST"
      fi
    fi
  done < <(find "$APP_PATH" -type f)

  macho_count="$(public_count_non_empty_lines "$macho_list")"
  first_party_macho_count="$(public_count_non_empty_lines "$first_party_macho_list")"
  skipped_macho_count="$(public_count_non_empty_lines "$SKIPPED_MACHO_LIST")"
  public_kv "Mach-O files found" "$macho_count"
  public_kv "Mach-O list" "reports/macho_discovered.txt"
  public_kv "First-party Mach-O files analyzed" "$first_party_macho_count"
  public_kv "First-party Mach-O list" "reports/macho_first_party.txt"
  public_kv "Skipped non-first-party Mach-O files" "$skipped_macho_count"
  public_kv "Skipped Mach-O list" "reports/macho_skipped_non_first_party.txt"

  if [[ "$macho_count" == "0" ]]; then
    public_log_error "No Mach-O files found. Input may be invalid or unsupported."
    exit 1
  fi

  if [[ "$first_party_macho_count" == "0" ]]; then
    public_log_error "No first-party Mach-O files found. Extend FIRST_PARTY_REGEX if required."
    exit 1
  fi

  public_log_info "Analyzing $first_party_macho_count first-party Mach-O files..."

  index=1
  while IFS= read -r binary; do
    public_log_info "[$index/$first_party_macho_count] Analyzing: $(public_relative_path "$binary" "$APP_PATH")"
    public_analyze_macho "$binary" "$index"
    index=$((index + 1))
  done < "$first_party_macho_list"
}

public_write_aggregate_summary() {
  public_section "Aggregate Reports"

  public_kv "Analyzed first-party Mach-O index" "reports/macho_files.tsv"
  public_kv "Skipped non-first-party Mach-O list" "reports/macho_skipped_non_first_party.txt"

  public_kv "All suspicious strings" "reports/all_suspicious_strings.txt"
  public_kv "All suspicious symbols" "reports/all_suspicious_symbols.txt"
  public_kv "All JWT candidates" "reports/all_jwt_candidates.txt"
  public_kv "All Frida/Cycript candidates" "reports/all_frida_cycript_candidates.txt"
  public_kv "All encryption reports" "reports/all_encryption.txt"

  public_section "First-Party Totals"

  {
    echo "| Mach-O files | All symbols | Suspicious symbols | All strings | Suspicious strings | JWT candidates | Frida/Cycript |"
    echo "|---:|---:|---:|---:|---:|---:|---:|"

    tail -n +2 "$MACHO_INDEX" \
      | awk -F '\t' '
        {
          files+=1
          all_strings+=$4
          suspicious_strings+=$5
          all_symbols+=$6
          suspicious_symbols+=$7
          jwt+=$8
          frida+=$9
        }
        END {
          printf "| %d | %d | %d | %d | %d | %d | %d |\n", files, all_symbols, suspicious_symbols, all_strings, suspicious_strings, jwt, frida
        }
      '
  } >> "$SUMMARY"

  public_section "Top Noisy First-Party Mach-O Files"

  {
    echo "| Suspicious symbols | All symbols | Suspicious strings | All strings | JWT | Frida/Cycript | Encrypted | Binary |"
    echo "|---:|---:|---:|---:|---:|---:|---|---|"

    tail -n +2 "$MACHO_INDEX" \
      | awk -F '\t' '{ print $7 "\t" $6 "\t" $5 "\t" $4 "\t" $8 "\t" $9 "\t" $3 "\t" $2 }' \
      | sort -nr \
      | head -20 \
      | while IFS=$'\t' read -r suspicious_symbols all_symbols suspicious_strings all_strings jwt frida encrypted path; do
          echo "| $suspicious_symbols | $all_symbols | $suspicious_strings | $all_strings | $jwt | $frida | $encrypted | \`$path\` |"
        done
  } >> "$SUMMARY"
}

public_write_footer() {
  public_section "High-Risk Files To Open First"

  cat >> "$SUMMARY" <<EOF
Open these first:

1. \`reports/macho_files.tsv\`
2. \`reports/all_suspicious_symbols.txt\`
3. \`reports/all_suspicious_strings.txt\`
4. \`reports/all_jwt_candidates.txt\`
5. \`reports/all_frida_cycript_candidates.txt\`
6. \`reports/all_encryption.txt\`
7. \`reports/macho_skipped_non_first_party.txt\`
8. \`reports/tool.log\`

For per-binary details, open:

\`macho/<binary-report-folder>/nm_symbols.txt\`
\`macho/<binary-report-folder>/dyld_export_symbols.txt\`
\`macho/<binary-report-folder>/symbols_demangled.txt\`
\`macho/<binary-report-folder>/suspicious_symbols.txt\`
\`macho/<binary-report-folder>/strings_all.txt\`
\`macho/<binary-report-folder>/suspicious_strings.txt\`
\`macho/<binary-report-folder>/dyld_imports.txt\`
\`macho/<binary-report-folder>/dyld_exports.txt\`
EOF

  public_section "Report Folder Layout"

  cat >> "$SUMMARY" <<EOF
\`\`\`
reports/
  app_*                         Info.plist, codesign, entitlements, provisioning profile
  macho_files.tsv               TSV table for analyzed first-party Mach-O files
  macho_discovered.txt          all Mach-O files discovered in the app bundle
  macho_first_party.txt         first-party Mach-O files selected for analysis
  macho_skipped_non_first_party.txt
  all_suspicious_symbols.txt    combined suspicious symbols for analyzed binaries
  all_suspicious_strings.txt    combined suspicious strings for analyzed binaries
  all_jwt_candidates.txt        JWT-like strings across analyzed binaries
  all_frida_cycript_candidates.txt
  all_encryption.txt
  tool.log

macho/
  <binary-report-folder>/       per-binary raw tool output and extracted data
\`\`\`
EOF

  public_section "Interpretation Rules"

  cat >> "$SUMMARY" <<EOF
- \`all_symbols\` is the count of unique symbol names from the combined symbol report after Swift demangling. The combined report includes normalized \`nm -m\` symbols when available and \`dyld_info -exports\` symbols when available.
- \`symbol_sources\` shows which symbol sources contributed to \`all_symbols\`: \`nm\`, \`dyld_exports\`, both, or \`none\`.
- \`all_strings\` is the count of non-empty printable strings extracted by \`strings -a\`.
- \`suspicious_symbols\` and \`suspicious_strings\` are heuristic grep matches, not confirmed vulnerabilities.
- If \`encrypted = yes\`, static code analysis may still expose metadata, imports, exports, and symbol names.
- If \`jwt_candidates\` is non-zero, inspect manually. Real JWT normally has three base64url parts separated by dots.
- If \`frida_cycript_candidates\` is non-zero, anti-hooking / anti-instrumentation strings are visible in plaintext.
- The main executable and app extensions are treated as first-party by default.
- If important first-party frameworks are skipped, extend \`FIRST_PARTY_REGEX\` through CLI, environment, or config.
EOF

  public_section "Tool Log"
  echo "Progress, warnings, errors, and static-analysis limitations are written to:" >> "$SUMMARY"
  echo "" >> "$SUMMARY"
  echo "\`reports/tool.log\`" >> "$SUMMARY"

  return 0
}

public_run() {
  public_parse_args "$@"

  if [[ -n "$CONFIG_FILE" ]]; then
    public_load_config "$CONFIG_FILE"
  fi

  public_apply_cli_overrides
  public_validate_input
  public_setup_output_paths
  trap public_cleanup EXIT

  public_log_info "Starting analysis"
  public_log_info "Input: $INPUT"
  public_log_info "Output: $OUT_DIR"

  public_require_command "find" "Needed to discover files." || exit 1
  public_require_command "grep" "Needed to filter reports." || exit 1
  public_require_command "sort" "Needed to sort report entries." || exit 1
  public_require_command "awk" "Needed to generate summary tables and count lines safely." || exit 1
  public_require_command "sed" "Needed to sanitize filenames." || exit 1
  public_require_command "file" "Needed to identify Mach-O files." || exit 1

  APP_PATH="$(public_find_app_path "$INPUT")"

  if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    public_log_error "Could not find .app inside input."
    exit 1
  fi

  INFO_PLIST="$APP_PATH/Info.plist"

  if [[ ! -f "$INFO_PLIST" ]]; then
    public_log_error "Info.plist not found in app bundle: $APP_PATH"
    exit 1
  fi

  EXECUTABLE="$(public_read_plist_value "CFBundleExecutable" "$INFO_PLIST")"
  BUNDLE_ID="$(public_read_plist_value "CFBundleIdentifier" "$INFO_PLIST")"
  APP_VERSION="$(public_read_plist_value "CFBundleShortVersionString" "$INFO_PLIST")"
  BUILD_VERSION="$(public_read_plist_value "CFBundleVersion" "$INFO_PLIST")"
  APP_NAME="$(public_read_plist_value "CFBundleName" "$INFO_PLIST")"

  if [[ -z "$EXECUTABLE" ]]; then
    public_log_error "CFBundleExecutable is missing or unreadable in Info.plist"
    exit 1
  fi

  MAIN_BINARY="$APP_PATH/$EXECUTABLE"

  if [[ ! -f "$MAIN_BINARY" ]]; then
    public_log_warn "Main binary declared in Info.plist was not found: $MAIN_BINARY"
  fi

  cp "$INFO_PLIST" "$OUT_DIR/raw/Info.plist" 2>/dev/null || public_log_warn "Failed to copy Info.plist to raw folder."

  if public_optional_command plutil "Needed to convert Info.plist to XML/JSON."; then
    plutil -convert xml1 -o "$REPORTS_DIR/app_Info.xml.plist" "$INFO_PLIST" 2>/dev/null || public_log_warn "Failed to convert Info.plist to XML."
    plutil -convert json -o "$REPORTS_DIR/app_Info.json" "$INFO_PLIST" 2>/dev/null || public_log_warn "Failed to convert Info.plist to JSON."
  fi

  public_write_summary_header
  public_write_tool_availability
  public_write_static_app_reports
  public_discover_and_analyze_macho
  public_write_aggregate_summary
  public_write_footer

  public_log_info "Done."
  echo ""
  echo "Done."
  echo "Summary: $SUMMARY"
  echo "Mach-O index: $MACHO_INDEX"
  echo "Skipped non-first-party Mach-O list: $SKIPPED_MACHO_LIST"
  echo "Tool log: $TOOL_LOG"
  echo "Reports: $REPORTS_DIR"
  echo "Per-binary reports: $MACHO_REPORTS_DIR"

  if [[ "$KEEP_WORK" == "yes" ]]; then
    echo "Work directory: $OUT_DIR/work"
  fi
}

public_run "$@"
