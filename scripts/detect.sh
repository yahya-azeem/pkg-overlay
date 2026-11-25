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
        want="$(desired_version "$dir")" || { warn "$name: upstream lookup failed, skipping"; exit 0; }
        want_up="$(desired_upstream)"
        have="$(state_version "$dir")"
        have_up="$(state_upstream "$dir")"
        if [[ -n "$have" && "$want_up" == "$have_up" ]]; then
            log "$name: $have (current, upstream $want_up)" >&2
        else
            log "$name: ${have:-<not built>} -> $want (upstream ${have_up:-none} -> $want_up)" >&2
            printf 'changed %s\n' "$name"
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
