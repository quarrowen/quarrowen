#!/usr/bin/env bash
# Does this private key match a public key the shipped client trusts?
#
#   tools/check_release_key.sh ~/.config/quarrowen/release_key.pem
#
# Compares the public half derived from the private key against every entry in updater.gd's
# RELEASE_KEYS. Exit 0 when one matches, 1 when none do, 2 when the key cannot be read at all.
#
# **Why this exists separately from tools/verify_signature.gd**: that one needs Godot and a signed file,
# which is the right check at the end of a release. This one needs neither, so it can run in a
# credentials preflight that does not build anything - and it answers the question a preflight actually
# has, which is "is the secret the right key" rather than "did signing work". (2026-09-29)
set -uo pipefail
cd "$(dirname "$0")/.."

key="${1:-$HOME/.config/quarrowen/release_key.pem}"
if [ ! -f "$key" ]; then
  echo "check_release_key: no such file: $key" >&2
  exit 2
fi

pub="$(openssl rsa -in "$key" -pubout 2>/dev/null)"
if [ -z "$pub" ]; then
  # An OpenSSL failure here is usually the secret having been base64'd, which turns a PEM into one long
  # line that no parser recognises.
  echo "check_release_key: could not read a private key out of $key" >&2
  echo "check_release_key: is it the raw PEM text? RELEASE_SIGNING_KEY is not base64." >&2
  exit 2
fi

# The comparison is on the base64 body alone, so a difference in line wrapping or a trailing newline
# does not read as a different key.
body() { tr -d '\r\n ' | sed 's/-----[A-Z ]*-----//g'; }
mine="$(printf '%s' "$pub" | body)"

if printf '%s' "$mine" | grep -q '^$'; then
  echo "check_release_key: derived an empty public key" >&2
  exit 2
fi

found=0
while IFS= read -r trusted; do
  [ -n "$trusted" ] || continue
  if [ "$trusted" = "$mine" ]; then found=1; fi
done < <(python3 - <<'PY'
import pathlib, re
src = pathlib.Path("engine/client/updater.gd").read_text()
block = re.search(r"const RELEASE_KEYS\s*:=\s*\[(.*?)\]", src, re.S)
for raw in re.findall(r'"((?:[^"\\]|\\.)*)"', block.group(1) if block else ""):
    pem = raw.encode().decode("unicode_escape")
    print(re.sub(r"-----[A-Z ]*-----", "", pem).replace("\r", "").replace("\n", "").replace(" ", ""))
PY
)

if [ "$found" = "1" ]; then
  echo "check_release_key: this key matches one of the client's RELEASE_KEYS"
  exit 0
fi
echo "check_release_key: THIS KEY IS NOT ONE THE CLIENT TRUSTS" >&2
echo "check_release_key: a release signed with it would be refused by every installed game." >&2
exit 1
