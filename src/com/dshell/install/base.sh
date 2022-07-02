#!/usr/bin/env bash

###############################################################################
#                                                                             #
#   Setup                                                                     #
#                                                                             #
###############################################################################

set -euo pipefail

# TODO - Check Bash Version (min 4.3)
echo $BASH_VERSION

readonly DSHELL_LAUNCHER_VERSION="1.1.1"  # warning: this line is auto-updated

readonly SUCCESS_MARK="\033[0;32m✔\033[0m"
readonly FAIL_MARK="\033[0;31m✘\033[0m"
readonly PROGRESS_MARKS=("⡿" "⢿" "⣻" "⣽" "⣾" "⣷" "⣯" "⣟")

# This is how mktemp(1) decides where to create stuff in tmpfs.
readonly TMPDIR="${TMPDIR:-/tmp}"

readonly CLI_DIR="${HOME}/.cache/dshell/cli"
mkdir -p "${CLI_DIR}"

KERNEL=$(uname | tr "[:upper:]" "[:lower:]")
readonly KERNEL

MACHINE=$(uname -m)
readonly MACHINE

PLATFORM="${KERNEL}-${MACHINE}"
readonly PLATFORM

PLATFORM_UNDERSCORE="${KERNEL}_${MACHINE}"
readonly PLATFORM_UNDERSCORE

# https://en.wikipedia.org/wiki/ANSI_escape_code#CSI_(Control_Sequence_Introducer)_sequences
# [nF is "cursor previous line" and moves to the beginning of the nth previous line
# [0K is "erase display" and clears from the cursor to the end of the screen
readonly CLEAR_LAST_MSG="\033[1F\033[0K"

# NOTE(sam): DSHELL_LAUNCHER_QUIET was originally DSHELL_QUIET;
readonly DSHELL_LAUNCHER_QUIET=${DSHELL_LAUNCHER_QUIET:-${DSHELL_QUIET:-false}}
readonly DSHELL_LAUNCHER_DEBUG

if [[ ${DSHELL_LAUNCHER_QUIET} != false ]]; then
  exec 3>&1 4>&2 &>/dev/null
fi

# platform check
readonly MINIMUM_MACOS_VERSION="10.15"
check_darwin_version() {
  local osx_version
  osx_version="$(sw_vers -productVersion)"

  # dshell-ignore-begin(shellcheck/SC2312): the == will fail if anything inside the $() fails
  if [[ "$(printf "%s\n%s\n" "${MINIMUM_MACOS_VERSION}" "${osx_version}" | \
           sort --version-sort | \
           head -n 1)" == "${MINIMUM_MACOS_VERSION}"* ]]; then
    return
  fi
  # dshell-ignore-end(shellcheck/SC2312)

  echo -e "${FAIL_MARK} DShell requires at least MacOS ${MINIMUM_MACOS_VERSION}" \
          "(yours is ${osx_version}). See https://docs.${DSHELL_FQDN} for more info."
  exit 1
}
if [[ ${PLATFORM} == "darwin-x86_64" || ${PLATFORM} == "darwin-arm64" ]]; then
  check_darwin_version
elif [[ ${PLATFORM} == "linux-x86_64" ]]; then
  :
else
  echo -e "${FAIL_MARK} DShell is only supported on Linux (x64_64) and MacOS (x86_64, arm64)." \
          "See https://docs.${DSHELL_FQDN} for more info."
  exit 1
fi

DSHELL_TMPDIR="${TMPDIR}/dshell-$(set -e; id -u)/launcher_logs"
readonly DSHELL_TMPDIR
mkdir -p "${DSHELL_TMPDIR}"

# For the `mv $TOOL_TMPDIR/dshell $TOOL_DIR` to be atomic (i.e. just inode renames),
# the source and destination filesystems need to be the same
TOOL_TMPDIR=$(mktemp -d "${CLI_DIR}/tmp.XXXXXXXXXX")
readonly TOOL_TMPDIR

cleanup() {
  rm -rf "${TOOL_TMPDIR}"
  if [[ "$1" == "0" ]]; then
    rm -rf "${DSHELL_TMPDIR}"
  fi
}
trap 'cleanup $?' EXIT

# e.g. 2022-02-16-20-40-31-0800
dt_str() { date +"%Y-%m-%d-%H-%M-%S%z"; }

