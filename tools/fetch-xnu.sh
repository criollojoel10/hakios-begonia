#!/bin/bash
# Fetch the XNU kernel built by the kernel workflow and the reference hello
# userland, with pinned provenance.  Writes xnu/hakios-kernel and build/hello.
#
#   tools/fetch-xnu.sh [RUN_ID]
#
# Without RUN_ID it takes the latest successful kernel run of this repository.
# Needs gh authenticated for this repository (or GITHUB_TOKEN).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO=${REPO:-criollojoel10/hakios-begonia}
HELLO_COMMIT=${HELLO_COMMIT:-a962798418fa1ebaa06554a69955803860907c6b}
RUN=${1:-}
[ -n "$RUN" ] || RUN=$(gh run list -R "$REPO" --workflow=kernel.yml --status success --limit 1 --json databaseId --jq '.[0].databaseId')
[ -n "$RUN" ] || { echo "fetch-xnu: no successful kernel run; pass a RUN_ID" >&2; exit 1; }
mkdir -p "$HERE/xnu" "$HERE/build"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "fetch-xnu: kernel artifact from run $RUN"
gh run download -R "$REPO" "$RUN" -D "$TMP"
K=$(find "$TMP" -name hakios-kernel -type f | head -1)
[ -n "$K" ] || { echo "fetch-xnu: the artifact has no hakios-kernel" >&2; exit 1; }
file "$K" | grep -q 'Mach-O' || { echo "fetch-xnu: $K is not a Mach-O: $(file -b "$K")" >&2; exit 1; }
cp "$K" "$HERE/xnu/hakios-kernel"
curl -fsSL "https://raw.githubusercontent.com/oosexgang/hakios-xnu-kernel/$HELLO_COMMIT/prebuilt/userland/hello" -o "$HERE/build/hello"
chmod +x "$HERE/build/hello"
file "$HERE/xnu/hakios-kernel" "$HERE/build/hello"
sha256sum "$HERE/xnu/hakios-kernel" "$HERE/build/hello"
echo "fetch-xnu: run $RUN, hello $HELLO_COMMIT"
