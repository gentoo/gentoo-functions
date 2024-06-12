# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# shellcheck shell=sh disable=2209,3043

# This file contains a series of function declarations followed by some
# initialisation code. Functions intended for internal use shall be prefixed
# with an <underscore> and shall not be considered as being a part of the public
# API. With the exception of those declared by the local builtin, all variables
# intended for internal use shall be prefixed with "genfun_" to indicate so,
# and to reduce the probability of name space conflicts.

# The following variables affect initialisation and/or function behaviour.

# BASH             : whether bash-specific features may be employed
# BASH_VERSINFO    : whether bash-specific features may be employed
# BASHPID          : may be used by _update_columns() to detect subshells
# COLUMNS          : may be used by _update_columns() to get the column count
# EPOCHREALTIME    : potentially used by _update_time() to get the time
# GENFUN_MODULES   : which of the optional function collections must be sourced
# IFS              : multiple warn() operands are joined by its first character
# INVOCATION_ID    : used by from_unit()
# PORTAGE_BIN_PATH : used by from_portage()
# RC_OPENRC_PID    : used by from_runscript()
# SYSTEMD_EXEC_PID : used by from_unit()
# TERM             : used to detect dumb terminals

#------------------------------------------------------------------------------#

#
# A safe wrapper for the cd builtin. To run cd "$dir" is problematic because:
#
# - it may consider its operand as an option
# - it will search CDPATH for an operand not beginning with ./, ../ or /
# - it will switch to OLDPWD if the operand is -
# - cdable_vars causes bash to treat the operand as a potential variable name
#
chdir()
{
	if [ "$BASH" ]; then
		# shellcheck disable=3044
		shopt -u cdable_vars
	fi
	if [ "$1" = - ]; then
		set -- ./-
	fi
	# shellcheck disable=1007,2164
	CDPATH= cd -- "$@"
}

#
# Determines whether the current shell is a subprocess of portage.
#
from_portage()
{
	test "${PORTAGE_BIN_PATH}"
}

#
# Determines whether the current shell is executing an OpenRC runscript, or is
# a subprocess of one.
#
from_runscript()
{
	has_openrc && test "${RC_OPENRC_PID}"
}

#
# Determines whether the current shell is a subprocess of a systemd unit that
# handles a service, socket, mount point or swap device, per systemd.exec(5).
#
from_unit()
{
	has_systemd && test "${SYSTEMD_EXEC_PID}" && test "${INVOCATION_ID}"
}

#
# Determines whether OpenRC appears to be operational as a service manager in
# the context of the present root filesystem namespace.
#
has_openrc()
{
	test -d /run/openrc
}

#
# Determines whether systemd appears to be operational as a service manager in
# the context of the present root filesystem namespace.
#
has_systemd()
{
	test -d /run/systemd
}

#
# Prints a horizontal rule. If specified, the first parameter shall be taken as
# a string to be repeated in the course of composing the rule. Otherwise, it
# shall default to the <hyphen-minus>. If specified, the second parameter shall
# define the length of the rule in characters. Otherwise, it shall default to
# the width of the terminal if such can be determined, or 80 if it cannot be.
#
hr()
{
	local length

	if is_int "$2"; then
		length=$2
	elif _update_tty_level <&1; [ "${genfun_tty}" -eq 2 ]; then
		length=${genfun_cols}
	else
		length=80
	fi
	PATTERN=${1:--} awk -v "width=${length}" -f - <<-'EOF'
		BEGIN {
			while (length(rule) < width) {
				rule = rule substr(ENVIRON["PATTERN"], 1, width - length(rule))
			}
			print rule
		}
	EOF
}

#
# Determines whether the first parameter is a valid identifier (variable name).
#
is_identifier()
(
	LC_ALL=C
	case $1 in
		''|_|[[:digit:]]*|*[!_[:alnum:]]*) false
	esac
)

#
# Determines whether the first parameter is a valid integer. A leading
# <hypen-minus> shall be permitted. Thereafter, leading zeroes shall not be
# permitted because the string might later be considered to be octal in an
# arithmetic context, causing the shell to exit if the number be invalid.
#
is_int()
{
	set -- "${1#-}"
	case $1 in
		''|*[!0123456789]*)
			false
			;;
		0)
			true
			;;
		*)
			test "$1" = "${1#0}"
	esac
}

