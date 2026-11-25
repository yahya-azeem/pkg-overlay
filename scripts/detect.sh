#!/usr/bin/env bash
# Compare each tracked package's upstream version with the last built version
# and emit a GitHub Actions matrix for the ones that changed.
set -Eeuo pipefail

source "$(dirname -- "$0")/lib.sh"

changed_file="$(mktemp)"
trap 'rm -f "$changed_file"' EXIT

while IFS= read -r dir; do
    name="$(basename "$dir")"
    (
        unset TRACK UPSTREAM BUILD
        source "$dir/meta.sh"
        want="$(desired_version)" || { warn "$name: upstream lookup failed, skipping"; exit 0; }
        have="$(state_version "$dir")"
        if [[ "$want" != "$have" ]]; then
            log "$name: ${have:-<not built>} -> $want" >&2
            printf 'changed %s\n' "$name"
        else
            log "$name: $want (current)" >&2
        fi
    ) | while read -r kind pkg; do
        [[ "$kind" == changed ]] && printf '%s\n' "$pkg" >> "$changed_file"
    done
done < <(package_dirs)

mapfile -t changed < <(sort -u "$changed_file")

if (( ${#changed[@]} > 0 )); then
    matrix="$(printf '%s\n' "${changed[@]}" | jq -R . | jq -cs '{include: map({pkg: ., dir: .})}')"
    any=true
else
    matrix='{"include":[]}'
    any=false
fi

echo "matrix=$matrix"
echo "any=$any"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "matrix=$matrix"
        echo "any=$any"
    } >> "$GITHUB_OUTPUT"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "## pkg-overlay"
        if (( ${#changed[@]} > 0 )); then
            echo "Rebuilding: ${changed[*]}"
        else
            echo "Everything is up to date."
        fi
    } >> "$GITHUB_STEP_SUMMARY"
fi
