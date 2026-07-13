#!/usr/bin/env bash
# spec-cache.sh — content-addressed phase cache for /mp-spec.
# Cross-platform Bash; emits exactly one JSON line and keeps an auditable input manifest.
set -uo pipefail

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

emit_error() {
  printf '{"ok":false,"error":"%s"}\n' "$(json_escape "$1")"
  exit 0
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$file"
  else
    return 1
  fi
}

file_size() {
  wc -c < "$1" | tr -d '[:space:]'
}

fingerprint() {
  [ "$#" -ge 3 ] || emit_error "usage: fingerprint <cache-dir> <label> <path>..."
  local cache_dir="$1" label="$2"
  shift 2
  mkdir -p "$cache_dir" || emit_error "cannot create cache dir: $cache_dir"

  local tmp manifest path file digest size
  local files=0 bytes=0
  tmp=$(mktemp "$cache_dir/.input-manifest.XXXXXX") || emit_error "mktemp failed"
  manifest="$cache_dir/${label}-input-manifest.tsv"

  for path in "$@"; do
    [ -e "$path" ] || continue
    if [ -f "$path" ]; then
      digest=$(sha256_file "$path") || emit_error "no SHA-256 implementation available"
      size=$(file_size "$path")
      printf '%s\t%s\t%s\n' "$path" "$digest" "$size" >> "$tmp"
      files=$((files + 1)); bytes=$((bytes + size))
    elif [ -d "$path" ]; then
      while IFS= read -r file; do
        [ -f "$file" ] || continue
        case "$file" in "$cache_dir"/*) continue ;; esac
        digest=$(sha256_file "$file") || emit_error "no SHA-256 implementation available"
        size=$(file_size "$file")
        printf '%s\t%s\t%s\n' "$file" "$digest" "$size" >> "$tmp"
        files=$((files + 1)); bytes=$((bytes + size))
      done < <(find "$path" -type f -print 2>/dev/null | LC_ALL=C sort)
    fi
  done

  mv "$tmp" "$manifest" || emit_error "cannot publish input manifest"
  digest=$(sha256_file "$manifest") || emit_error "cannot hash input manifest"
  printf '{"ok":true,"command":"fingerprint","label":"%s","fingerprint":"%s","files":%s,"bytes":%s,"manifest":"%s"}\n' \
    "$(json_escape "$label")" "$digest" "$files" "$bytes" "$(json_escape "$manifest")"
}

check_cache() {
  [ "$#" -eq 3 ] || emit_error "usage: check <cache-dir> <phase> <fingerprint>"
  local cache_dir="$1" phase="$2" expected="$3"
  local state="$cache_dir/${phase}.sha256" actual=""
  [ -f "$state" ] && IFS= read -r actual < "$state"
  if [ -n "$actual" ] && [ "$actual" = "$expected" ]; then
    printf '{"ok":true,"command":"check","phase":"%s","hit":true,"fingerprint":"%s"}\n' \
      "$(json_escape "$phase")" "$expected"
  else
    printf '{"ok":true,"command":"check","phase":"%s","hit":false,"fingerprint":"%s","previous":"%s"}\n' \
      "$(json_escape "$phase")" "$expected" "$(json_escape "$actual")"
  fi
}

record_cache() {
  [ "$#" -eq 3 ] || emit_error "usage: record <cache-dir> <phase> <fingerprint>"
  local cache_dir="$1" phase="$2" fingerprint_value="$3"
  local state tmp previous="" history stamp
  mkdir -p "$cache_dir" || emit_error "cannot create cache dir: $cache_dir"
  state="$cache_dir/${phase}.sha256"
  history="$cache_dir/history.tsv"
  [ -f "$state" ] && IFS= read -r previous < "$state"
  stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  [ -n "$previous" ] && printf '%s\t%s\t%s\n' "$stamp" "$phase" "$previous" >> "$history"
  tmp=$(mktemp "$cache_dir/.${phase}.XXXXXX") || emit_error "mktemp failed"
  printf '%s\n' "$fingerprint_value" > "$tmp"
  mv "$tmp" "$state" || emit_error "cannot publish cache state"
  printf '{"ok":true,"command":"record","phase":"%s","fingerprint":"%s","previous":"%s"}\n' \
    "$(json_escape "$phase")" "$fingerprint_value" "$(json_escape "$previous")"
}

command_name="${1:-}"
[ -n "$command_name" ] || emit_error "usage: fingerprint|check|record ..."
shift
case "$command_name" in
  fingerprint) fingerprint "$@" ;;
  check) check_cache "$@" ;;
  record) record_cache "$@" ;;
  *) emit_error "unknown command: $command_name" ;;
esac