#
# Determines whether the first parameter matches any of the parameters that
# follow it.
#
is_anyof()
{
	local arg needle

	if [ "$#" -eq 0 ]; then
		warn "is_anyof: too few arguments (got $#, expected at least 1)"
	else
		needle=$1
		shift
		for arg; do
			if [ "${arg}" = "${needle}" ]; then
				return
			fi
		done
	fi
	false
}

#
# Collects the intersection of the parameters up to - but not including - a
# sentinel value then determines whether the resulting set is a subset of the
# interection of the remaining parameters. If the SENTINEL variable is set and
# non-empty, it shall be taken as the value of the sentinel. Otherwise, the
# value of the sentinel shall be defined as <hyphen-dash><hyphen-dash>. If the
# sentinel value is not encountered or if either set is empty then the returm
# value shall be greater than 1.
#
is_subset()
{
	SENTINEL=${SENTINEL:-'--'} awk -f - -- "$@" <<-'EOF'
		BEGIN {
			argc = ARGC
			ARGC = 1
			for (i = 1; i < argc; i++) {
				word = ARGV[i]
				if (word == ENVIRON["SENTINEL"]) {
					break
				} else {
					set1[word] = ""
				}
			}
			if (i == 1 || argc - i < 2) {
				exit 1
			}
			for (i++; i < argc; i++) {
				word = ARGV[i]
				set2[word] = ""
			}
			for (word in set2) {
				delete set1[word]
			}
			for (word in set1) {
				exit 1
			}
		}
	EOF
}

#
# Considers one or more pathnames and prints the one having the newest
# modification time. If at least one parameter is provided, all parameters shall
# be considered as pathnames to be compared to one another. Otherwise, the
# pathnames to be compared shall be read from the standard input as
# NUL-delimited records. If no pathnames are given, or those specified do not
# exist, the return value shall be greater than 0. In the case that two or more
# pathnames are candidates, the one having the lexicographically greatest value
# shall be selected. Pathnames containing newline characters shall be ignored.
#
newest()
{
	_select_by_mtime -r "$@"
}

#
# Tries to determine the number of available processors. Falls back to trying to
# determine the number of online processors in a way that is somewhat portable.
#
get_nprocs()
{
	if nproc 2>/dev/null; then
		# The nproc(1) utility is provided by GNU coreutils. It has the
		# advantage of acknowledging the effect of sched_setaffinity(2).
		true
	elif getconf _NPROCESSORS_ONLN 2>/dev/null; then
		# This is a non-standard extension. Nevertheless, it works for
		# glibc, musl-utils, macOS, FreeBSD, NetBSD and OpenBSD.
		true
	else
		warn "get_nprocs: failed to determine the number of processors"
		false
	fi
}

#
# Considers one or more pathnames and prints the one having the oldest
# modification time. If at least one parameter is provided, all parameters shall
# be considered as pathnames to be compared to one another. Otherwise, the
# pathnames to be compared shall be read from the standard input as
# NUL-delimited records. If no pathnames are given, or those specified do not
# exist, the return value shall be greater than 0. In the case that two or more
# pathnames are candidates, the one having the lexicographically lesser value
# shall be selected. Pathnames containing newline characters shall be ignored.
#
oldest()
{
	_select_by_mtime -- "$@"
}

#
# Executes a simple command in parallel. At least two parameters are expected.
# The first parameter shall be taken as the maximum number of jobs to run
# concurrently. If specified as less than or equal to 0, the number shall be
# determined by running the nproc function. The second parameter shall be taken
# as a command name. The remaining parameters shall be conveyed to the specified
# command, one at a time. Should at least one command fail, the return value
# shall be greater than 0.
#
parallel_run()
{
	local arg cmd i statedir w workers

	if [ "$#" -lt 3 ]; then
		warn "parallel_run: too few arguments (got $#, expected at least 3)"
		return 1
	elif ! is_int "$1"; then
		_warn_for_args parallel_run "$1"
		return 1
	elif [ "$1" -le 0 ] && ! workers=$(get_nprocs); then
		return 1
	elif ! statedir=${TMPDIR:-/tmp}/parallel_run.$$.$(srandom); then
		return 1
	fi
	workers=${workers:-$1} cmd=$2
	shift 2
	w=0
	i=0
	(
		while [ "$(( w += 1 ))" -le "${workers}" ]; do
			i=$w
			while [ "$i" -le "$#" ]; do
				eval "arg=\$${i}"
				if ! "${cmd}" "${arg}"; then
					mkdir -p -- "${statedir}"
				fi
				i=$(( i + workers ))
			done &
		done
		wait
	)
	! rmdir -- "${statedir}" 2>/dev/null
}

