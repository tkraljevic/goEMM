#!/usr/bin/env sh
# goEMM installer for macOS and Linux.
#
# Installing by hand is six steps, and v0.6.2 showed that most of them are
# places to go wrong quietly. This script collapses them into one command —
# but the point is not brevity, it is that every step FAILS LOUDLY. The
# manual instructions did not:
#
#   - Downloading with a bad or missing token returns Forgejo's sign-in
#     page as a normal 200 OK. Fourteen kilobytes of HTML named `emm`,
#     chmod +x, and the error you get is "cannot execute binary file".
#   - There is no `latest/download` alias, so a GitHub-shaped URL returns
#     eleven bytes reading `Not found.` — which also chmods fine.
#   - The manual steps verify no checksum at all, and the obvious way to
#     add one (`shasum -c --ignore-missing`) matches nothing when the file
#     has been renamed to `emm`, prints nothing, and exits 0.
#
# So: every download is checked for being what it claims, the checksum is
# compared explicitly against the manifest entry for the exact asset name,
# and the installed binary is made to prove itself by running.
#
# Usage:
#   sh install.sh                 install or report an existing install
#   sh install.sh --force         reinstall even if one is already there
#   EMM_INSTALL_DIR=/tmp/x sh install.sh    install somewhere else (testing)
set -eu

HOST="${EMM_HOST:-https://github.com}"
REPO="${EMM_REPO:-tkraljevic/goEMM}"
# No token by default, on purpose.
#
# This fetches from the DOWNLOADS repository — builds only, no source. Once
# that repository is public it needs no credential at all, and there is
# nothing here for anyone to extract. While it is private, whoever installs
# supplies one:  EMM_TOKEN=... sh install.sh
#
# The previous version of this script carried a token said to be harmless
# because it could only fetch releases. It could also fetch the entire
# private source tree.
TOKEN="${EMM_TOKEN:-}"
DIR="${EMM_INSTALL_DIR:-$HOME/.emm}"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

say() { printf '%s\n' "$*"; }
die() { printf '\n%s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "This needs $1, which is not on this machine."
}
need curl

# --- which build ------------------------------------------------------
os=$(uname -s)
arch=$(uname -m)
case "$os" in
  Darwin) os=darwin ;;
  Linux)  os=linux ;;
  *) die "goEMM has no build for $os. Supported: macOS and Linux (Windows: install.ps1)." ;;
esac
case "$arch" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64)  arch=amd64 ;;
  *) die "goEMM has no build for $arch. Supported: arm64 and amd64." ;;
esac
asset="emm-$os-$arch"
say "Installing goEMM for $os/$arch into $DIR"

# --- already here? ----------------------------------------------------
if [ -x "$DIR/emm" ] && [ "$FORCE" -eq 0 ]; then
  have=$("$DIR/emm" version 2>/dev/null || true)
  die "goEMM is already installed at $DIR/emm${have:+ ($have)}.

To move to the newest version, use its own updater, which keeps a copy of
the one it replaces:

  $DIR/emm update

To install over it anyway:  sh install.sh --force
  (that replaces the program only — your memories are a separate file.)"
fi

# curl_auth exists so the Authorization header is present or absent, never
# present-and-empty: an empty -H argument is not the same as no argument,
# and building the command as a string to work around that is how quoting
# bugs get in.
curl_auth() { # curl_auth <accept> <output> <url>
  if [ -n "$TOKEN" ]; then
    curl -sSL -w '%{http_code}' -H "Accept: $1" -H "Authorization: Bearer $TOKEN" -o "$2" "$3"
  else
    curl -sSL -w '%{http_code}' -H "Accept: $1" -o "$2" "$3"
  fi
}

fetch() { # fetch <url> <output> [accept]
  accept="${3:-application/json}"
  code=$(curl_auth "$accept" "$2" "$1") || \
    die "Could not reach $HOST. Check the network, then try again."
  if [ "$code" = "404" ]; then
    die "$HOST answered 404 for
  $1

The release is missing that file, or EMM_HOST/EMM_REPO point somewhere
that is not a goEMM release host. Nothing was installed."
  fi
  [ "$code" = "200" ] || die "$HOST answered $code for
  $1
Nothing was installed."
  # A release host can answer 200 with something that is not the file:
  # Forgejo serves its sign-in PAGE that way, and GitHub's asset address
  # returns the asset's JSON description unless asked for octet-stream.
  # Catching it here is the difference between a clear message and
  # 'cannot execute binary file' half an hour later.
  case $(head -c 15 "$2" | tr 'A-Z' 'a-z') in
    *'<!doctype html'*|*'<html'*)
      rm -f "$2"
      die "That download returned a web page instead of a file.

The token is probably wrong or expired. Set a working one:
  EMM_TOKEN=... sh install.sh" ;;
  esac
}

# --- which version ----------------------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# release.json is what every release carries since v0.8.162: tag, notes
# and the download address of each file. Read from the download CDN's
# "latest" alias, never from the GitHub API — the API allows sixty
# unauthenticated requests an hour per address, and an installer that
# shares an address with a few other machines then fails with 403 (#137).
fetch "$HOST/$REPO/releases/latest/download/release.json" "$tmp/rel.json"
# -n with an explicit p: without it sed prints every line it does NOT
# match, and `ver` becomes the whole response with one line rewritten.
ver=$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' "$tmp/rel.json" | head -1)
case "$ver" in
  v*) : ;;
  *) die "Could not read the latest version from release.json. Nothing was installed." ;;
esac
say "Newest release: $ver"

# --- download and prove it is what it claims --------------------------
#
# By tag, from the download CDN: the same address release.json lists for
# each file. No asset ids, no API.
get_asset() { # get_asset <name> <output>
  fetch "$HOST/$REPO/releases/download/$ver/$1" "$2" "application/octet-stream"
}
get_asset "$asset" "$tmp/$asset"
get_asset "SHA256SUMS.txt" "$tmp/SHA256SUMS.txt"

want=$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1; found=1 } END { if (!found) exit 1 }' \
  "$tmp/SHA256SUMS.txt") || die "The checksum file does not list $asset.

That means the release is incomplete, not that your download is bad.
Nothing was installed."

if command -v shasum >/dev/null 2>&1; then
  got=$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then
  got=$(sha256sum "$tmp/$asset" | awk '{print $1}')
else
  die "This needs shasum or sha256sum to verify the download, and has neither."
fi
[ "$want" = "$got" ] || die "The download does not match its published checksum.

  expected  $want
  got       $got

Nothing was installed. Try again; if it repeats, say so — a mismatch that
survives a retry is worth knowing about."
say "Checksum verified."

# --- put it in place and make it prove itself -------------------------
mkdir -p "$DIR"
chmod +x "$tmp/$asset"
mv "$tmp/$asset" "$DIR/emm"
# macOS quarantines anything downloaded, and the first run then fails with
# a dialog rather than a message. Removing it here is the same decision the
# user would make in that dialog, taken before it interrupts them.
[ "$os" = "darwin" ] && xattr -d com.apple.quarantine "$DIR/emm" 2>/dev/null || true

installed=$("$DIR/emm" version 2>/dev/null) || die "The binary was installed but will not run.

  $DIR/emm version

failed. The file is in place; nothing else was changed."
say "Installed: $installed"

say ""
say "Next:"
say "  $DIR/emm demo          see what it does, on a throwaway database"
say "  $DIR/emm setup         connect your AI assistants"
say "  $DIR/emm setup path    so you can type 'emm' from anywhere"
