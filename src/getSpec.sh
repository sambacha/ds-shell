rev=$(git rev-parse HEAD)
fullref=$(git for-each-ref --contains $rev | sed -n "s/^.*refs\/\(heads\|remotes\/\)//p" | sort -k1.1,1.1 -rs | head -n1)
remote=${fullref%/*}
remote=${remote:-origin}
ref=${fullref#*/}
url=$(git remote get-url $remote | sed "s/\(\.git\|\/\)$//")
alias=${url##*/}
con=${alias}_${rev::7}
