#!/bin/bash
# update_helpers_auto_v1.sh
# - Detects helper files in the repo's helpers/ directory via GitHub API
# - Downloads each helper, makes it executable, and links it into /usr/local/bin
# - Safe to run repeatedly; skips files that can't be fetched

set -euo pipefail
IFS=$'\n\t'

# Configuration
HELPER_DIR="/opt/demos-node/helpers"
GLOBAL_BIN="/usr/local/bin"
GITHUB_OWNER="weudlll-cyber"
GITHUB_REPO="demos-installer-v2"
GITHUB_BRANCH="main"
API_URL="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/helpers?ref=${GITHUB_BRANCH}"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/${GITHUB_BRANCH}/helpers"

mkdir -p "${HELPER_DIR}" "${GLOBAL_BIN}" || true
echo "Fetching helper list from ${API_URL} ..."

# Query GitHub API for files in helpers/ (public repo, no auth required)
files_json="$(curl -fsSL "${API_URL}" 2>/dev/null || true)"
if [ -z "${files_json}" ]; then
  echo "Warning: unable to fetch helpers list from GitHub API; falling back to static known-names (if any)."
  declare -a FILES=()
else
  # Extract filenames from JSON (safe simple parsing)
  mapfile -t FILES < <(printf "%s\n" "${files_json}" | grep -oP '"name":\s*"\K[^"]+' || true)
fi

# If API returned nothing, optionally define a conservative static fallback (empty here)
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No helper files detected via API and no fallback list provided. Exiting."
  exit 0
fi

echo "Detected helper files:"
for f in "${FILES[@]}"; do echo "  - ${f}"; done

# Download and install each file
for fname in "${FILES[@]}"; do
  # Ensure we only handle reasonable filenames and avoid directory traversal
  safe_name="$(basename "${fname}")"
  raw_url="${RAW_BASE}/${safe_name}"
  dst_path="${HELPER_DIR}/${safe_name}"
  tmp_path="${dst_path}.tmp.$$"

  echo "Fetching ${raw_url} ..."
  if curl -fsSL "${raw_url}" -o "${tmp_path}"; then
    chmod +x "${tmp_path}"
    mv -f "${tmp_path}" "${dst_path}"

    # Symlink strategy:
    # - For files with an extension (e.g., .sh), create a symlink without the extension.
    # - For extensionless files (e.g., restart_manual_flow), link as-is.
    base_no_ext="${safe_name%.*}"
    link_target="${GLOBAL_BIN}/${base_no_ext}"

    # If stripping yields the same name (i.e., no extension), link as-is.
    if [ "${base_no_ext}" = "${safe_name}" ]; then
      link_target="${GLOBAL_BIN}/${safe_name}"
    fi

    ln -sf "${dst_path}" "${link_target}"
    echo "Installed and linked: ${safe_name} -> ${link_target}"
  else
    echo "Warning: failed to fetch ${raw_url}; skipping ${safe_name}."
    rm -f "${tmp_path}" || true
  fi
done

echo "Helpers update finished. Installed files in ${HELPER_DIR} and symlinked to ${GLOBAL_BIN}."
echo "Available helper commands (symlinks):"
# List symlinks for detected files, showing both extensionless and stripped names
for f in "${FILES[@]}"; do
  bn="${f%.*}"
  if [ "${bn}" = "${f}" ]; then
    # extensionless
    cmd="${f}"
  else
    # had an extension, we symlinked to the stripped name
    cmd="${bn}"
  fi
  ls -l "${GLOBAL_BIN}/${cmd}" 2>/dev/null || true
done
