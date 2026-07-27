#!/usr/bin/env bash
# kimi-fetch installer
#
#   curl -fsSL https://raw.githubusercontent.com/marsninja/kimi-fetch/main/install.sh | bash
#
# Options (pass after `bash -s --`):
#   --version vX.Y.Z   install a specific release (default: latest)
#   --to DIR           install directory (default: ~/.local/bin)
#
# Downloads the prebuilt binary for this platform from GitHub Releases,
# verifies its sha256, and installs it as `kimi-fetch`. No API calls, no
# token needed: the latest release publishes version-less asset aliases.
set -euo pipefail

REPO="marsninja/kimi-fetch"
VERSION="latest"
DEST="${HOME}/.local/bin"

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      [ $# -ge 2 ] || { echo "error: --version needs an argument (e.g. v0.1.0)" >&2; exit 2; }
      VERSION="$2"; shift 2 ;;
    --to)
      [ $# -ge 2 ] || { echo "error: --to needs a directory" >&2; exit 2; }
      DEST="$2"; shift 2 ;;
    *)
      echo "error: unknown option: $1" >&2; exit 2 ;;
  esac
done

os="$(uname -s)"
arch="$(uname -m)"
case "${os}/${arch}" in
  Linux/x86_64)  target="linux-x86_64" ;;
  Darwin/arm64)  target="macos-arm64" ;;
  *)
    echo "error: no prebuilt kimi-fetch binary for ${os}/${arch}" >&2
    echo "build from source instead: see https://github.com/${REPO}#building" >&2
    exit 1 ;;
esac

if [ "$VERSION" = "latest" ]; then
  asset="kimi-fetch-${target}.tar.gz"
  url="https://github.com/${REPO}/releases/latest/download/${asset}"
else
  asset="kimi-fetch-${VERSION}-${target}.tar.gz"
  url="https://github.com/${REPO}/releases/download/${VERSION}/${asset}"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "[kimi-fetch] downloading ${url}"
curl -fSL --retry 3 --progress-bar -o "${tmp}/${asset}" "$url"

if curl -fsSL -o "${tmp}/${asset}.sha256" "${url}.sha256"; then
  if (cd "$tmp" && { command -v shasum >/dev/null && shasum -a 256 -c "${asset}.sha256" >/dev/null 2>&1; } \
      || { command -v sha256sum >/dev/null && sha256sum -c "${asset}.sha256" >/dev/null 2>&1; }); then
    echo "[kimi-fetch] checksum OK"
  else
    echo "error: checksum verification failed for ${asset}" >&2
    exit 1
  fi
else
  echo "[kimi-fetch] warning: no published checksum for this asset; skipping verification"
fi

tar -xzf "${tmp}/${asset}" -C "$tmp"
bin="$(find "$tmp" -type f -name kimi-fetch | head -1)"
[ -n "$bin" ] || { echo "error: kimi-fetch binary not found in archive" >&2; exit 1; }

mkdir -p "$DEST"
install -m 755 "$bin" "${DEST}/kimi-fetch"
echo "[kimi-fetch] installed ${DEST}/kimi-fetch"

case ":${PATH}:" in
  *":${DEST}:"*) ;;
  *) echo "[kimi-fetch] note: ${DEST} is not on your PATH" ;;
esac
echo "[kimi-fetch] get started:  kimi-fetch --help"
