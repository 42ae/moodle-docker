#!/usr/bin/env bash
set -Eeuo pipefail

manifest="${1:-versions.json}"
updates=''

while IFS=$'\t' read -r series current; do
    latest="$(
        git ls-remote --tags https://github.com/moodle/moodle.git "refs/tags/v${series}.*" \
            | awk '{print $2}' \
            | sed -E 's#refs/tags/v##; /\^\{\}$/d; /-(alpha|beta|rc)/d' \
            | sort -V \
            | tail -1
    )"

    if [ -n "$latest" ] && [ "$latest" != "$current" ]; then
        updates+="- Moodle ${series}: ${current} -> ${latest}"$'\n'
    fi
done < <(jq -r '.versions[] | select(.support == "stable" or .support == "lts-security") | [.series, .moodle] | @tsv' "$manifest")

if [ -n "$updates" ]; then
    printf '# New Moodle releases available\n\n%s' "$updates"
    exit 1
fi

echo 'All maintained Moodle series are current.'
