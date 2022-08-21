#!/bin/awk
# -*- indent-tabs-mode: nil; c-basic-offset: 2 -*-
# rnc2rng.awk - Convert RELAX NG Compact Syntax to XML Syntax
# Copyright (C) 2007 Shaun McCance <shaunm@gnome.org>
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

# This program is free software, but that doesn't mean you should use it.
# I wanted to write and maintain the Mallard schema in RNC in code blocks
# within the specification, but I needed to distribute the schema in RNG.
# Since xmllint (libxml2) does not currently support RNC, and since I'm
# not willing to introduce more dependencies, awk was my only option.
#
# This awk script is *NOT* a complete implementation, and probably never
# will be.  Its sole purpose is to handle the Mallard schema, and it is
# sufficient for that task.
#
# You are, of course, free to use any of this.  If you do proliferate this
# hack, it is requested (though not required, that would be non-free) that
# you atone for your actions.  A good atonement would be contributing to
# free software.

function parse_define (line) {
  nameix = index(line, "=");
  combine = "";
  if (nameix < 1) next;
  if (substr(line, nameix - 1, 1) == "|") {
    combine = "choice";
    name = substr(line, 1, nameix - 2);
  }
  else if (substr(line, nameix - 1, 1) == "&") {
    combine = "interleave";
    name = substr(line, 1, nameix - 2);
  }
  else {
    name = substr(line, 1, nameix - 1);
  }
  sub(/^ */, "", name);
  sub(/ *$/, "", name);
  if (name == "")
    name = maybe_define;
  if (name == "start")
    define = "<start"
  else
    define = sprintf("<define name='%s'", name);
  if (combine != "")
    define = define " combine='" combine "'"
  define = define ">"
  stack[++stack_i] = define;
  mode = "pattern";
  maybe_define = "";
  if (length(line) >= nameix + 1)
    parse_pattern(substr(line, nameix + 1))
}
function parse_pattern (line) {
  sub(/^ */, "", line)
  if (length(line) == 0) return;
  c = substr(line, 1, 1);
  if (c == "(" || c == "{") {
    stack[++stack_i] = substr(line, 1, 1);
    paren[++paren_i] = stack_i;
    if (length(line) >= 2)
      parse_pattern(substr(line, 2));
  }
  else if (c == ")" || c == "}") {
    open = stack[paren[paren_i]];
    oc = substr(open, 1, 1) c;
    if (oc != "()" && oc != "{}") {
      print "Mismatched parentheses on line " FNR | "cat 1>&2";
      error = 1;
      exit 1
    }

    tag = "";
    if (length(open) > 1 && substr(open, 2, 1) == "&") {
      tag = "interleave";
    }
    else if (length(open) > 1 && substr(open, 2, 1) == "|") {
      tag = "choice";
    }
    else if (oc == "()") {
      tag = "group";
    }

    tmp = "";
    if (tag != "") {
      tmp = "<" tag ">";
    }
    for (i = paren[paren_i] + 1; i <= stack_i; i++) {
      tmp = tmp stack[i] "\n";
    }
    if (tag != "") {
      tmp = tmp "</" tag ">";
    }
    stack_i = paren[paren_i];
    stack[stack_i] = tmp;
    paren_i--;

    if (oc == "{}") {
      if (match(stack[stack_i - 1], "^<element")) {
        tmp = stack[stack_i - 1] "\n";
        if (stack[stack_i] != "") {
          tmp = tmp stack[stack_i] "\n";
        } else {
          tmp = tmp "<empty/>\n";
        }
        tmp = tmp "</element>";
        stack[--stack_i] = tmp;
      }
      else if (match(stack[stack_i - 1], "^<attribute")) {
        tmp = stack[stack_i - 1] "\n";
        if (stack[stack_i] != "") {
          tmp = tmp stack[stack_i] "\n";
        } else {
          tmp = tmp "<empty/>\n";
        }
        tmp = tmp "</attribute>";
        stack[--stack_i] = tmp;
      }
      else if (stack[stack_i - 1] == "<list>") {
        tmp = stack[stack_i - 1] "\n";
        tmp = tmp stack[stack_i] "\n";
        tmp = tmp "</list>";
        stack[--stack_i] = tmp;
      }
      else if (stack[stack_i - 1] == "<mixed>") {
        tmp = stack[stack_i - 1] "\n";
        tmp = tmp stack[stack_i] "\n";
        tmp = tmp "</mixed>";
        stack[--stack_i] = tmp;
      }
    }
    if (paren_i == 0) {
      mode = "grammar";
    }
    if (length(line) >= 2)
      parse_pattern(substr(line, 2));
  }
  else if (c == "|" || c == "&" || c == ",") {
    if (length(stack[paren[paren_i]]) == 1) {
      stack[paren[paren_i]] = stack[paren[paren_i]] c;
    }
    else if (length(stack[paren[paren_i]]) < 2 || substr(stack[paren[paren_i]], 2) != c) {
      if (paren_i == 0) {
        tmp = stack[stack_i];
        stack[stack_i] = c c;
        paren[++paren_i] = stack_i;
        stack[++stack_i] = tmp;
      }
      else {
        print "Mismatched infix operators on line " FNR | "cat 1>&2";
        error = 1;
        exit 1
      }
    }
    postop = 1;
    if (length(line) >= 2)
      parse_pattern(substr(line, 2));
  }
  else if (c == "?") {
    stack[stack_i] = "<optional>" stack[stack_i] "</optional>"
    if (length(line) >= 2)
      parse_pattern(substr(line, 2));
  }
  else if (c == "*") {
    stack[stack_i] = "<zeroOrMore>" stack[stack_i] "</zeroOrMore>"
    if (length(line) >= 2)
      parse_pattern(substr(line, 2));
  }
  else if (c == "+") {
    stack[stack_i] = "<oneOrMore>" stack[stack_i] "</oneOrMore>"
    if (length(line) >= 2)
      parse_pattern(substr(line, 2));
  }
  else if (c == "\"") {
    txt = substr(line, 2);
    sub(/".*/, "", txt)
    stack[++stack_i] = "<value>" txt "</value>";
    postop = 0;
    if (length(line) >= length(txt) + 3)
      parse_pattern(substr(line, length(txt) + 3));
  }
  else if (match(line, "^element ")) {
    aft = substr(line, 8);
    sub(/^ */, "", aft);
    name = aft;
    stack[++stack_i] = "<element";
    mode = "name_class";
    name_class_i = stack_i;
    postop = 0;
    parse_name_class(name);
  }
  else if (match(line, "^attribute ")) {
    aft = substr(line, 10);
    sub(/^ */, "", aft);
    name = aft;
    stack[++stack_i] = "<attribute";
    mode = "name_class";
    name_class_i = stack_i;
    postop = 0;
    parse_name_class(name);
  }
  else if (match(line, "^list ")) {
    aft = substr(line, 5);
    sub(/^ */, "", aft);
    stack[++stack_i] = "<list>";
    if (aft != "") { parse_pattern(aft); }
  }
  else if (match(line, "^mixed ")) {
    aft = substr(line, 6);
    sub(/^ */, "", aft);
    stack[++stack_i] = "<mixed>";
    if (aft != "") { parse_pattern(aft); }
  }
  else if (match(line, /^text[^A-Za-z]/) || match(line, /^text$/)) {
    stack[++stack_i] = "<text/>";
    aft = substr(line, 5);
    sub(/^ */, "", aft);
    postop = 0;
    if (aft != "") { parse_pattern(aft); }
  }
  else if (match(line, "^default namespace ")) {
    print "default namespace appeared out of context on line " FNR | "cat 1>&2";
    error = 1;
    exit 1
  }
  else if (match(line, "^namespace ")) {
    print "namespace appeared out of context on line " FNR | "cat 1>&2";
    error = 1;
    exit 1
  }
  else if (match(line, "^start ")) {
    print "start appeared out of context on line " FNR | "cat 1>&2";
    error = 1;
    exit 1
  }
  else if (match(line, "^include ")) {
    print "include appeared out of context on line " FNR | "cat 1>&2";
    error = 1;
    exit 1
  }
  else if (match(line, /^xsd:[A-Za-z_.-]/)) {
    name = substr(line, 1);
    sub(/^xsd:/, "", name);
    sub(/[^A-Za-z_.-]+.*/, "", name);
    stack[++stack_i] = sprintf("<data type='%s' datatypeLibrary='http://www.w3.org/2001/XMLSchema-datatypes'",
                               name);
    postop = 0;
    aft = "";
    if (length(line) >= length(name) + 5) {
      aft = substr(line, length(name) + 5);
      sub(/^ */, "", aft)
    }
    if (substr(aft, 1, 1) == "{") {
      stack[stack_i] = stack[stack_i] ">";
      aft = substr(aft, 2);
      while (aft != "" && substr(aft, 1, 1) != "}") {
        sub(/^ */, "", aft);
        subpos = index(aft, "=");
        paramname = substr(aft, 1, subpos - 1);
        sub(/ *$/, "", paramname);
        aft = substr(aft, subpos);
        subpos = index(aft, "\"");
        aft = substr(aft, subpos + 1);
        subpos = index(aft, "\"");
        paramval = substr(aft, 1, subpos - 1);
        aft = substr(aft, subpos + 1);
        sub(/^ */, "", aft);
        stack[stack_i] = stack[stack_i] sprintf("<param name='%s'>%s</param>", paramname, paramval);
      }
      stack[stack_i] = stack[stack_i] "</data>";
      if (aft != "")
        aft = substr(aft, 2);
    }
    else {
      stack[stack_i] = stack[stack_i] "/>";
    }
    if (aft != "") {
      parse_pattern(aft);
    }
  }
  else if (match(line, /^[A-Za-z_.-]/)) {
    if (popop(line)) {
      next;
    }
    name = substr(line, 1);
    sub(/[^A-Za-z_.-]+.*/, "", name);
    if (name == "string") {
      stack[++stack_i] = "<data type='string'/>";
    }
    else if (name == "empty") {
      stack[++stack_i] = "<empty/>";
    }
    else if (name == "notAllowed") {
      stack[++stack_i] = "<notAllowed/>";
    }
    else {
      stack[++stack_i] = sprintf("<ref name='%s'/>", name);
    }
    postop = 0;
    if (length(line) >= length(name) + 1) {
      aft = substr(line, length(name) + 1);
      parse_pattern(aft);
    }
  }
}
function popop (line) {
  op = stack[paren[paren_i]];
  if (postop == 0 && (op == "||" || op == "&&" || op == ",,")) {
    stack[paren[paren_i]] = "(" substr(op, 1, 1);
    parse_pattern(")");
    mode = "grammar";
    if (line != "") {
      parse_define(line);
    }
    return 1;
  }
  return 0;
}
function parse_name_class (line) {
  sub(/^ */, "", line)
  if (length(line) == 0) return;
  c = substr(line, 1, 1);
  if (c == "{") {
    if (stack_i != name_class_i) {
      tmp = "";
      for (i = stack_i; i >= name_class_i; i--) {
        if (stack[i] == "<except>") {
          tmp = "<except>" tmp "</except>";
        }
        else if (stack[i] == "<anyName>") {
          tmp = "<anyName>" tmp "</anyName>";
        }
        else {
          tmp = stack[i] tmp
        }
      }
      stack[name_class_i] = tmp;
      stack_i = name_class_i;
    }
    mode = "pattern";
    parse_pattern(line);
  }
  else if (c == "*") {
    if (stack[stack_i] == "<element" || stack[stack_i] == "<attribute") {
      stack[stack_i] = stack[stack_i] ">";
    }
    stack[++stack_i] = "<anyName>";
    parse_name_class(substr(line, 2));
  }
  else if (c == "-" && stack[stack_i] == "<anyName>") {
    stack[++stack_i] = "<except>"
    parse_name_class(substr(line, 2));
  }
  else if (c == "|") {
    if (length(stack[paren[paren_i]]) == 1) {
      stack[paren[paren_i]] = stack[paren[paren_i]] c;
    }
    else if (substr(stack[paren[paren_i]], 2) != "|") {
      print "Mismatched infix operators on line " FNR | "cat 1>&2";
      error = 1;
      exit 1
    }
    parse_name_class(substr(line, 2));
  }
  else if (c == "(") {
    stack[++stack_i] = "(";
    paren[++paren_i] = stack_i;
    parse_name_class(substr(line, 2));
  }
  else if (c == ")") {
    open = stack[paren[paren_i]];
    if (substr(open, 1, 1) != "(") {
      print "Mismatched parentheses on line " FNR | "cat 1>&2";
      error = 1;
      exit 1
    }
    if (length(open) == 2 && substr(open, 2, 1) != "|") {
      print "Unknown name class pattern on line " FNR | "cat 1>&2";
      error = 1;
      exit 1
    }
    tmp = ""
    for (i = paren[paren_i] + 1; i <= stack_i; i++) {
      tmp = tmp stack[i] "\n";
    }
    stack_i = paren[paren_i];
    stack[stack_i] = tmp;
    paren_i--;
    parse_name_class(substr(line, 2));
  }
  else if (match(line, /^[A-Za-z_.-]/)) {
    name = substr(line, 1);
    sub(/[^A-Za-z_.-]+.*/, "", name);
    if (length(line) >= length(name) + 1)
      aft = substr(line, length(name) + 1);
    else
      aft = "";
    if (length(aft) >= 2 && substr(aft, 1, 2) == ":*") {
      namespace_uri = "";
      if (name == "xml") {
        namespace_uri = "http://www.w3.org/XML/1998/namespace";
      }
      else {
        for (i = 1; i <= namespaces_i; i++) {
          if (nsnames[i] == name) {
            namespace_uri = namespaces[i];
            break;
          }
        }
      }
      stack[++stack_i] = sprintf("<nsName ns='%s'/>", namespace_uri);
      if (length(aft) >= 3)
        aft = substr(aft, 3);
      else
        aft = "";
    }
    else {
      if (length(aft) >= 2 && substr(aft, 1, 1) == ":") {
        checkns = "";
        pos = 1;
        while (pos <= namespaces_i) {
          if (namespaces[pos] != "" && nsnames[pos] == name) {
            checkns = namespaces[pos];
            break;
          }
          pos++;
        }
        if (name != "xml" && checkns == "") {
          print "Unknown namespace prefix " name " on line " FNR | "cat 1>&2";
          error = 1;
          exit 1
        }
        localname = substr(aft, 2);
        sub(/[^A-Za-z_.-]+.*/, "", localname);
        if (length(aft) >= length(localname) + 2)
          aft = substr(aft, length(localname) + 2);
        else
          aft = "";
        name = name ":" localname;
      }
      if (stack[stack_i] == "<element" || stack[stack_i] == "<attribute") {
        stack[stack_i] = stack[stack_i] sprintf(" name='%s'>", name);
      }
      else {
        stack[++stack_i] = sprintf("<name>%s</name>", name);
      }
    }
    parse_name_class(aft);
  }
}

function printstack () {
  pos = 1;
  while (pos <= stack_i) {
    printstackone();
  }
}
function printstackone () {
  if (substr(stack[pos], 1, 1) == "#") {
    print "<!--";
    while (substr(stack[pos], 1, 1) == "#") {
      cmt = substr(stack[pos], 2);
      sub(/^ */, "", cmt);
      print cmt;
      pos++;
    }
    print "-->";
  }
  else if (substr(stack[pos], 1, 6) == "<start") {
    print stack[pos];
    pos++;
    printstackone();
    print "</start>"
  }
  else if (substr(stack[pos], 1, 7) == "<define") {
    print stack[pos];
    pos++;
    printstackone();
    print "</define>"
  }
  else {
    print stack[pos];
    pos++;
  }
}

BEGIN {
  mode = "grammar";
  stack_i = 0;
  paren_i = 0;
  namespaces_i = 0;
  include_i = 0;
  postop = 0;
  error = 0;
  maybe_define = "";
}

END {
  popop("");
  if (!error) {
    print "<grammar xmlns='http://relaxng.org/ns/structure/1.0'";
    pos = 1;
    while (pos <= namespaces_i) {
      if (namespaces[pos] != "") {
        printf " xmlns:%s='%s'", nsnames[pos], namespaces[pos];
      }
      pos++;
    }
    if (default_namespace != "") {
      printf " ns='%s'>\n", default_namespace;
    }
    else {
      print ">";
    }
    printstack()
    print "</grammar>"
  }
}
/^[^#]/ || /^$/ {
  if (substr(stack[stack_i], 1, 1) == "#") {
    stack[++stack_i] = " "
  }
}

mode == "pattern" && paren_i == 0 && /^[^{(]*=/ { mode = "grammar"; }
mode == "grammar" && /^[^{(]*=/ {
  if (match($0, "^default namespace ")) {
    namespace = substr($0, index($0, "=") + 1);
    nsname = substr($0, 19, index($0, "=") - 19);
    sub(/^ */, "", nsname);
    sub(/ *$/, "", nsname);
    sub(/^ *"/, "", namespace);
    sub(/" *$/, "", namespace);
    if (nsname != "") {
      nsnames[++namespaces_i] = nsname;
      namespaces[namespaces_i] = namespace;
    }
    default_namespace = namespace
  }
  else if (match($0, "^namespace ")) {
    namespace = substr($0, index($0, "=") + 1);
    nsname = substr($0, 11, index($0, "=") - 11);
    sub(/^ */, "", nsname);
    sub(/ *$/, "", nsname);
    sub(/^ *"/, "", namespace);
    sub(/" *$/, "", namespace);
    if (nsname != "") {
      nsnames[++namespaces_i] = nsname;
      namespaces[namespaces_i] = namespace;
    }
  }
  else {
    parse_define($0);
  }
  next;
}
mode == "grammar" && /^include / {
  href = substr($0, index($0, "\"") + 1);
  brace = substr(href, index(href, "\"") + 1);
  href = substr(href, 1, index(href, "\"") - 1);
  sub(/^ */, "", brace);
  sub(/ *$/, "", brace);
  sub(/\.rnc$/, ".rng", href);
  if (brace == "{") {
    stack[++stack_i] = "<include href=\"" href "\">";
    include_i = stack_i;
  }
  else {
    stack[++stack_i] = "<include href=\"" href "\"/>";
  }
}
mode == "grammar" && /^ *[A-Za-z_.-]/ {
  maybe_define = substr($0, 1, length($0));
  sub(/^ */, "", maybe_define);
  sub(/ *$/, "", maybe_define);
}
include_i != 0 && paren_i == 0 && /}/ {
  if (substr(stack[include_i], 1, 8) == "<include") {
    stack[++stack_i] = "</include>";
  }
  else {
    print "Mismatched parentheses on line " FNR | "cat 1>&2";
    error = 1;
    exit 1
  }
  mode = "grammar";
  include_i = 0;
  next;
}
mode == "pattern" && /^[^#]/ {
  parse_pattern($0);
  next;
}
mode == "name_class" && /^[^#]/ {
  parse_name_class($0);
  next;
}
# Doesn't handle all comments. That would require modifying
# parse_pattern and parse_name_class and generally being a lot
# more clever about output. But it handles comments that start
# a line outside a pattern. Enough for me.
/#.*/ {
  popop("");
  stack[++stack_i] = $0
  next;
}
Footer
