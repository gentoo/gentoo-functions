# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# shellcheck shell=sh disable=2209,3043

# This file contains a series of function declarations followed by some
# initialisation code. Functions intended for internal use shall be prefixed
# with an <underscore> and shall not be considered as being a part of the public
# API. With the exception of those declared by the local builtin, all variables
# intended for internal use shall be prefixed with "genfun_" to indicate so,
# and to reduce the probability of name space conflicts.

# The functions shall be compatible with the POSIX-1.2018 Shell and Utilities
# (XCU), except where otherwise noted, and with the additional exception that
# the use of the local utility is permitted, despite the results of its
# invocation being formally unspecified.

# The following variables affect initialisation and/or function behaviour.

# BASH             : whether bash-specific features may be employed
# BASH_VERSINFO    : whether bash-specific features may be employed
# BASHPID          : may be used by _update_columns() to detect subshells
# COLUMNS          : may be used by _update_columns() to get the column count
# EPOCHREALTIME    : potentially used by _update_time() to get the time
# GENFUN_MODULES   : which of the optional function collections must be sourced
# IFS              : warn() operands are joined by its first character
# INVOCATION_ID    : used by from_unit()
# PORTAGE_BIN_PATH : used by from_portage()
# RC_OPENRC_PID    : used by from_runscript()
# SENTINEL         : can define a value separating two distinct argument lists
# SYSTEMD_EXEC_PID : used by from_unit()
# TERM             : used to detect dumb terminals

#------------------------------------------------------------------------------#

#
# Considers the first parameter as a reference to a variable by name and
# assigns the second parameter as its value. If the first parameter is found
# not to be a legal identifier, no assignment shall occur and the return value
# shall be greater than 0.
#
assign()
{
	if [ "$#" -ne 2 ]; then
		warn "assign: wrong number of arguments (got $#, expected 2)"
		false
	elif ! is_identifier "$1"; then
		_warn_for_args assign "$@"
		false
	else
		eval "$1=\$2"
	fi
}

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
	if [ "$#" -eq 1 ]; then
		case $1 in
			'')
				_warn_for_args chdir "$1"
				return 1
				;;
			-)
				set -- ./-
		esac
	fi
	if [ "${BASH}" ]; then
		# shellcheck disable=3044
		shopt -u cdable_vars
	fi
	# shellcheck disable=1007,2164
	CDPATH= cd -- "$@"
}

#
# Considers the first parameter as a string comprising zero or more
# whitespace-separated words then determines whether all of the remaining
# parameters can be found within the resulting list in their capacity as
# discrete words. If they cannot be, or if fewer than two parameters were given,
# the return value shall be 1. Of the words to be searched for, any which are
# empty or which contain whitespace characters shall be deemed unfindable.
#
contains_all()
{
	local arg haystack

	[ "$#" -gt 1 ] || return
	haystack=" $1 "
	shift
	for arg; do
		case ${arg} in
			''|*[[:space:]]*)
				return 1
		esac
		case ${haystack} in
			*" ${arg} "*)
				;;
			*)
				return 1
		esac
	done
}

#
# Considers the first parameter as a string comprising zero or more
# whitespace-separated words then determines whether any of the remaining
# parameters can be found within the resulting list in their capacity as
# discrete words. If none can be, or if no parameters were given, the return
# value shall be greater than 0. Of the words to be searched for, any which are
# empty or which contain whitespace characters shall be disregarded.
#
contains_any()
{
	local arg haystack

	[ "$#" -gt 0 ] || return
	haystack=" $1 "
	shift
	for arg; do
		case ${arg} in
			''|*[[:space:]]*)
				continue
		esac
		case ${haystack} in
			*" ${arg} "*)
				return 0
		esac
	done
	false
}

