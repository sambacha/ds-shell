#!/bin/sh

# Regular expression matching at least one whitespace.
SPACE_RE='[[:space:]][[:space:]]*'

# Regular expression matching optional whitespace.
OPTIONAL_SPACE_RE='[[:space:]]*'

# The inverse of the above, must match at least one character
NOT_SPACE_RE='[^[:space:]][^[:space:]]*'

# Regular expression matching shell function or variable name.  Functions may
# use nearly every character.  See [issue #8].  Disallowed characters (hex,
# octal, then a description or a character):
#
#   00 000 null       01 001 SOH        09 011 Tab        0a 012 Newline
#   20 040 Space      22 042 Quote      23 043 #          24 044 $
#   26 046 &          27 047 Apostrophe 28 050 (          29 051 )
#   2d 055 Hyphen     3b 073 ;          3c 074 <          3d 075 =
#   3e 076 >          5b 133 [          5c 134 Backslash  60 140 Backtick
#   7c 174 |          7f 177 Delete
#
# Exceptions allowed as leading character:  \x3d and \x5b
# Exceptions allowed as secondary character: \x23 and \x2d
#
# Must translate to raw characters because Mac OS X's sed does not work with
# escape sequences.  All escapes are handled by printf.
#
# Must use a hyphen first because otherwise it is an invalid range expression.
#
# [issue #8]: https://github.com/tests-always-included/tomdoc.sh/issues/8
FUNC_NAME_RE=$(printf "[^-\\001\\011 \"#$&'();<>\\134\\140|\\177][^\\001\\011 \"$&'();<=>[\\134\\140|\\177]*")