LAUNCHER_TMPDIR="${TOOL_TMPDIR}/launcher"
readonly LAUNCHER_TMPDIR
mkdir -p "${LAUNCHER_TMPDIR}"

if [[ -n ${DSHELL_LAUNCHER_DEBUG:-} ]]; then
  set -x
fi

# launcher awk
#
# BEGIN{ORS="";}
#   use "" as the output record separator
#   ORS defaults to "\n" for bwk, which results in
#     $(printf "foo bar" | awk '{print $2}') == "bar\n"
#
# {gsub(/\r/, "", $0)}
#   for every input record (i.e. line), the regex "\r" should be replaced with ""
#   This is necessary to handle CRLF files in a portable fashion.
#
# Some StackOverflow answers suggest using RS="\r?\n" to handle CRLF files (RS is the record
# separator, i.e. the line delimiter); unfortunately, original-awk only allows single-character
# values for RS (see https://www.gnu.org/software/gawk/manual/gawk.html#awk-split-records).
lawk() {
  awk 'BEGIN{ORS="";}{gsub(/\r/, "", $0)}'"${1}" "${@:2}"
}
awk_test() {
  # dshell-ignore-begin(shellcheck/SC2310,shellcheck/SC2312)
  # SC2310 and SC2312 are about set -e not propagating to the $(); if that happens, the string
  # comparison will fail and we'll claim the user's awk doesn't work
  if [[ $(set -e; printf 'k1: v1\n \tk2: v2\r\n'   | lawk '/[ \t]+k2:/{print $2}') == 'v2' && \
        $(set -e; printf 'k1: v1\r\n\t k2: v2\r\n' | lawk '/[ \t]+k2:/{print $2}') == 'v2' ]]; then
    return
  fi
  # dshell-ignore-end(shellcheck/SC2310,shellcheck/SC2312)

  echo -e "${FAIL_MARK} DShell does not work with your awk;" \
          "please report this at https://slack.${DSHELL_FQDN}."
  echo -e "Your version of awk is:"
  awk --version || awk -Wversion
  exit 1
}
awk_test

readonly CURL_FLAGS="${CURL_FLAGS:- -vvv --max-time 120 --retry 3 --fail}"
readonly WGET_FLAGS="${WGET_FLAGS:- --verbose --tries=3 --limit-rate=10M}"
TMP_DOWNLOAD_LOG="${DSHELL_TMPDIR}/download-$(set -e; dt_str).log"
readonly TMP_DOWNLOAD_LOG

# Detect whether we should use wget or curl.
if command -v wget &>/dev/null; then
  download_cmd() {
    local url="${1}"
    local output_to="${2}"
    # dshell-ignore-begin(shellcheck/SC2312): we don't care if wget --version errors
    cat >>"${TMP_DOWNLOAD_LOG}" <<EOF
Using wget to download '${url}' to '${output_to}'

Is DShell up?: https://status.${DSHELL_FQDN}

WGET_FLAGS: ${WGET_FLAGS}

wget --version:
$(wget --version)

EOF
    # dshell-ignore-end(shellcheck/SC2312)

    # dshell-ignore(shellcheck/SC2086): we deliberately don't quote WGET_FLAGS
    wget ${WGET_FLAGS} "${url}" --output-document "${output_to}" 2>>"${TMP_DOWNLOAD_LOG}" &
  }
elif command -v curl &>/dev/null; then
  download_cmd() {
    local url="${1}"
    local output_to="${2}"
    # dshell-ignore-begin(shellcheck/SC2312): we don't care if curl --version errors
    cat >>"${TMP_DOWNLOAD_LOG}" <<EOF
Using curl to download '${url}' to '${output_to}'

Is DShell up?: https://status.${DSHELL_FQDN}

CURL_FLAGS: ${CURL_FLAGS}

curl --version:
$(curl --version)

EOF
    # dshell-ignore-end(shellcheck/SC2312)

    # dshell-ignore(shellcheck/SC2086): we deliberately don't quote CURL_FLAGS
    curl ${CURL_FLAGS} "${url}" --output "${output_to}" 2>>"${TMP_DOWNLOAD_LOG}" &
  }
else
  download_cmd() {
    echo -e "${FAIL_MARK} Cannot download '${url}'; please install curl or wget."
    exit 1
  }
fi

