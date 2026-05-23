#!/usr/bin/env bash
set -euo pipefail

tag_name="${1:?Usage: generate-release-notes.sh <tag> [output] [artifacts-dir]}"
output_path="${2:-release_notes.md}"
artifacts_dir="${3:-artifacts}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

windows_links=""
macos_links=""
linux_links=""
other_links=""

append_link() {
  local os="$1"
  local label="$2"
  local arch="$3"
  local color="$4"
  local logo="$5"
  local filename="$6"
  local url="https://github.com/${repo}/releases/download/${tag_name}/${filename}"
  local link="[![${label}](https://img.shields.io/badge/${label}-${arch}-${color}?logo=${logo})](${url})"

  case "$os" in
    windows) windows_links="${windows_links} ${link}" ;;
    macos) macos_links="${macos_links} ${link}" ;;
    linux) linux_links="${linux_links} ${link}" ;;
    *) other_links="${other_links} [${filename}](${url})" ;;
  esac
}

while IFS= read -r file; do
  filename="$(basename "$file")"
  arch="Universal"

  case "$filename" in
    *amd64*) arch="x64" ;;
    *arm64*) arch="ARM64" ;;
  esac

  case "$filename" in
    *windows*setup.exe)
      append_link "windows" "Installer" "$arch" "blue" "windows" "$filename"
      ;;
    *windows*portable.zip)
      append_link "windows" "Portable" "$arch" "blue" "windows" "$filename"
      ;;
    *macos*.dmg)
      [ "$arch" = "ARM64" ] && arch="Apple Silicon"
      append_link "macos" "DMG" "$arch" "black" "apple" "$filename"
      ;;
    *linux*.deb)
      append_link "linux" "DEB" "$arch" "orange" "linux" "$filename"
      ;;
    *linux*.AppImage)
      append_link "linux" "AppImage" "$arch" "orange" "linux" "$filename"
      ;;
    *)
      append_link "other" "Asset" "$arch" "lightgrey" "github" "$filename"
      ;;
  esac
done < <(find "$artifacts_dir" -type f | sort)

{
  gh api "repos/${repo}/releases/generate-notes" \
    -f tag_name="${tag_name}" \
    --jq .body

  echo
  echo "Download based on your OS:"
  echo
  echo "| OS | Download |"
  echo "| --- | --- |"
  if [ -n "$windows_links" ]; then
    echo "| Windows |${windows_links} |"
  fi
  if [ -n "$macos_links" ]; then
    echo "| macOS |${macos_links} |"
  fi
  if [ -n "$linux_links" ]; then
    echo "| Linux |${linux_links} |"
  fi
  if [ -n "$other_links" ]; then
    echo "| Other |${other_links} |"
  fi
} > "$output_path"