#
# Prints the positional parameters in a format that may be reused as shell
# input. For each considered, it shall be determined whether its value contains
# any non-printable characters in lieu of the US-ASCII character set. If no such
# characters are found, the value shall have each instance of <apostrophe> be
# replaced by <apostrophe><backslash><apostrophe><apostrophe> before being
# enclosed by a pair of <apostrophe> characters. Otherwise, non-printable
# characters shall be replaced by octal escape sequences, <apostrophe> by
# <backslash><apostrophe> and <backslash> by <backslash><backslash>, prior to
# the value being given a prefix of <dollar-sign><apostrophe> and a suffix of
# <apostrophe>, per Issue 8. Finally, the resulting values shall be printed as
# <space> separated. The latter quoting strategy can be suppressed by setting
# the POSIXLY_CORRECT variable as non-empty in the environment.
#
quote_args()
{
	awk -v q=\' -f - -- "$@" <<-'EOF'
		BEGIN {
			strictly_posix = length(ENVIRON["POSIXLY_CORRECT"])
			argc = ARGC
			ARGC = 1
			for (arg_idx = 1; arg_idx < argc; arg_idx++) {
				arg = ARGV[arg_idx]
				if (strictly_posix || arg !~ /[\001-\037\177]/) {
					gsub(q, q "\\" q q, arg)
					word = q arg q
				} else {
					# Use $'' quoting per Issue 8
					if (ord_by["\001"] == "") {
						for (i = 1; i < 32; i++) {
							char = sprintf("%c", i)
							ord_by[char] = i
						}
						ord_by["\177"] = 127
					}
					word = "$'"
					for (i = 1; i <= length(arg); i++) {
						char = substr(arg, i, 1)
						if (char == "\\") {
							word = word "\\\\"
						} else if (char == q) {
							word = word "\\'"
						} else {
							ord = ord_by[char]
							if (ord != "") {
								word = word "\\" sprintf("%03o", ord)
							} else {
								word = word char
							}
						}
					}
					word = word q
				}
				line = line word
				if (arg_idx < argc - 1) {
					line = line " "
				}
			}
			print line
		}
	EOF
}

#
# Generates a random uint32 with the assistance of the kernel CSPRNG.
#
srandom()
{
	# shellcheck disable=3028
	if [ "${BASH_VERSINFO:-0}" -ge 5 ]; then
		srandom()
		{
			printf '%d\n' "${SRANDOM}"
		}
	elif [ -c /dev/urandom ]; then
		srandom()
		{
			printf '%d\n' "0x$(
				LC_ALL=C od -vAn -N4 -tx1 /dev/urandom | tr -d '[:space:]'
			)"
		}
	else
		warn "srandom: /dev/urandom doesn't exist as a character device"
		return 1
	fi

	srandom
}

#
# Trims leading and trailing whitespace from one or more lines. If at least one
# parameter is provided, each positional parameter shall be considered as a line
# to be processed. Otherwise, the lines to be processed shall be read from the
# standard input. The trimmed lines shall be printed to the standard output.
#
trim()
{
	if [ "$#" -gt 0 ]; then
		printf '%s\n' "$@"
	else
		cat
	fi |
	sed -e 's/^[[:space:]]\{1,\}//' -e 's/[[:space:]]\{1,\}$//'
}

#
# Prints a diagnostic message prefixed with the basename of the running script.
#
warn()
{
	printf '%s: %s\n' "${0##*/}" "$*" >&2
}

