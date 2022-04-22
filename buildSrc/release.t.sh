#!/usr/bin/env bash
# shellcheck disable=SC2257

failed=0
fail() {
  echo "$(tput setaf 1)$*$(tput sgr0)"
  failed=1
}

if git diff | grep -q ""
then
  fail "[alert] There are uncommitted changes"
fi

current=$(git tag --points-at)
if [[ -z "$current" ]]
then
  fail "[alert] No git tag on the current commit"
  echo "Create one with:   git tag -a v0.0.0"
fi

if [[ "$current" != v* ]]
then
  fail "[err] Bad tag format: expected v0.0.0"
fi

if [[ "$(git cat-file -t "$current")" != "tag" ]]
then
  fail "[alert] Current tag is not annotated (required for mkdist)."
fi

if [[ "$(git tag --points-at master)" != "$current" ]]
then
  fail "[alert] You are not on master"
fi

version=${current#v}
if ! grep "Version:" dsshell | grep -qFw "$version"
then
  fail "[err] The file does not match tag version $version"
fi

if ! grep -qF "## $current" CHANGELOG.md
then
  fail "CHANGELOG.md does not contain '## $current'"
fi

if [[ $(git log -1 --pretty=%B) != "feat(release) "* ]]
then
  fail "Expected git log message to be 'feat(release) ...'"
fi

i=1 j=1
cat << EOF
Manual Checklist
$((i++)). Make sure the package builds.
Release Steps
$((j++)). \`git push --follow-tags\` to push commit
EOF
exit "$failed"