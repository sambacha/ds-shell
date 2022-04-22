#!/usr/bin/env bash
# -*- shell-script -*-
# Top-level program. This program may be initially invoked.
#

# @NOTE Stop script on exception.
set -e

# @NOTE Stop script if unbound variable found
# @DEV use` `${var:-}` if intentional)
set -u

# @NOTE By default `cmd1 | cmd2` returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail

# Use in the the functions: eval $invocation
invocation='say_verbose "Calling: ${yellow:-}${FUNCNAME[0]} ${green:-}$*${normal:-}"'

# standard output may be used as a return value in the functions
# we need a way to write text on the screen in the functions so that
# it won't interfere with the return value.
# Exposing stream 3 as a pipe to standard output of the script itself
exec 3>&1

# @function nocolors Setup some colors to use.
# @summary Supports shells where there are only 8 colors.

#! [check]: if `stdout` is a terminal
if [ -t 1 ] && command -v tput >/dev/null; then
  #! [check]: supports colors
  ncolors=$(tput colors || echo 0)
  if [ -n "$ncolors" ] && [ $ncolors -ge 8 ]; then
    bold="$(tput bold || echo)"
    normal="$(tput sgr0 || echo)"
    black="$(tput setaf 0 || echo)"
    red="$(tput setaf 1 || echo)"
    green="$(tput setaf 2 || echo)"
    yellow="$(tput setaf 3 || echo)"
    blue="$(tput setaf 4 || echo)"
    magenta="$(tput setaf 5 || echo)"
    cyan="$(tput setaf 6 || echo)"
    white="$(tput setaf 7 || echo)"
  fi
fi

# Creates an archive (*.tar.gz) from given directory.
function maketar() { tar cvzf "${1%%/}.tar.gz"  "${1%%/}/"; }

# Create a ZIP archive of a file or folder.
function makezip() { zip -r "${1%%/}.zip" "$1" ; }

# Make your directories and files access rights sane.
function sanitize() { chmod -R u=rwX,g=rX,o= "$@" ;}

# Local Variables:
# mode:shell-script
# sh-shell:bash
# End: