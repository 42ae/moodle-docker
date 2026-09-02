#!/usr/bin/env bash
set -Eeuo pipefail

manifest="${1:-versions.json}"

jq -e '.versions | length > 0' "$manifest" >/dev/null
jq -e '[.versions[].tags[]] | length == (unique | length)' "$manifest" >/dev/null
jq -e '[.versions[] | select(.tags | index("latest"))] | length == 1' "$manifest" >/dev/null

while IFS=$'\t' read -r version branch expected; do
    checksum_url="https://packaging.moodle.org/stable${branch}/moodle-${version}.tgz.sha256"
    actual="$(curl -fsSL "$checksum_url" | awk '{print $NF}')"
    if [ "$actual" != "$expected" ]; then
        echo >&2 "Checksum mismatch for Moodle ${version}: expected ${expected}, received ${actual}"
        exit 1
    fi
done < <(jq -r '.versions[] | [.moodle, .branch, .sha256] | @tsv' "$manifest")

echo 'Version manifest is valid and all upstream checksums match.'
