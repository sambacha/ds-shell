#!/usr/bin/env bash

set -euo pipefail

check_mark="\033[1;32m✔\033[0m"
header() { echo -e "\n\033[1m$1\033[0m"; }

# TODO - Boilerplate message
header "Loading DShell\n"
echo " This will download and install the latest DShell Launcher. When you run 'dshell'"
echo " you'll really be running the DShell Launcher, which figures out which version of"
echo " DShell to run based on your current environment."
echo " If you want to run DShell directly, you can do so by running 'dshell --version'"

header "\nThis script will install\n"
echo -e " \033[4m/usr/local/bin/dshell\033[0m\n\n"

if [[ $* != "-y" ]]; then
  # Explicitly use /dev/tty instead of relying on stdin pointing at /dev/tty, so that
  # `curl $GET_SCRIPT | bash` works
  printf >/dev/tty '%s' "${*:-Press any key to continue... }"
  read </dev/tty -rsn1
fi

header "\n\nDownloading and Installing\n"

echo "  Downloading DShell Launcher..."
tmp_file=$(mktemp)
curl -fsSL https://${DSHELL_FQDN}/releases/dshell -o "${tmp_file}"
echo -e "\033[1A ${check_mark} Downloading DShell Launcher... done"

echo "   Installing DShell Launcher (requires sudo access)..."
chmod +x "${tmp_file}"
$(command -v sudo || true) bash -c "mkdir -p /usr/local/bin && mv ${tmp_file} /usr/local/bin/dshell"
echo -e " ${check_mark} Installing DShell Launcher... done\n"

header "Next Steps\n"
echo -e " 1. \033[1mInitialize dshell in a repo\033[0m"
echo -e "    \033[0;90mRun \033[0;36mdshell init\033[0;90m to setup dshell in a git repo\033[0m\n"
echo -e " 2. \033[1mRead documentation\033[0m"
echo -e "    \033[0;90mOur documentation can be found at \033[0;4mhttps://docs.${DSHELL_FQDN}\033[0m\n"
echo -e " 3. \033[1mGet help and give feedback\033[0m"
echo -e "    \033[0;90mJoin the dshell community at \033[0;4mhttps://forums.${DSHELL_FQDN}\033[0m"
