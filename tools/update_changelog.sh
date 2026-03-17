#!/bin/bash
set -euo pipefail

REPO_DIR=$(git rev-parse --show-toplevel)
CHANGELOG="$REPO_DIR/CHANGELOG.md"
PYPROJECT="pyproject.toml"
OPENBLAS_COMMIT_FILE="openblas_commit.txt"

# ── Get current version ───────────────────────────────────────────────────
version=$(grep "^version = " "$PYPROJECT" | sed 's/version = "//;s/"//')

# ── Check version is different from main ─────────────────────────────────
main_version=$(git show origin/main:"$PYPROJECT" | grep "^version = " | sed 's/version = "//;s/"//')
if [[ "$version" == "$main_version" ]]; then
    echo "ERROR: pyproject.toml version ($version) is the same as main."
    echo "Please bump the version before submitting a PR."
    exit 1
fi

# ── Guard: skip if version already in changelog ───────────────────────────
if grep -q "^### $version " "$CHANGELOG" 2>/dev/null; then
    echo "CHANGELOG.md already contains $version — skipping."
    exit 0
fi

# ── Get OpenBLAS info ─────────────────────────────────────────────────────
openblas_raw=$(cat "$OPENBLAS_COMMIT_FILE")
openblas_tag=$(echo "$openblas_raw" | sed 's/^\(v[0-9]*\.[0-9]*\.[0-9]*\)-\([0-9]*\).*/\1.\2/')

# ── Detect if OpenBLAS version changed vs main ────────────────────────────
main_openblas_raw=$(git show origin/main:"$OPENBLAS_COMMIT_FILE" 2>/dev/null || true)

# ── Get date ──────────────────────────────────────────────────────────────
date_str=$(date +%Y-%m-%d)

# ── Get first meaningful commit message ───────────────────────────────────
merge_base=$(git merge-base origin/main HEAD)
first_commit_msg=$(git log "$merge_base"..HEAD --format="%s" --reverse \
    | grep -iv "^typo\|^fix test\|^wip\|^minor\|^cleanup\|^merge" \
    | head -1 || true)
[[ -z "$first_commit_msg" ]] && first_commit_msg="(no description)"

# ── Build new entry ───────────────────────────────────────────────────────
new_entry=""
if [[ -n "$main_openblas_raw" && "$openblas_raw" != "$main_openblas_raw" ]]; then
    new_entry="## OpenBLAS $openblas_tag ($openblas_raw)\n\n"
fi
new_entry+="### $version ($date_str)\n- $first_commit_msg\n\n"

# ── Prepend to changelog ──────────────────────────────────────────────────
existing=$(cat "$CHANGELOG" 2>/dev/null || true)

if [[ -n "$main_openblas_raw" && "$openblas_raw" != "$main_openblas_raw" ]]; then
    # New OpenBLAS header + entry go at the very top
    printf "%b%s" "$new_entry" "$existing" > "$CHANGELOG"
else
    # Insert ### entry after the existing ## OpenBLAS header
    printf "%b" "$existing" | awk -v entry="### $version ($date_str)\n- $first_commit_msg\n" '
        /^### /{
            if (!inserted) {
                printf "%s\n", entry
                inserted=1
            }
        }
        { print }
    ' > "$CHANGELOG"
fi
echo "Changelog updated: $version"
echo "Please review and edit CHANGELOG.md before committing."
