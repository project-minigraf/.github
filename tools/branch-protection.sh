#!/usr/bin/env bash
# Audit default-branch protection across the org and copy it from a template
# repo to any repo that has none.
#
# Usage:
#   tools/branch-protection.sh                 # audit only (dry run)
#   tools/branch-protection.sh --apply         # apply template where missing
#
# Options:
#   --org NAME          org to scan (default: project-minigraf)
#   --template REPO     repo to copy rules from (default: minigraf)
#   --keep-checks       also copy required status checks (off by default,
#                       because check names from the template usually do not
#                       exist in other repos and would block every merge)
#   --apply             make changes; without it the script only reports
#
# Needs: gh (logged in as an org admin), jq.
#
# Both kinds of protection are handled:
#   - repository rulesets: copied as new rulesets with the same name
#   - classic branch protection: copied onto the target's default branch
# A repo counts as protected if any rule (repo ruleset, org ruleset or classic
# protection) already applies to its default branch. Those repos are skipped.

set -euo pipefail

ORG=project-minigraf
TEMPLATE=minigraf
KEEP_CHECKS=0
APPLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORG="$2"; shift 2 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --keep-checks) KEEP_CHECKS=1; shift ;;
    --apply) APPLY=1; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

# Prints the classic protection JSON for a branch, or nothing if there is none.
classic_protection() {
  gh api "repos/$ORG/$1/branches/$2/protection" 2>/dev/null || true
}

# Prints the number of ruleset rules (repo or org level) that apply to a branch.
active_rule_count() {
  gh api "repos/$ORG/$1/rules/branches/$2" --jq 'length' 2>/dev/null || echo 0
}