#
# Considers the first parameter as the potential name of an executable regular
# file before attempting to locate it. If not specifed as an absolute pathname,
# a PATH search shall be performed in accordance with the Environment Variables
# section of the Base Definitions. If an executable is found, its path shall be
# printed. Otherwise, the return value shall be 1. This function is intended as
# an alternative to type -P in bash. That is, it is useful for determining the
# existence and location of an external utility without potentially matching
# against aliases, builtins and functions (as command -v can).
#
whenceforth()
(
	local bin path prefix

	case $1 in
		/*)
			# Absolute command paths must be directly checked.
			[ -f "$1" ] && [ -x "$1" ] && bin=$1
			;;
		*)
			# Relative command paths must be searched for in PATH.
			# https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html#tag_08_03
			case ${PATH} in
				''|*:)
					path=${PATH}:
					;;
				*)
					path=${PATH}
			esac
			IFS=:
			set -f
			for prefix in ${path}; do
				case ${prefix} in
					*/)
						bin=${prefix}$1
						;;
					*)
						bin=${prefix:-.}/$1
				esac
				[ -f "${bin}" ] && [ -x "${bin}" ] && break
			done
	esac \
	&& printf '%s\n' "${bin}"
)

#------------------------------------------------------------------------------#

#
# Considers the first parameter as containing zero or more blank-separated words
# then determines whether any of the remaining parameters can be matched in
# their capacity as discrete words.
#
_contains_word()
{
	local word wordlist

	wordlist=$1 word=$2
	case ${word} in
		''|*[[:blank:]]*)
			;;
		*)
			case " ${wordlist} " in
				*[[:blank:]]"${word}"[[:blank:]]*)
					return
					;;
			esac
	esac
	false
}

#
# Determines whether the terminal is a dumb one.
#
_has_dumb_terminal()
{
	! case ${TERM} in *dumb*) false ;; esac
}

#
#
# See the definitions of oldest() and newest().
#
_select_by_mtime() {
	local sort_opt

	sort_opt=$1
	shift
	if [ "$#" -ge 0 ]; then
		printf '%s\0' "$@"
	else
		cat
	fi \
	| "${genfun_bin_find}" -files0-from - -maxdepth 0 ! -path "*${genfun_newline}*" -printf '%T+ %p\n' \
	| sort "${sort_opt}" \
	| { IFS= read -r line && printf '%s\n' "${line#* }"; }
}

#
# Considers the first parameter as a number of deciseconds and determines
# whether fewer have elapsed since the last occasion on which the function was
# called.
#
_should_throttle()
{
	_update_time || return
	if [ "$(( genfun_time - genfun_last_time > $1 ))" -eq 1 ]; then
		genfun_last_time=${genfun_time}
		false
	fi
}

#
# Determines whether the terminal on STDIN is able to report its dimensions.
# Upon success, the number of columns shall be stored in genfun_cols.
#
_update_columns()
{
	# Two optimisations are applied. Firstly, the rate at which updates can
	# be performed is throttled to intervals of 5 deciseconds. Secondly, if
	# running on bash then the COLUMNS variable may be gauged, albeit only
	# in situations where doing so can be expected to work reliably; not if
	# in a subshell. Note that executing true(1) is faster than executing
	# stty(1) within a comsub.
	# shellcheck disable=3028,3044
	if _should_throttle 5; then
		test "${genfun_cols}"
		return
	elif [ "$$" = "${BASHPID}" ] && shopt -q checkwinsize; then
		"${genfun_bin_true}"
		set -- 0 "${COLUMNS}"
	else
		# The following use of stty(1) is portable as of POSIX Issue 8.
		genfun_ifs=${IFS}
		IFS=' '
		# shellcheck disable=2046
		set -- $(stty size 2>/dev/null)
		IFS=${genfun_ifs}
	fi
	[ "$#" -eq 2 ] && is_int "$2" && [ "$2" -gt 0 ] && genfun_cols=$2
}

