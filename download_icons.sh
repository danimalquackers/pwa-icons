#!/usr/bin/env sh
set -euo pipefail

# Configuration
CURL_UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36"
ICON_DIR="${2:-${ICON_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/webapp-icons}}"
mkdir -p "$ICON_DIR"

log() {
  echo -e "[INFO] $*" >&2
}

error() {
  echo -e "[ERROR] $*" >&2
}

if [ -z "${1:-}" ]; then
  error "Usage: $0 <base-domain> [output-dir]"
  exit 1
fi

# Clean up the domain 
DOMAIN=$(echo "$1" | sed -E 's|^https?://||' | sed -E 's|/.*||')
BASE_URL="https://$DOMAIN"

# Generate a safe filename for the icon
SAFE_NAME="${DOMAIN//[^a-zA-Z0-9.-]/_}"
ICON_FILE="$ICON_DIR/$SAFE_NAME.ico"

# Helper: Verify if the downloaded file is a valid image with non-zero size
# shellcheck disable=SC2329
is_valid_image() {
  local file="$1"
  [[ -s "$file" ]] || return 1
  local mime
  mime=$(file --mime-type -b "$file" 2>/dev/null || true)
  [[ "$mime" == image/* ]]
}

# Helper: Resolve relative or absolute URLs against a base URL
# shellcheck disable=SC2329
resolve_url() {
  local url="$1"
  local base="$2"

  # If URL starts with http, it's already absolute
  [[ "$url" == http* ]] && { echo "$url"; return; }

  # If URL starts with /, it's relative to the domain root
  [[ "$url" == /* ]] && { echo "${base%/}${url}"; return; }

  # Otherwise, it's relative to the current path
  echo "${base%/}/${url}"
}

# Method 1: Extraction from PWA Manifest
# Scans HTML for rel="manifest" and parses the JSON for icon sources.
# shellcheck disable=SC2329
fetch_pwa_manifest() {
  local domain="$1" base_url="$2" target="$3" html_file="$4"
  
  # Ensure the HTML file exists and is not empty before processing
  [[ ! -s "$html_file" ]] && return 1

  # Extract the manifest URL from the <link rel="manifest" ...> tag
  local manifest_href
  manifest_href=$(grep -ioP '<link[^>]+rel=["'\'']manifest["'\''][^>]*>' "$html_file" | \
                  grep -ioP 'href=["'\'']\K[^"'\'' >]+' | head -n 1 || true)

  log "Manifest href found: ${manifest_href:-none}"

  # If no manifest link is found in the HTML, this method fails
  [[ -z "$manifest_href" ]] && return 1

  # Resolve the manifest URL (could be relative to the base URL)
  local manifest_url
  manifest_url=$(resolve_url "$manifest_href" "$base_url")
  log "Resolved manifest URL: $manifest_url"

  # Create a temporary manifest file
  local tmp_manifest
  tmp_manifest=$(mktemp)

  # Download the manifest JSON file
  if curl -sSL "$manifest_url" -o "$tmp_manifest"; then
    # Extract all "src" values from the manifest using regex.
    # Note: This is a simple grep-based parse which works for standard manifest structures.
    mapfile -t icon_srcs < <(grep -oP '"src"\s*:\s*"\K[^"]+' "$tmp_manifest" || true)
    
    # Iterate through all icon sources found in the manifest
    for src in "${icon_srcs[@]}"; do
      # Manifest icons are relative to the manifest file's location
      local manifest_base="${manifest_url%/*}"
      local icon_url
      icon_url=$(resolve_url "$src" "$manifest_base")
      
      # Try to download the specific icon and verify if it's a valid image
      if curl -sSL "$icon_url" -o "$target" && is_valid_image "$target"; then
        # Successfully found an icon! Clean up and return
        log "Successfully downloaded icon from manifest: $icon_url"
        rm -f "$tmp_manifest"
        return 0
      fi
    done
  fi
  
  # Clean up and return failure if no valid icon was found in the manifest
  rm -f "$tmp_manifest"
  return 1
}

# Method 2: Extraction from HTML <link> tags
# Scans for shortcut icons, apple-touch-icons, etc.
# shellcheck disable=SC2329
fetch_html_icon() {
  local domain="$1" base_url="$2" target="$3" html_file="$4"
  
  # Ensure the HTML file exists and is not empty
  [[ ! -s "$html_file" ]] && return 1

  # Search for common icon link types (shortcut icon, icon, apple-touch-icon)
  local link_href
  link_href=$(grep -ioP '<link[^>]+rel=["'\''](?:shortcut\s+icon|icon|apple-touch-icon)["'\''][^>]*>' "$html_file" | \
              grep -ioP 'href=["'\'']\K[^"'\'' >]+' | head -n 1 || true)
  
  # If no icon link is found, return failure
  [[ -z "$link_href" ]] && return 1

  # Resolve the icon's URL and attempt the download
  local resolved_url
  resolved_url=$(resolve_url "$link_href" "$base_url")
  
  log "Found HTML icon link: $resolved_url"

  # Verify if the downloaded file is actually an image
  if curl -sSL "$resolved_url" -o "$target" && is_valid_image "$target"; then
    return 0
  fi
  return 1
}

# Method 3: Direct download from /favicon.ico
# shellcheck disable=SC2329
fetch_direct_favicon() {
  local domain="$1" base_url="$2" target="$3"
  
  # Many sites still host a favicon at the root for legacy compatibility
  if curl -sSL "$base_url/favicon.ico" -o "$target" && is_valid_image "$target"; then
    return 0
  fi
  return 1
}

# Method 4: Fallback to Google S2 Favicon service
# This is a reliable fallback that uses Google's cache if local checks fail.
# shellcheck disable=SC2329
fetch_google_s2() {
  local domain="$1" base_url="$2" target="$3"
  
  # Construct the Google S2 API URL with a requested size of 128px
  local google_url="https://www.google.com/s2/favicons?domain=${domain}&sz=128"
  
  # Fetch and validate the image from the external service
  if curl -sSL "$google_url" -o "$target" && is_valid_image "$target"; then
    return 0
  fi
  return 1
}

# Download the main page HTML once to be used by scrapers
TMP_HTML=$(mktemp)
curl -sSL -A "$CURL_UA" "$BASE_URL" -o "$TMP_HTML" || true

TMP_ICON=$(mktemp)
SUCCESS=false

# Priority-ordered list of methods to attempt
for method in "fetch_pwa_manifest" "fetch_html_icon" "fetch_direct_favicon" "fetch_google_s2"; do
  log "Attempting method: $method"
  # Scrapers require the HTML file; direct/service methods do not
  if [[ "$method" == fetch_pwa_manifest || "$method" == fetch_html_icon ]]; then
      "$method" "$DOMAIN" "$BASE_URL" "$TMP_ICON" "$TMP_HTML" && SUCCESS=true
  else
      "$method" "$DOMAIN" "$BASE_URL" "$TMP_ICON" && SUCCESS=true
  fi

  # If a method succeeds, finalize the icon file and exit
  if [ "$SUCCESS" = true ]; then
    mv "$TMP_ICON" "$ICON_FILE"
    rm -f "$TMP_HTML"
    echo "$ICON_FILE"
    exit 0
  fi
done

# Cleanup on failure
rm -f "$TMP_HTML" "$TMP_ICON"
error "Failed to download icon for $DOMAIN"
exit 1