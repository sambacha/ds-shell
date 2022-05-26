#!/usr/bin/env bash

echo "assert testing harness"
echo "version 2022.05.25"

echo $BASH_VERSION
echo date +%T
sleep 1

setUp() {
	. '../libfoundryup'

	TMP_INSTALL_DIR=$(mktemp -d)
	pd=$TOOL_DIR # alias to reduce character count
}

tearDown() {
	rm -rf $pd
}

testUseProgramNameEmpty() {
	use_program
	assertEquals 2 $?
}

testUseProgramVersionEmpty() {
	use_program dshell
	assertEquals 3 $?
}

testUseProgramProgramsDirDoesntExist() {
	TOOL_DIR='/non/existent'
	local msg=$(
		use_program dshell 0.1.0 2>&1
		assertEquals 1 $?
	)
	assertEquals "Not installed: dshell 0.1.0" "$msg"
}

testUseProgramNotInstalled() {
	local msg=$(
		use_program dshell 0.1.0 2>&1
		assertEquals 1 $?
	)
	assertEquals "Not installed: dshell 0.1.0" "$msg"
}

testUseProgramNotInstalledInstalledOne() {
	mkdir $pd/dshell

	local msg=$(
		use_program dshell 0.1.0 2>&1
		assertEquals 1 $?
	)
	assertEquals "Not installed: dshell 0.1.0" "$msg"
}