#
# Determines either the number of deciseconds elapsed since the unix epoch or
# the number of deciseconds that the operating system has been online, depending
# on the capabilities of the shell and/or platform. Upon success, the obtained
# value shall be assigned to genfun_time. Otherwise, the return value shall be
# greater than 0.
#
_update_time()
{
	genfun_last_time=0

	# shellcheck disable=3028
	if [ "${BASH_VERSINFO:-0}" -ge 5 ]; then
		# shellcheck disable=2034,3045
		_update_time()
		{
			local ds s timeval

			timeval=${EPOCHREALTIME}
			s=${timeval%.*}
			printf -v ds '%.1f' ".${timeval#*.}"
			if [ "${ds}" = "1.0" ]; then
				ds=10
			else
				ds=${ds#0.}
			fi
			genfun_time=$(( s * 10 + ds ))
		}
	elif [ -f /proc/uptime ]; then
		_update_time()
		{
			local ds s timeval

			IFS=' ' read -r timeval _ < /proc/uptime || return
			s=${timeval%.*}
			printf -v ds '%.1f' ".${timeval#*.}"
			if [ "${ds}" = "1.0" ]; then
				ds=10
			else
				ds=${ds#0.}
			fi
			genfun_time=$(( s * 10 + ds ))
		}
	else
		_update_time()
		{
			false
		}
	fi

	_update_time
}

#
# Grades the capability of the terminal attached to STDIN, assigning the level
# to genfun_tty. If no terminal is detected, the level shall be 0. If a dumb
# terminal is detected, the level shall be 1. If a smart terminal is detected,
# the level shall be 2. For a terminal to be considered as smart, it must be
# able to successfully report its dimensions.
#
_update_tty_level()
{
	if [ ! -t 0 ]; then
		genfun_tty=0
	elif _has_dumb_terminal || ! _update_columns; then
		genfun_tty=1
	else
		genfun_tty=2
	fi
}

#
# Takes the first parameter as the path of a gentoo-functions module then
# determines whether it has been requested by attempting to match its basename
# against the any of the blank-separated words defined by the GENFUN_MODULES
# variable (not including the ".sh" suffix).
#
_want_module()
{
	local basename

	basename=${1##*/}
	_contains_word "${GENFUN_MODULES}" "${basename%.sh}"
}

#
# Prints a diagnostic message concerning invalid function arguments. The first
# argument shall be taken as a function identifier. The remaining arguments
# shall be safely rendered as a part of the diagnostic.
#
_warn_for_args()
{
	local ident plural

	ident=$1
	shift
	[ "$#" -gt 1 ] && plural=s || plural=
	warn "${ident}: invalid argument${plural}: $(quote_args "$@")"
}

#------------------------------------------------------------------------------#

# This shall be incremented by one upon any change being made to the public API.
# It was introduced by gentoo-functions-1.7 with an initial value of 1.
# shellcheck disable=2034
GENFUN_API_LEVEL=1

# If genfun_basedir is unset, set genfun_prefix to the value of EPREFIX, as it
# was at the time of installing gentoo-functions, before setting genfun_basedir
# to the path of the directory to which this file was installed. Otherwise,
# honour its existing value so as to ease the development and testing process.
if [ ! "${genfun_basedir+set}" ]; then
	genfun_prefix=
	genfun_basedir=${genfun_prefix}/lib/gentoo
fi

# Store the name of the GNU find binary. Some platforms may have it as "gfind".
hash gfind 2>/dev/null && genfun_bin_find=gfind || genfun_bin_find=find

# Assign the LF ('\n') character for later expansion. POSIX Issue 8 permits
# $'\n' but it may take years for it to be commonly implemented.
genfun_newline='
'

# Store the path to the true binary. It is potentially used by _update_columns.
if [ "${BASH}" ]; then
	genfun_bin_true=$(whenceforth true)
fi

# The GENFUN_MODULES variable acts as a means of selecting modules, which are
# merely optional collections of functions. If unset then set it now.
if [ ! "${GENFUN_MODULES+set}" ]; then
	# OpenRC provides various functions and utilities which have long had
	# parallel implementations in gentoo-functions. Declare ours only if the
	# shell is neither executing a runscript nor is a subprocess of one.
	if ! from_runscript; then
		GENFUN_MODULES="rc"
	fi
	# Several functions are available which overlap with functions and
	# utilities provided by portage. These exist primarily to make it easier
	# to test code outside of ebuilds. Declare them only if the shell is not
	# a subprocess of portage.
	if ! from_portage; then
		GENFUN_MODULES="${GENFUN_MODULES}${GENFUN_MODULES+ }portage"
	fi
fi

# Source any modules that have been selected by the GENFUN_MODULES variable.
for _ in "${genfun_basedir}/functions"/*.sh; do
	if _want_module "$_"; then
		. "$_" || return
	fi
done
