#!/usr/bin/env bash
# Checks the website in site/ before .github/workflows/pages.yml publishes it on GitHub Pages:
#
#   - lists the TODO(owner) placeholders that still wait for the owner's data (address, email, phone), as file:line,
#   - checks that the landing page and the four privacy and support pages exist, with the Impressum anchor,
#   - checks that every internal href and src resolves to a file inside site/, and every #fragment to an id,
#   - checks that the page URLs in fastlane/metadata/*/ point at pages that exist.
#
# Usage: scripts/check_site.sh [--placeholders-only]
#
# Exit status:
#   0   the site is complete and every link resolves: ready to publish
#   1   only TODO(owner) placeholders remain: the pages are fine, but not ready to publish
#   2   a page, a link or a page URL is broken (reported whether or not placeholders remain)
#   64  unknown option
# --placeholders-only skips the page and link checks and exits with 0 or 1.
set -euo pipefail

cd "$(dirname "$0")/.."

site=site
base_url="https://juliusedel.github.io/eggscape/"
pages=(index.html de/datenschutz/index.html de/support/index.html en/privacy/index.html en/support/index.html)

usage() {
    sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
}

placeholders_only=false
for argument in "$@"; do
    case "$argument" in
        --placeholders-only) placeholders_only=true ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n\n' "$argument" >&2
            usage >&2
            exit 64
            ;;
    esac
done

if [[ ! -d $site ]]; then
    printf 'error: %s/ does not exist\n' "$site" >&2
    exit 2
fi

# Placeholders: one line per occurrence, "file:line: TODO(owner): what is missing".
placeholder_list=$(
    { grep -rnoE 'TODO\(owner\)(: [^<.,;]*)?' "$site" || true; } |
        sed -E 's/^([^:]*:[0-9]+):/\1: /' | sort -t: -k1,1 -k2,2n
)
placeholder_count=0
if [[ -n $placeholder_list ]]; then
    placeholder_count=$(printf '%s\n' "$placeholder_list" | wc -l | tr -d ' ')
    printf 'TODO(owner) placeholders left in %s/ (%s):\n%s\n' "$site" "$placeholder_count" "$placeholder_list"
fi

if [[ $placeholders_only == true ]]; then
    if ((placeholder_count > 0)); then
        exit 1
    fi
    printf 'No TODO(owner) placeholders left in %s/.\n' "$site"
    exit 0
fi

errors=0
fail() {
    printf 'error: %s\n' "$*" >&2
    errors=$((errors + 1))
}

site_root=$(cd "$site" && pwd -P)

# Checks one reference from `source` (a page, or a fastlane URL file): a relative path, a link to the site's own
# public URL, or a #fragment. Links to other sites, mailto: and tel: are not checked.
check_reference() {
    local source=$1 reference=$2 target fragment="" resolved
    if [[ $reference == *"#"* ]]; then
        fragment=${reference#*#}
        reference=${reference%%#*}
    fi
    reference=${reference%%\?*}
    case "$reference" in
        "") target=$source ;;
        "$base_url"*) target="$site/${reference#"$base_url"}" ;;
        http:* | https:* | mailto:* | tel:* | data:*) return 0 ;;
        /*)
            # GitHub Pages serves this project site under /eggscape/, so a path from the domain root breaks.
            fail "$source: $reference starts at the domain root; use a relative path"
            return 0
            ;;
        *) target="$(dirname "$source")/$reference" ;;
    esac
    if [[ -d $target || $target == */ ]]; then
        target="${target%/}/index.html"
    fi
    if [[ ! -f $target ]]; then
        fail "$source: ${reference:-#$fragment} does not resolve to a file"
        return 0
    fi
    resolved="$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
    if [[ $resolved != "$site_root"/* ]]; then
        fail "$source: $reference points outside $site/"
        return 0
    fi
    if [[ -n $fragment && $target == *.html ]] && ! grep -qF "id=\"$fragment\"" "$target"; then
        fail "$source: #$fragment is not an id in $target"
    fi
}

for page in "${pages[@]}"; do
    if [[ ! -f $site/$page ]]; then
        fail "missing page $site/$page"
    fi
done
if [[ -f $site/de/support/index.html ]] && ! grep -q 'id="impressum"' "$site/de/support/index.html"; then
    fail "$site/de/support/index.html has no section with id=\"impressum\""
fi

page_count=0
reference_count=0
while IFS= read -r page; do
    page_count=$((page_count + 1))
    while IFS= read -r reference; do
        reference_count=$((reference_count + 1))
        check_reference "$page" "$reference"
    done < <({ grep -oE '(href|src)="[^"]*"' "$page" || true; } | sed -E 's/^(href|src)="//; s/"$//')
done < <(find "$site" -name '*.html' | sort)

# The privacy, support and marketing URLs App Store Connect gets from fastlane must be pages of this site.
url_count=0
for file in fastlane/metadata/*/privacy_url.txt fastlane/metadata/*/support_url.txt \
    fastlane/metadata/*/marketing_url.txt; do
    [[ -f $file ]] || continue
    url_count=$((url_count + 1))
    url=$(tr -d '[:space:]' <"$file")
    if [[ $url != "$base_url"* ]]; then
        fail "$file: $url is not a page of $base_url"
        continue
    fi
    check_reference "$file" "$url"
done

if ((errors > 0)); then
    printf '%s problem(s) with the pages, links or page URLs.\n' "$errors" >&2
    exit 2
fi
printf 'Pages and links are fine: %s pages, %s references, %s fastlane page URLs.\n' \
    "$page_count" "$reference_count" "$url_count"
if ((placeholder_count > 0)); then
    printf 'Not ready to publish: fill in the TODO(owner) placeholders above.\n'
    exit 1
fi
printf 'Ready to publish.\n'