download_url() {
  local url="${1}"
  local output_to="${2}"
  local progress_message="${3:-}"

  if [[ -n ${progress_message} ]]; then
    echo -e "${PROGRESS_MARKS[0]} ${progress_message}..."
  fi

  download_cmd "${url}" "${output_to}"
  local download_pid="$!"

  local i_prog=0
  while [[ -d "/proc/${download_pid}" && -n ${progress_message} ]]; do
    echo -e "${CLEAR_LAST_MSG}${PROGRESS_MARKS[${i_prog}]} ${progress_message}..."
    sleep 0.2
    i_prog=$(( (i_prog + 1) % ${#PROGRESS_MARKS[@]} ))
  done

  local download_log
  if ! wait "${download_pid}"; then
    download_log="${DSHELL_TMPDIR}/launcher-download-$(set -e; dt_str).log"
    mv "${TMP_DOWNLOAD_LOG}" "${download_log}"
    echo -e "${CLEAR_LAST_MSG}${FAIL_MARK} ${progress_message}... FAILED (see ${download_log})"
    echo -e "Please check your connection and try again." \
            "If you continue to see this error message," \
            "consider reporting it to us at https://forums.${DSHELL_FQDN}."
    exit 1
  fi

  if [[ -n ${progress_message} ]]; then
   echo -e "${CLEAR_LAST_MSG}${SUCCESS_MARK} ${progress_message}... done"
  fi

}

# sha256sum is in coreutils, so we prefer that over shasum, which is installed with perl
if command -v sha256sum &>/dev/null; then
  :
elif command -v shasum &>/dev/null; then
  sha256sum() { shasum -a 256 "$@"; }
else
  sha256sum() {
    echo -e "${FAIL_MARK} Cannot compute sha256; please install sha256sum or shasum"
    exit 1
  }
fi

###############################################################################
#                                                                             #
#   CLI resolution functions                                                  #
#                                                                             #
###############################################################################

dshell_yaml_abspath() {
  local repo_head
  local cwd

  if repo_head=$(git rev-parse --show-toplevel 2>/dev/null); then
    echo "${repo_head}/.dshell/dshell.yaml"
  elif [[ -f .dshell/dshell.yaml ]]; then
    cwd="$(pwd)"
    echo "${cwd}/.dshell/dshell.yaml"
  else
    echo ""
  fi
}

read_cli_version_from() {
  local config_abspath="${1}"
  local cli_version

  cli_version="$(set -e; lawk '/[ \t]+version:/{print $2; exit;}' "${config_abspath}")"
  if [[ -z ${cli_version} ]]; then
    echo -e "${FAIL_MARK} Invalid .dshell/dshell.yaml, no cli version found." \
            "See https://docs.${DSHELL_FQDN} for more info."
    exit 1
  fi

  echo "${cli_version}"
}

download_cli() {
  local dl_version="${1}"
  local expected_sha256="${2}"
  local actual_sha256

  readonly TMP_INSTALL_DIR="${LAUNCHER_TMPDIR}/install"
  mkdir -p "${TMP_INSTALL_DIR}"

  DSHELL_NEW_URL_VERSION=0.10.2-beta.1
  if [[ "$(printf "%s\n%s\n" "${DSHELL_NEW_URL_VERSION}" "${dl_version}" | \
           sort --version-sort | \
           head -n 1)" == "${DSHELL_NEW_URL_VERSION}"* ]]; then
    readonly URL="https://${DSHELL_FQDN}/releases/${dl_version}/dshell-${dl_version}-${PLATFORM}.tar.gz"
    else
    readonly URL="https://${DSHELL_FQDN}/releases/dshell-${dl_version}.${KERNEL}.tar.gz"
  fi

  readonly DOWNLOAD_TAR_GZ="${TMP_INSTALL_DIR}/download-${dl_version}.tar.gz"

  download_url "${URL}" "${DOWNLOAD_TAR_GZ}" "Downloading DShell ${dl_version}"

  if [[ -n ${expected_sha256:-} ]]; then
    local verifying_text="Verifying DShell sha256..."
    echo -e "${PROGRESS_MARKS[0]} ${verifying_text}"

    actual_sha256="$(set -e; sha256sum "${DOWNLOAD_TAR_GZ}" | lawk '{print $1}')"

    if [[ ${actual_sha256} != "${expected_sha256}" ]]; then
      echo -e "${CLEAR_LAST_MSG}${FAIL_MARK} ${verifying_text} FAILED"
      echo "Expected sha256: ${expected_sha256}"
      echo "  Actual sha256: ${actual_sha256}"
      exit 1
    fi

    echo -e "${CLEAR_LAST_MSG}${SUCCESS_MARK} ${verifying_text} done"
  fi

  local unpacking_text="Unpacking DShell..."
  echo -e "${PROGRESS_MARKS[0]} ${unpacking_text}"
  tar --strip-components=1 -C "${TMP_INSTALL_DIR}" -xf "${DOWNLOAD_TAR_GZ}"
  echo -e "${CLEAR_LAST_MSG}${SUCCESS_MARK} ${unpacking_text} done"

  rm -f "${DOWNLOAD_TAR_GZ}"
  mkdir -p "${TOOL_DIR}"

  mv -n "${TMP_INSTALL_DIR}/dshell" "${TOOL_DIR}/"
  rm -rf "${TMP_INSTALL_DIR}"
}

###############################################################################
#                                                                             #
#   CLI resolution                                                            #
#                                                                             #
###############################################################################

CONFIG_ABSPATH="$(set -e; dshell_yaml_abspath)"
readonly CONFIG_ABSPATH

version="${DSHELL_CLI_VERSION:-}"
if [[ -n ${version:-} ]]; then
  :
elif [[ -f ${CONFIG_ABSPATH} ]]; then
  version="$(set -e; read_cli_version_from "${CONFIG_ABSPATH}")"
  version_sha256="$(set -e; lawk "/${PLATFORM_UNDERSCORE}:/"'{print $2}' "${CONFIG_ABSPATH}")"
else
  readonly LATEST_FILE="${LAUNCHER_TMPDIR}/latest"
  download_url "https://${DSHELL_FQDN}/releases/latest" "${LATEST_FILE}"
  version=$(set -e; lawk '/version:/{print $2}' "${LATEST_FILE}")
  version_sha256=$(set -e; lawk "/${PLATFORM_UNDERSCORE}:/"'{print $2}' "${LATEST_FILE}")
fi

readonly OLD_TOOL_DIR="${CLI_DIR}/${version}"
readonly TOOL_PART="${version}-${PLATFORM}"
readonly TOOL_DIR="${CLI_DIR}/${TOOL_PART}"

if [[ ! -x "${TOOL_DIR}/dshell" ]]; then
  rm -rf "${TOOL_DIR}"

  if [[ -n ${LATEST_FILE:-} ]]; then
    read -rp "Would you like to download and run the latest version of dshell? (Y/n) " yn
    case "${yn}" in
    Yes | yes | Y | y | "") ;;
    *) exit 1 ;;
    esac
  fi

  download_cli "${version}" "${version_sha256:-}"

  # It looks better to have whitespace between the launcher download steps and the CLI invocation:
  #
  #   $ dshell check
  #   ✔ Downloading DShell 0.7.0-beta... done
  #   ✔ Verifying DShell sha256... done
  #   ✔ Unpacking DShell... done
  #
  #   Checking 100% [=============================================>]  30/30  1.4s
  #
  # so we insert an echo here
  echo
fi

# Create a backwards compatability link for old versions of dshell that want to write their
# crashpad_handlers to that dir.
if [[ ! -L ${OLD_TOOL_DIR} ]]; then
  rm -rf "${OLD_TOOL_DIR}"
  ln -s "${TOOL_PART}" "${OLD_TOOL_DIR}"
fi

# blow away and download TOOL if the binary doesn't exist

if [[ -n ${LATEST_FILE:-} ]]; then
  # If we downloaded the latest dshell version, i.e. because there was no dshell.yaml
  mv -n "${LATEST_FILE}" "${TOOL_DIR}/version"
fi

if [[ ${DSHELL_LAUNCHER_QUIET} != false ]]; then
  exec 1>&3 3>&- 2>&4 4>&-
fi

###############################################################################
#                                                                             #
#   CLI invocation                                                            #
#                                                                             #
###############################################################################

# NOTE: exec will overwrite the process image, so trap will not catch the exit signal.
# Therefore, run cleanup manually here.
cleanup 0

exec \
  env DSHELL_LAUNCHER_VERSION="${DSHELL_LAUNCHER_VERSION}" \
  env DSHELL_LAUNCHER_PATH="${BASH_SOURCE[0]}" \
  "${TOOL_DIR}/dshell" "$@"
