#!/usr/bin/env bash
# Print a Markdown summary of last week's package downloads and repo traffic.
#
# Usage:
#   tools/weekly-stats.sh            # summary for the 7 days ending yesterday (UTC)
#   tools/weekly-stats.sh --end DATE # ... ending DATE (YYYY-MM-DD) instead
#
# Needs: curl, jq, gh (logged in with push access to the org's repos, for the
# traffic endpoints). Registry APIs are public.
#
# Sources:
#   crates.io  /api/v1/crates/NAME/downloads   daily, last 90 days
#   PyPI       pypistats.org overall?mirrors=false   daily, last 180 days
#   npm        api.npmjs.org/downloads/range        daily
#   traffic    GitHub traffic API, public repos only (the summary is posted publicly)
# A source that fails shows "n/a" in its row; the rest of the summary is still printed.

set -euo pipefail

ORG=project-minigraf
UA="project-minigraf weekly-stats (https://github.com/$ORG/.github)"

# Registry, package name, label. Add new published packages here.
PACKAGES=(
  "crates minigraf minigraf (Rust)"
  "pypi minigraf minigraf (Python)"
  "npm minigraf minigraf (Node.js)"
  "npm @minigraf/browser @minigraf/browser"
  "npm @minigraf/wasi @minigraf/wasi"
  "pypi temporal-reasoning temporal-reasoning"
)

END=$(date -u -d yesterday +%F)
while [[ $# -gt 0 ]]; do
  case $1 in
    --end) END=$2; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
START=$(date -u -d "$END - 6 days" +%F)
PREV_END=$(date -u -d "$START - 1 day" +%F)
PREV_START=$(date -u -d "$END - 13 days" +%F)

fetch() {
  curl -fsS --retry 3 --retry-delay 5 -A "$UA" "$1"
}

# Each fetcher prints a JSON array of {d: "YYYY-MM-DD", n: count}.
daily_crates() {
  fetch "https://crates.io/api/v1/crates/$1/downloads" |
    jq '[(.version_downloads[], .meta.extra_downloads[]) | {d: .date, n: .downloads}]'
}
daily_pypi() {
  fetch "https://pypistats.org/api/packages/$1/overall?mirrors=false" |
    jq '[.data[] | select(.category == "without_mirrors") | {d: .date, n: .downloads}]'
}
daily_npm() {
  fetch "https://api.npmjs.org/downloads/range/$PREV_START:$END/$1" |
    jq '[.downloads[] | {d: .day, n: .downloads}]'
}

# sum DAILY FROM TO: total of the days in [FROM, TO].
sum() {
  jq --arg from "$2" --arg to "$3" '[.[] | select(.d >= $from and .d <= $to) | .n] | add // 0' <<<"$1"
}

change() {
  local now=$1 prev=$2
  if [[ $prev -eq 0 ]]; then
    echo "—"
  else
    awk -v a="$now" -v b="$prev" 'BEGIN { printf "%+.0f%%", (a - b) * 100 / b }'
  fi
}

echo "Week **$START** to **$END** (UTC). Previous week: $PREV_START to $PREV_END."
echo
echo "## Downloads"
echo
echo "| Package | Registry | This week | Previous week | Change |"
echo "|---|---|--:|--:|--:|"
for entry in "${PACKAGES[@]}"; do
  read -r registry name label <<<"$entry"
  if daily=$("daily_$registry" "$name" 2>/dev/null); then
    now=$(sum "$daily" "$START" "$END")
    prev=$(sum "$daily" "$PREV_START" "$PREV_END")
    echo "| $label | $registry | $now | $prev | $(change "$now" "$prev") |"
  else
    echo "::warning::$registry $name: fetch failed" >&2
    echo "| $label | $registry | n/a | n/a | |"
  fi
done
echo
if total=$(fetch "https://crates.io/api/v1/crates/minigraf" 2>/dev/null | jq -e '.crate.downloads'); then
  echo "crates.io all-time: **$total**."
  echo
fi
echo "PyPI counts exclude mirrors. All counts include CI and bot downloads. Maven Central"
echo "(Java, Android), SwiftPM and the C release assets have no public download counts; see"
echo "repo traffic below for those."
echo
echo "## Repo traffic"
echo
echo "Public repos, $START to $END. Clones include CI checkouts."
echo
echo "| Repo | Views | Clones |"
echo "|---|--:|--:|"
rows=()
for repo in $(gh repo list "$ORG" --visibility public --no-archived --limit 100 --json name --jq '.[].name'); do
  if views=$(gh api "repos/$ORG/$repo/traffic/views" 2>/dev/null) &&
    clones=$(gh api "repos/$ORG/$repo/traffic/clones" 2>/dev/null); then
    v=$(sum "$(jq '[.views[] | {d: .timestamp[:10], n: .count}]' <<<"$views")" "$START" "$END")
    c=$(sum "$(jq '[.clones[] | {d: .timestamp[:10], n: .count}]' <<<"$clones")" "$START" "$END")
    rows+=("$v	$c	$repo")
  else
    echo "::warning::$repo: traffic fetch failed" >&2
    rows+=("-1	-1	$repo")
  fi
done
printf '%s\n' "${rows[@]}" | sort -t$'\t' -k1,1nr -k2,2nr |
  awk -F'\t' '$1 < 0 { print "| " $3 " | n/a | n/a |"; next }
              { print "| " $3 " | " $1 " | " $2 " |" }'
