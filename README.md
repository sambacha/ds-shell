# ds-shell

>

## `bash`: concepts

Bash is aligned strongly with the **Unix philosophy**.  As such, this can cause moments of confusion while trying to understand why and how things work the way that they do.  The goal of this document is to demystify various topics and let the rest of the documentation link here instead of explaining it poorly multiple times.

The examples here are captured from a terminal.  Lines that start with `~$` are the prompt where you type commands.  The part before `$` bit indicates the current working directory, and `~` means my home directory.  The stuff after `$` are the commands that I type.  Other lines are the output from the command.  In this example I make a directory, go into that directory and then perform a file listing. There are no files in the new directory, so the file listing does not produce any output.

```bash 
    ~$ mkdir test
    ~$ cd test
    ~/test$ ls
    ~/test$ cd ..
    ~$ rmdir test
    ~$
```
Comments to explain commands are added sometimes to help clarify what's going on.  They start with a `#` symbol and continue to the end of the line.  You don't need to type them in, but if you do, you won't mess anything up.

```bash 
    ~$ # This is a comment
    ~$ # Comments do not affect the shell
    ~$
```

## Success and Failure: Return Codes

> see [openbsd/src/blob/master/sys/sys/errno.h](https://github.com/openbsd/src/blob/master/sys/sys/errno.h)

Programs can report success by returning a status code of 0.  Anything else is considered a failure.  In the way of the Unix, there is only one success but many reasons why something can fail.

When shell scripts do not use an `exit` keyword, the status code of the shell script will be equal to the last executed command's status code.  You can see the status code by using `$?`.  Here is an example:

```bash 
    ~$ # Create a file, list it, then show the success status code
    ~$ touch somefile.txt
    ~$ ls somefile.txt
    somefile.txt
    ~$ echo $?
    0
    ~$ # Remove the file, list it, show the error status code
    ~$ rm somefile.txt
    ~$ ls somefile.txt
    ls: cannot access somefile.txt: No such file or directory
    ~$ echo $?
    2
    ~$
```

Shell scripts can pick their return code and abruptly stop the program at any time using the `exit` keyword.  Here is a simple shell script that exits with a number that's equal to the number of arguments passed to it.

```bash 
    ~$ cat > simple-script <<'EOF'
    > #!/usr/bin/env bash
    > exit $#
    > EOF
    ~$ chmod 755 simple-script
    ~$ ./simple-script
    ~$ echo $?
    0
    ~$ ./simple-script one two three
    3
    ~$
```

## Stdout and Stderr


Every process that's running can write output to "stdout" and "stderr".  Typically, the non-error output goes to stdout and error messages go to stderr.  Stdout is captured using `>` and stderr is captured using `2>`.  Take a look at this example.

```bash 
    ~$ cat > stdout-stderr <<'EOF'
    > #!/usr/bin/env bash
    > ls $@ > stdout 2> stderr
    > echo "stdout:"
    > cat stdout
    > echo "stderr:"
    > cat stderr
    > EOF
    ~$ chmod 755 stdout-stderr
    ~$ touch somefile.txt
    ~$ ./stdout-stderr somefile.txt
    stdout:
    somefile.txt
    stderr:
    ~$ rm somefile.txt
    ~$ ./stdout-stderr somefile.txt
    stdout:
    stderr:
    ls: cannot access somefile.txt: No such file or directory
    ~$
```

To write to stdout in a shell script is trivial.

```bash 
    echo "This goes to stdout"
```

Writing content to stderr is slightly more difficult, but you can do it!

```bash 
    echo "This goes to stderr" >&2
```

### Sourcing Files


Here is sourcing a file in two different ways:

```bash 
    ~$ # Method 1
    ~$ source some-other-file
    ~$ # Method 2
    ~$ . some-other-file
```

What does it do?  It pretends that you typed in the commands in that other file in this shell.  Let's use a better example.

```bash 
    ~$ # Create a file with a function in it
    ~$ cat > testing-function <<'EOF'
    > #!/usr/bin/env bash
    > testMe() {
    > echo "This is the function"
    > }
    > echo "testing-function was sourced or executed"
    > EOF
    ~$ chmod 755 testing-function
    ~$
```

When you run the test script it will not create the function in the current environment.

```bash 
    ~$ ./testing-function
    testing-function was sourced or executed
    ~$ testMe
    testMe: command not found
    ~$
```

When you source the test script, the function is added to your environment and you can use it.

```bash 
    ~$ . testing-function
    testing-function was sourced or executed
    ~$ testMe
    This is the function
    ~$
```

## Bash Strict Mode

As found on [another website](http://redsymbol.net/articles/unofficial-bash-strict-mode/), there is a combination of flags that you can enable to enable a sort of strict mode.  This project is using this combination:

```bash 
    set -eEu -o pipefail
    shopt -s extdebug
    IFS=$'\n\t'
    trap 'wickStrictModeFail $?' ERR
```

A brief summary of what each option does:

* `set -e`: Exit immediately if a command exits with a non-zero status, unless that command is part a test condition.  On failure this triggers the ERR trap. **There are [some contexts][exit on error] that will disable this setting!**
* `set -E`: The ERR trap is inherited by shell functions, command substitutions and commands in subshells.  This helps us use `wickStrictModeFail` wherever `set -e` is enabled.
* `set -u`: Exit and trigger the ERR trap when accessing an unset variable.  This helps catch typos in variable names.
* `set -o pipefail`: The return value of a pipeline is the value of the last (rightmost) command to exit with a non-zero status.  So, `a | b | c` can return `a`'s status when `b` and `c` both return a zero status.  It is easier to catch problems during the middle of processing a pipeline this way.
* `shopt -s extdebug`: Enable extended debugging.  Bash will track the parameters to all the functions in the call stack, allowing the stack trace to also display the parameters that were used.
* `IFS=$'\n\t'`: Set the "internal field separator", which is a list of characters use for word splitting after expansion and to split lines into words with the `read` builtin command.  Normally this is `$' \t\n'` and we're removing the space.  This helps us catch other issues when we may rely on IFS or accidentally use it incorrectly.
* `trap 'wickStrictModeFail $?' ERR`:  The ERR trap is triggered when a script catches an error.  `wickStrictModeFail` attempts to produce a stack trace to aid in debugging.  We pass `$?` as the first argument so we have access to the return code of the failed command.

This document deals heavily with status codes, conditionals, and other constructs in Bash scripts.  For more information on those, read about [#concepts].