#
# Considers the first parameter as a reference to a variable by name and
# attempts to retrieve its presently assigned value. If only one parameter is
# specified, the retrieved value shall be printed to the standard output. If a
# second parameter is also specified, it shall be be taken as the name of a
# variable to which the retrieved value shall be assigned. If any parameter is
# found not to be a legal identifier, or if the variable referenced by the
# first parameter is unset, the return value shall be greater than 0.
#
deref()
{
	if [ "$#" -eq 0 ] || [ "$#" -gt 2 ]; then
		warn "deref: wrong number of arguments (got $#, expected between 1 and 2)"
	elif ! trueof_all is_identifier -- "$@"; then
		_warn_for_args deref "$@"
		false
	elif ! eval "test \${$1+set}"; then
		false
	elif [ "$#" -eq 1 ]; then
		eval "printf '%s\\n' \"\$$1\""
	else
		eval "$2=\$$1"
	fi
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
# a string whose first character is to be repeated in the course of composing
# the rule. Otherwise, or if specified as the empty string, it shall default to
# the <hyphen-minus>. If specified, the second parameter shall define the length
# of the rule in characters. Otherwise, it shall default to the width of the
# terminal if such can be determined, or 80 if it cannot be.
#
hr()
{
	local c hr i length

	if [ "$#" -ge 2 ] && is_int "$2"; then
		length=$2
	elif _update_tty_level <&1; [ "${genfun_tty}" -eq 2 ]; then
		length=${genfun_cols}
	else
		length=80
	fi
	c=${1--}
	c=${c%"${c#?}"}
	i=0
	while [ "$(( i += 16 ))" -le "${length}" ]; do
		hr=${hr}${c}${c}${c}${c}${c}${c}${c}${c}${c}${c}${c}${c}${c}${c}${c}${c}
	done
	i=${#hr}
	while [ "$(( i += 1 ))" -le "${length}" ]; do
		hr=${hr}${c}
	done
	printf '%s\n' "${hr}"
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
# <hyphen-minus> shall be permitted. Thereafter, leading zeroes shall not be
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
		# This constant is standard as of POSIX-1.2024 and was already
		# supported by glibc, musl-utils, macOS, FreeBSD, NetBSD and OpenBSD.
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
# determined by calling the get_nprocs function. The second parameter shall be
# taken as a command name. The remaining parameters shall be conveyed to the
# specified command, one at a time. Should at least one command fail, the
# return value shall be greater than 0.
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
# any bytes that are either outside the scope of the US-ASCII character set or
# which are considered as non-printable. If no such bytes are found, the value
# shall have each instance of <apostrophe> be replaced by <apostrophe>
# <backslash> <apostrophe> <apostrophe> before being enclosed by a pair of
# <apostrophe> characters. However, as a special case, a value consisting of a
# single <apostrophe> shall be replaced by <backslash> <apostrophe>.
#
# If any such bytes are found, the value shall instead be requoted in a manner
# that conforms with section 2.2.4 of the Shell Command Language, wherein the
# the use of dollar-single-quotes sequences is described. Such sequences are
# standard as of POSIX-1.2024. However, as of August 2024, many implementations
# lack support for this feature. So as to mitigate this state of affairs, the
# use of dollar-single-quotes may be suppressed by setting POSIXLY_CORRECT as a
# non-empty string.
#
quote_args()
{
	LC_ALL=C awk -v q=\' -f - -- "$@" <<-'EOF'
	function init_table() {
		# Iterate over ranges \001-\037 and \177-\377.
		for (i = 1; i <= 255; i += (i == 31 ? 96 : 1)) {
			char = sprintf("%c", i)
			seq_by[char] = sprintf("%03o", i)
		}
		seq_by["\007"] = "a"
		seq_by["\010"] = "b"
		seq_by["\011"] = "t"
		seq_by["\012"] = "n"
		seq_by["\013"] = "v"
		seq_by["\014"] = "f"
		seq_by["\015"] = "r"
		seq_by["\033"] = "e"
		seq_by["\047"] = "'"
		seq_by["\134"] = "\\"
	}
	BEGIN {
		issue = length(ENVIRON["POSIXLY_CORRECT"]) ? 7 : 8;
		argc = ARGC
		ARGC = 1
		for (arg_idx = 1; arg_idx < argc; arg_idx++) {
			arg = ARGV[arg_idx]
			if (arg == q) {
				word = "\\" q
			} else if (issue < 8 || arg !~ /[\001-\037\177-\377]/) {
				gsub(q, q "\\" q q, arg)
				word = q arg q
			} else {
				# Use $'' quoting per POSIX-1.2024.
				if (! ("\001" in seq_by)) {
					init_table()
				}
				word = "$'"
				for (i = 1; i <= length(arg); i++) {
					char = substr(arg, i, 1)
					if (char in seq_by) {
						word = word "\\" seq_by[char]
					} else {
						word = word char
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
# Considers the parameters up to - but not including - a sentinel value as the
# words comprising a simple command then determines whether said command
# succeeds for all of the remaining parameters, passing them one at a time. If
# the SENTINEL variable is set, it shall be taken as the value of the sentinel.
# Otherwise, the value of the sentinel shall be defined as <hyphen-dash>
# <hyphen-dash>. If the composed command is empty, the sentinel value is not
# encountered or there are no parameters following the sentinel, the return
# value shall be greater than 0.
#
trueof_all()
{
	local arg arg_idx i j

	arg_idx=0
	i=0
	j=0
	for arg; do
		if [ "$(( arg_idx += 1 ))" -eq 1 ]; then
			set --
		fi
		if [ "$i" -gt 1 ]; then
			"$@" "${arg}" || return
			j=${arg_idx}
		elif [ "${arg}" = "${SENTINEL-"--"}" ]; then
			i=${arg_idx}
		else
			set -- "$@" "${arg}"
		fi
	done
	test "$i" -gt 1 && test "$j" -gt "$i"
}

#
# Considers the parameters up to - but not including - a sentinel value as the
# words comprising a simple command then determines whether said command
# succeeds for at least one of the remaining parameters, passing them one at a
# time. If the SENTINEL variable is set, it shall be taken as the value of the
# sentinel. Otherwise, the value of the sentinel shall be defined as
# <hyphen-dash> <hyphen-dash>. If the composed command is empty, the sentinel
# value is not encountered or there are no parameters following the sentinel,
# the return value shall be greater than 0.
#
trueof_any()
{
	local arg arg_idx i

	arg_idx=0
	i=0
	for arg; do
		if [ "$(( arg_idx += 1 ))" -eq 1 ]; then
			set --
		fi
		if [ "$i" -gt 1 ]; then
			"$@" "${arg}" && return
		elif [ "${arg}" = "${SENTINEL-"--"}" ]; then
			i=${arg_idx}
		else
			set -- "$@" "${arg}"
		fi
	done
	false
}

#
# Prints a diagnostic message prefixed with the basename of the running script.
#
warn()
{
	printf '%s: %s\n' "${0##*/}" "$*" >&2
}

#
# Considers the first parameter as a command name before trying to locate it as
# a regular file. If not specified as an absolute pathname, a PATH search shall
# be performed in accordance with the Environment Variables section of the Base
# Definitions. If a file is found, its path shall be printed. Otherwise, the
# return value shall be 1. If the -x option is specified then the file must
# also be executable by the present user in order to be matched. This function
# serves as an alternative to type -P in bash. It is useful for determining the
# existence and location of an external utility without potentially matching
# against aliases, builtins and functions (as command -v can).
#
whenceforth()
(
	local bin executable opt path prefix

	executable=
	while getopts :x opt; do
		case ${opt} in
			x)
				executable=1
				;;
			'?')
				_warn_for_args whenceforth "-${OPTARG}"
				return 1
		esac
	done
	shift "$(( OPTIND - 1 ))"

	case $1 in
		/*)
			# Absolute command paths must be directly checked.
			test -f "$1" && test ${executable:+-x} "$1" && bin=$1
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
				test -f "${bin}" && test ${executable:+-x} "${bin}" && break
			done
	esac \
	&& printf '%s\n' "${bin}"
)

#------------------------------------------------------------------------------#

#
# See the definitions of _select_by_mtime() and is_older_than(). This function
# requires that GNU findutils >=4.9 be installed.
#
_find0()
{
	# Store the name of the GNU find binary, which may be "gfind".
	hash gfind 2>/dev/null && genfun_bin_find=gfind || genfun_bin_find=find

	_find0()
	{
		local opt

		case $1 in
			-[HL])
				opt=$1
				shift
				set -- "${opt}" -files0-from - "$@"
				;;
			*)
				set -- -files0-from - "$@"
		esac
		"${genfun_bin_find}" "$@"
	}

	_find0 "$@"
}

#
# Determines whether the terminal is a dumb one.
#
_has_dumb_terminal()
{
	! case ${TERM} in *dumb*) false ;; esac
}

#
# See the definitions of oldest() and newest().
#
_select_by_mtime()
{
	local sort_opt

	sort_opt=$1
	shift
	if [ "$#" -ge 0 ]; then
		printf '%s\0' "$@"
	else
		cat
	fi \
	| _find0 -maxdepth 0 ! -path "*${genfun_newline}*" -printf '%T+ %p\n' \
	| sort "${sort_opt}" \
	| { IFS= read -r line && printf '%s\n' "${line#* }"; }
}

#
# Considers the first parameter as a number of centiseconds and determines
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
	# shellcheck disable=3044
	if [ "${BASH}" ] && shopt -q checkwinsize; then
		genfun_bin_true=$(whenceforth -x true)
	fi

	_update_columns()
	{
		# Two optimisations are applied. Firstly, the rate at which
		# updates can be performed is throttled to intervals of half a
		# second. Secondly, if running on bash then the COLUMNS variable
		# may be gauged, albeit only in situations where doing so can be
		# expected to work reliably; it is an unreliable method where
		# operating from a subshell. Note that executing true(1) is
		# faster than executing stty(1) within a comsub.
		# shellcheck disable=3028
		if _should_throttle 50; then
			test "${genfun_cols}"
			return
		elif [ "${genfun_bin_true}" ] && [ "$$" = "${BASHPID}" ]; then
			"${genfun_bin_true}"
			set -- 0 "${COLUMNS}"
		else
			# This use of stty(1) is portable as of POSIX-1.2024.
			genfun_ifs=${IFS}
			IFS=' '
			# shellcheck disable=2046
			set -- $(stty size 2>/dev/null)
			IFS=${genfun_ifs}
		fi
		[ "$#" -eq 2 ] && is_int "$2" && [ "$2" -gt 0 ] && genfun_cols=$2
	}

	_update_columns
}

#
# Determines either the number of centiseconds elapsed since the unix epoch or
# the number of centiseconds that the operating system has been online,
# depending on the capabilities of the shell and/or platform. Upon success, the
# obtained value shall be assigned to genfun_time. Otherwise, the return value
# shall be greater than 0.
#
_update_time()
{
	genfun_last_time=0

	# shellcheck disable=3028
	if [ "${BASH_VERSINFO:-0}" -ge 5 ]; then
		# shellcheck disable=2034,3045
		_update_time()
		{
			# Setting LC_NUMERIC as C ensures a radix character of
			# U+2E, duly affecting both EPOCHREALTIME and printf.
			local LC_ALL LC_NUMERIC=C cs s timeval

			timeval=${EPOCHREALTIME}
			s=${timeval%.*}
			printf -v cs '%.2f' ".${timeval#*.}"
			if [ "${cs}" = "1.00" ]; then
				cs=100
			else
				cs=${cs#0.} cs=${cs#0}
			fi
			genfun_time=$(( s * 100 + cs ))
		}
	elif [ -f /proc/uptime ]; then
		_update_time()
		{
			local cs s

			IFS='. ' read -r s cs _ < /proc/uptime \
			&& genfun_time=$(( s * 100 + ${cs#0} ))
		}
	else
		_update_time()
		{
			return 2
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
	contains_any "${GENFUN_MODULES}" "${basename%.sh}"
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

# Assign the LF ('\n') character for later expansion. POSIX-1.2024 permits $'\n'
# but it may take years for it to be commonly implemented.
genfun_newline='
'

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