# Converts a classic protection GET response into a PUT request body.
classic_to_put() {
  jq --argjson keep "$KEEP_CHECKS" '
    def slugs: if . == null then null else {
      users: [.users[]?.login], teams: [.teams[]?.slug], apps: [.apps[]?.slug]
    } end;
    {
      required_status_checks: (
        if $keep == 1 and .required_status_checks != null then
          { strict: .required_status_checks.strict,
            checks: [.required_status_checks.checks[]? | {context, app_id}] }
        else null end),
      enforce_admins: (.enforce_admins.enabled // false),
      required_pull_request_reviews: (
        if .required_pull_request_reviews == null then null else
          .required_pull_request_reviews | {
            dismiss_stale_reviews: (.dismiss_stale_reviews // false),
            require_code_owner_reviews: (.require_code_owner_reviews // false),
            required_approving_review_count: (.required_approving_review_count // 0),
            require_last_push_approval: (.require_last_push_approval // false),
            dismissal_restrictions: (.dismissal_restrictions | slugs // {}),
            bypass_pull_request_allowances: (.bypass_pull_request_allowances | slugs // {})
          }
        end),
      restrictions: (.restrictions | slugs),
      required_linear_history: (.required_linear_history.enabled // false),
      allow_force_pushes: (.allow_force_pushes.enabled // false),
      allow_deletions: (.allow_deletions.enabled // false),
      block_creations: (.block_creations.enabled // false),
      required_conversation_resolution: (.required_conversation_resolution.enabled // false),
      lock_branch: (.lock_branch.enabled // false),
      allow_fork_syncing: (.allow_fork_syncing.enabled // false)
    }'
}

# Converts a ruleset GET response into a POST request body.
ruleset_to_post() {
  jq --argjson keep "$KEEP_CHECKS" '
    { name, target, enforcement, conditions,
      bypass_actors: (.bypass_actors // []),
      rules: [ .rules[] | select($keep == 1 or .type != "required_status_checks") ] }'
}

# ---- Read the template ------------------------------------------------------

tpl_branch=$(gh api "repos/$ORG/$TEMPLATE" --jq .default_branch)
tpl_classic=$(classic_protection "$TEMPLATE" "$tpl_branch")
tpl_ruleset_ids=$(gh api "repos/$ORG/$TEMPLATE/rulesets?includes_parents=false" \
  --jq '.[] | select(.source_type == "Repository" and .target == "branch") | .id')

tpl_rulesets=()
for id in $tpl_ruleset_ids; do
  tpl_rulesets+=("$(gh api "repos/$ORG/$TEMPLATE/rulesets/$id" | ruleset_to_post)")
done

if [[ -z "$tpl_classic" && ${#tpl_rulesets[@]} -eq 0 ]]; then
  echo "Template $ORG/$TEMPLATE has no branch protection or branch rulesets." >&2
  exit 1
fi

echo "Template: $ORG/$TEMPLATE ($tpl_branch)"
[[ -n "$tpl_classic" ]] && echo "  classic branch protection: yes"
for rs in ${tpl_rulesets[@]+"${tpl_rulesets[@]}"}; do
  echo "  ruleset: $(jq -r .name <<<"$rs") ($(jq -r '[.rules[].type] | join(", ")' <<<"$rs"))"
done
[[ $KEEP_CHECKS -eq 0 ]] && echo "  (required status checks are not copied; use --keep-checks to copy them)"
echo

# ---- Audit and apply --------------------------------------------------------

missing=()
while IFS=$'\t' read -r repo branch archived; do
  if [[ "$archived" == "true" ]]; then
    printf '%-32s %s\n' "$repo" "skipped (archived)"; continue
  fi
  if [[ -z "$branch" || "$branch" == "null" ]]; then
    printf '%-32s %s\n' "$repo" "skipped (no default branch)"; continue
  fi

  has_classic=$([[ -n "$(classic_protection "$repo" "$branch")" ]] && echo yes || echo no)
  rules=$(active_rule_count "$repo" "$branch")

  if [[ "$has_classic" == "yes" || "$rules" -gt 0 ]]; then
    printf '%-32s %s\n' "$repo" "protected ($branch: classic=$has_classic, ruleset rules=$rules)"
  else
    printf '%-32s %s\n' "$repo" "MISSING ($branch)"
    missing+=("$repo:$branch")
  fi
done < <(gh api --paginate "orgs/$ORG/repos?per_page=100" \
  --jq '.[] | [.name, .default_branch, .archived] | @tsv' | sort)

echo
if [[ ${#missing[@]} -eq 0 ]]; then
  echo "All repos are protected. Nothing to do."
  exit 0
fi

if [[ $APPLY -eq 0 ]]; then
  echo "${#missing[@]} repo(s) need protection. Run again with --apply to copy the template."
  exit 0
fi

failed=0
for entry in "${missing[@]}"; do
  repo=${entry%%:*}; branch=${entry#*:}
  echo "Applying to $repo ($branch)..."

  for rs in ${tpl_rulesets[@]+"${tpl_rulesets[@]}"}; do
    name=$(jq -r .name <<<"$rs")
    if gh api "repos/$ORG/$repo/rulesets" --method POST --input - <<<"$rs" >/dev/null; then
      echo "  created ruleset: $name"
    else
      echo "  FAILED to create ruleset: $name" >&2; failed=1
    fi
  done

  if [[ -n "$tpl_classic" ]]; then
    body=$(classic_to_put <<<"$tpl_classic")
    if gh api "repos/$ORG/$repo/branches/$branch/protection" --method PUT --input - <<<"$body" >/dev/null; then
      echo "  set classic branch protection"
    else
      echo "  FAILED to set classic branch protection" >&2; failed=1
    fi
    if [[ "$(jq -r '.required_signatures.enabled // false' <<<"$tpl_classic")" == "true" ]]; then
      gh api "repos/$ORG/$repo/branches/$branch/protection/required_signatures" --method POST >/dev/null \
        && echo "  enabled required signatures" \
        || { echo "  FAILED to enable required signatures" >&2; failed=1; }
    fi
  fi
done

exit $failed
