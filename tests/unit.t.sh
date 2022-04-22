#!/usr/bin/env bash
# -*- tab-width: 4; encoding: utf-8 -*-
#
#
#

PS4='+ ${FUNCNAME:-main}${LINENO:+:$LINENO}>'

# If it works with failglob and nounset, it will work without.
shopt -s failglob
set -o nounset

. ./ds-shell.sh

shopt -s extdebug
errors=0
disabled=0

rm -f unittest.log unittest.env.log

err_trap() {
  : $((errors += 1))
  return 1
}

trap err_trap ERR

print_exit_status() {
  # Prints [OK] at the end of the screen of first argument is 0,
  # else [FAILURE].
  # 1st Parameter: a number, usually the exit status of your
  # previous command. If omitted, will use $?.
  # returns the first parameter value
  local ret="${1:-$?}"
  # If you want you can override the FAILED and OK messages by
  # pre-defining those variables.
  local FAILED=${FAILED:-FAILED}
  local OK=${OK:-OK}
  # Move to column default is 70
  local COL=${COL:=70}
  [[ -t 1 ]] && echo -en "\033[${COL}G"
  # Colors
  if [[ -t 1 ]]; then
    local COLOR_SUCCESS=${COLOR_SUCCESS:-'\033[1;32m'}
    local COLOR_FAILURE=${COLOR_FAILURE:-'\033[1;31m'}
    local COLOR_WARNING='\033[1;33m' COLOR_NORMAL='\033[0;39m'
  else
    local COLOR_SUCCESS= COLOR_FAILURE= COLOR_WARNING= COLOR_NORMAL=
  fi
  [[ "$ret" -eq 0 ]] && echo -e "[$COLOR_SUCCESS$OK$COLOR_NORMAL]" ||
    echo -e "[$COLOR_FAILURE$FAILED$COLOR_NORMAL]"
  return $ret
}

echo_for_print_status() {
  local m=$1
  if tty >/dev/null 2>&1 && [[ -n "${PRINT_STATUS_COLOR:-}" ]]; then
    m="$(tput setaf $PRINT_STATUS_COLOR)$m$(tput sgr0)"
  fi
  printf "%s: " "$m"
}

exec_and_print_status() {
  # prints a message, execute a command and print its exit status
  # using print_exit_status function.
  # 1st Parameter: a message
  # all other parameter: the command to execute
  # returns the exit status code of the command
  [[ $# -lt 2 ]] && return 1
  local m=$1
  shift
  PRINT_STATUS_COLOR="${PRINT_STATUS_COLOR-}" \
    echo_for_print_status "$m"
  "$@"
  print_exit_status $?
}

default_test() {
  [[ $? -eq 0 ]]
}

failure() {
  [[ $? -ne 0 ]]
}

shell_env() {
  # Greps are:
  # * variables automatically altered by bash itself.
  # * local environment variables, used by the environment checking routines.
  # * ds-shell private variables, subjects to modifications/deletion.
  # * ds-shell public variables.
  # * ds-shell results, which are expected to change.
  set |
    grep -vE '^(FIRST|SECOND|SHELLOPTS|FUNCNAME|_|LINENO|BASH_(ARG[CV]|LINENO|SOURCE|REMATCH)|PIPESTATUS)=' |
    grep -vE '^before=' |
    grep -vE '^__ds-shell_(options_descriptions|short_options|tmp_identifiers)=' |
    grep -vE '^ds-shell_usage_description=' |
    grep -vE '^(program_(params|options))|cumulated_values_[0-9a-zA-Z_]+='
  shopt
  set -o | grep -v xtrace
}

check_env() {
  {
    printf "For test: %s\n" "$message"
    diff -u <(echo "$before") <(shell_env)
  } >>unittest.env.log
}

parse_option_wrapper() {
  local message=$1
  local TEST=${TEST:-default_test}
  shift
  local before=$(shell_env)
  echo_for_print_status "Checking $message"
  (
    printf "Test is: %s\n" "$message"
    printf "Validation is: %s\n" "$TEST"
    set -x
    (
      trap check_env EXIT
      ds-shell_parse_options "$@"
      ${INNERTEST:-exit $?}
    )
  ) >>unittest.log 2>&1
  $TEST
  print_exit_status || exit
}

value_check_test() {
  [[ ${program_options[$value_check_option]} = $value_check_value ]]
}

value_check() {
  local value_check_option=$1
  local value_check_value=$2
  shift 2
  INNERTEST=value_check_test parse_option_wrapper "$@"
}

printf "Tests report:\n"
if [[ $disabled -ne 0 ]]; then
  printf "* %d test(s) disabled.\n" "$disabled"
fi

if [[ $errors -ne 0 ]]; then
  printf "* %d error(s) encountered. (See above)\n" "$errors"
  exit_code=1
else
  printf "All tests passed.\n"
  exit_code=0
fi

printf "Environment alteration detected:\n"
if grep -v -B 1 '^For test:' unittest.env.log; then
  : exit_code $((exit_code))
else
  printf "None.\n"
fi

if [[ $exit_code -ne 0 ]]; then
  printf "Runtime environment was:\n"
  set -x
  {
    command -v bash
    bash --version
    shopt
    set -o
  } 2>&1
fi

printf "Completed in %d seconds.\n" "$SECONDS"

exit "$exit_code"
