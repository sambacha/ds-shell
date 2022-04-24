#!/usr/bin/env bash
set -eo pipefail
shopt -s lastpipe

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dsforge"
export GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME
unset HOME

DSFORGE_VERSION="${DSFORGE_VERSION:-unknown}"

usage() {
  echo >&2 "
Usage: dsforge COMMAND [ARGS]
Commands
  init                      Create a .dapp.json
  migrate                   Populate .dapp.json from submodules
  add <URL> [REF]           Add a dependency from URL pointing to a Git repo
  remove | rm <NAME>        Remove a dependency
  update | up [NAME [REF]]  Update a dependency to REF
  list | ls                 List dependencies
  duplicates | dup          List duplicate dependencies
  clone [PATH]              Clone dependencies into a directory
  clone-recursive [PATH]    Clone dependencies into a directory and fetch their submodules
  help                      Print this message
Version $DSFORGE_VERSION
"
}

export getSpec='rev=$(git rev-parse HEAD); \
fullref=$(git for-each-ref --contains $rev | sed -n "s/^.*refs\/\(heads\|remotes\/\)//p" | sort -k1.1,1.1 -rs | head -n1); \
remote=${fullref%/*}; remote=${remote:-origin};
ref=${fullref#*/}; \
url=$(git remote get-url $remote | sed "s/\(\.git\|\/\)$//"); \
alias=${url##*/}; con=${alias}_${rev::7}; '

submods() {
  git submodule --quiet foreach --recursive \
    "$getSpec"'printf %s\\n "$PWD $con"' \
    | sort -k2 -u
}
export -f submods

subdeps() {
  git submodule --quiet foreach "$getSpec"'printf %s "
        \"$alias\": \"$con\","'
}
export -f subdeps

spec() {
  (cd "$1"
    eval "$getSpec"
    deps=$(subdeps)
    name=$alias-${rev::7}
    printf %s "
    \"$con\": {
      \"name\": \"$alias\",
      \"deps\": {${deps%,}
      },
      \"repo\": {
        \"name\": \"$name\",
        \"url\": \"$url\",
        \"rev\": \"$rev\",
        \"ref\": \"${ref#refs/remotes/*/}\"
      }
    }"
  )
}
export -f spec

specs() {
  eval "$getSpec"

  local repos; repos="$1
$PWD $con"
  local root; root=$(realpath .)
  local deps;
  local sep; sep=""

  printf %s "{
  \"contracts\": {"

  echo >&2 "$repos"
  for path in $(cut -d " " -f1 <<<"$repos"); do

    if [[ $path != "$root" ]]; then
      printf %s "$sep"; sep=","
      if [[ -f "$path/.dapp.json" ]]; then
        jq .contracts "$path/.dapp.json" | sed '1d;$d'
      else
        spec "$path"
      fi
    fi
  done

  printf %s "
  },
  \"this\": {
$(spec "$path" | sed '1,2d;$d')
  }
}"
}
export -f specs

main() {
  local repos; repos=$(submods)

  [ -n "$repos" ] || { echo >&2 'Submodules not initiated? Run: `git submodule update --init --recursive`'; exit 1; }

  specs "$repos"
}
export -f main

clone() {
  [[ -d "$3/.git" ]] || git clone "$1" "$3" >&2
  (cd "$3" || exit 3
    git fetch >&2 || exit 3
    git checkout "${2:-HEAD}" >&2 || exit 3
    git pull >&2 || true
  ) || exit $?
}

tmpclone() {
  local target; target="$CACHE_DIR/${1##*/}"
  [[ -d "$target" && "$1" == "$(git -C "$target" remote get-url origin)" ]] \
    || rm -rf "$target"
  clone "$1" "${2:-HEAD}" "$target" >&2
  (cd "$target" || exit 3
    if [[ -f "./dapp.json" ]]; then
      local repo; repo=$(jq -c .repo <<<"$(spec "$target" | sed '1s/^.*://')")
      jq ".this.repo = $repo" ./dapp.json
    else
      git submodule deinit --all -f >/dev/null >&2 || exit 3
      git submodule update --init --recursive >&2 || exit 3
      main "$target"
    fi
  ) || exit $?
}

clean_deps() {
  jq '
      .contracts as $cs
    | def fu:
        flatten | unique
      ;
      def w($dep):
        [$dep] + [
          $cs[$dep].deps[]
        | values
        | reduce . as $x ([]; . + w($x))
        ] | fu
      ;
    .contracts = (
        [ .this.deps[] | values | w(.) ]
      | fu as $deps
      | $cs
      | to_entries
      | [
          .[]
        | select(
            .key as $key
          | $deps
          | contains([$key])
        )
      ]
      | from_entries
    )
  ' <<<"$1"
}

add_dep() {
  local jsonIn="$1"
  local ref=${3:-HEAD}
  local specs=$(tmpclone "$2" "$ref") || exit $?
  local contracts=$(jq .contracts <<<"$specs")
  local this=$(jq .this <<<"$specs")
  local addname=$(jq -r '.name' <<<"$this")
  local addrev=$(jq -r '.repo.rev' <<<"$this")
  local addcon="${addname}_${addrev::7}"

  [[ $(jq ".this.deps.\"$addname\"" <<<"$jsonIn") == null ]] || {
    echo >&2 "Dependency $addname already exists, not adding. Use \`dsforge update $addname $ref\` instead."
    exit 1
  }

  merge_json <<<"
    $jsonIn
    {\"contracts\": $contracts}
    {\"contracts\": {\"$addcon\":$this}, \"this\": {\"deps\": {\"$addname\":\"$addcon\"}}}
  "
}
init() {
  cat \
    <(echo "# [auto]: gen by dsforge $DSFORGE_VERSION") \
    "${DSFORGE_EXPR:-${BASH_SOURCE[0]%/*}/dapp2.nix}" \
    > "$1/dapp2.nix"
  printf %s "
{
  \"contracts\": {},
  \"this\": {
    \"name\": \"${1##*/}\",
    \"deps\": {}
  }
}"
}

remove_dep() {
  clean_deps "$(jq "del(.this.deps.\"$2\")" <<<"$1")"
}

update_dep() {
  local con=$(jq ".this.deps.\"$2\"" <<<"$1")

  [[ $con != null ]] || {
    echo >&2 "Dependency $2 not added. Use \`dsforge add\` first"
    exit 1
  }

  local dep=$(jq ".contracts.$con" <<<"$1")
  local rev=$(jq -r ".repo.rev" <<<"$dep")

  [[ "$rev" != "$3" ]] || {
    echo >&2 "Dependency $2 already at revision $rev"
    return
  }

  local ref=${3:-$(jq -r ".repo.ref" <<<"$dep")}
  local url=$(jq -r ".repo.url" <<<"$dep")
  local jsonOut
  jsonOut=$(remove_dep "$1" "$2")
  add_dep "$jsonOut" "$url" "$ref"
}

update_deps() {
  {
    list_deps "$1" | cut -d " " -f1 | while read -r dep; do
      update_dep "$1" "$dep"
    done
  } | merge_json
}

list_deps() {
  jq -r '
    .contracts as $cs
    | .this.deps | to_entries | .[]
    | ($cs[.value] as $c
      | "\($c.name) \($c.repo.url) \($c.repo.ref) \($c.repo.rev)"
      )
  ' <<<"$1"
}

clone_deps() {
  local target
  list_deps "$1" | cut -d " " -f1,2,4 | while read -r dep url rev; do
    target="${2:-.}/$dep"
    clone "$url" "$rev" "$target"
    if [[ "$3" == "--recursive" ]]; then
      (cd "$target" || exit 3
        git submodule update --init --recursive >&2 || exit 3
      ) || exit $?
    fi
  done
}

merge_json() {
  jq -s 'reduce .[] as $x ({}; . * $x)'
}

save() {
  local jsonOut
  jsonOut=$(clean_deps "$1")
  jsonOut=$(jq -S '
      .version = ($ENV.DSFORGE_FORMAT_VERSION | tonumber)
    | del(.this.repo)
  ' <<<"$jsonOut")
  if [[ -n "$jsonOut" ]]; then
    echo "$jsonOut" > "$2"
  else
    exit 5
  fi
}

outPath="$PWD/.dapp.json"
outDir="$PWD"

[[ -f "$outPath" || $1 == init || $1 == migrate ]] || {
  echo >&2 "Couldn't read .dapp.json, please run: \`dsforge init\` or \`dsforge migrate\` first"
  usage
  exit 1
}

case "${1:-help}" in
  init)
    [[ ! -e "$outPath" ]] || {
      echo >&2 ".dapp.json already exists, will not init"
      exit 1
    }
    save "$(init "$outDir")" "$outPath"
    ;;
  migrate)
    [[ ! -e "$outPath" ]] || {
      echo >&2 ".dapp.json already exists, will not migrate"
      exit 1
    }
    init "$outDir" >/dev/null
    save "$(main)" "$outPath"
    ;;
  add)
    jsonOut=$(add_dep "$(cat "$outPath")" "$2" "$3") || exit $?
    save "$jsonOut" "$outPath"
    ;;
  remove|rm)
    jsonOut=$(remove_dep "$(cat "$outPath")" "$2") || exit $?
    save "$jsonOut" "$outPath"
    ;;
  list|ls)
    list_deps "$(cat "$outPath")" | column -t -s" "
    ;;
  duplicates|dup)
    jq -r '.contracts[] | values | "\(.repo.rev) \(.name)"' "$outPath" \
      | sort -k2 | uniq -f1 -D | column -t -s" "
    ;;
  update|up)
    if [[ -n $2 ]]; then
      jsonOut=$(update_dep "$(cat "$outPath")" "$2" "$3") || exit $?
    else
      jsonOut=$(update_deps "$(cat "$outPath")") || exit $?
    fi
    save "$jsonOut" "$outPath"
    ;;
  clone)
    clone_deps "$(cat "$outPath")" "${2:-lib}"
    ;;
  clone-recursive)
    clone_deps "$(cat "$outPath")" "${2:-lib}" --recursive
    ;;
  help)
    usage
    ;;
  *)
    echo >&2 "No command $1"
    usage
    exit 1
    ;;
esac