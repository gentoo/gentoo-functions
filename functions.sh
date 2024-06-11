# Copyright 1999-2023 Gentoo Authors
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
# EERROR_QUIET     : whether error printing functions should be silenced
# EINFO_LOG        : whether printing functions should call esyslog()
# EINFO_QUIET      : whether info message printing functions should be silenced
# EINFO_VERBOSE    : whether v-prefixed functions should do anything
# EPOCHREALTIME    : potentially used by _update_time() to get the time
# IFS              : multiple message operands are joined by its first character
# INSIDE_EMACS     : whether to work around an emacs-specific bug in _eend()
# NO_COLOR         : whether colored output should be suppressed
# PORTAGE_BIN_PATH : used by from_portage()
# RC_NOCOLOR       : like NO_COLOR but deprecated
# TEST_GENFUNCS    : used for testing the behaviour of get_bootparam()
# TERM             : may influence message formatting and whether color is used

################################################################################

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
# Prints a diagnostic message prefixed with the basename of the running script
# before exiting. It shall preserve the value of $? as it was at the time of
# invocation unless its value was 0, in which case the exit status shall be 1.
#
if ! command -v die >/dev/null; then
	die()
	{
		case $? in
			0)
				genfun_status=1
				;;
			*)
				genfun_status=$?
		esac
		warn "$@"
		exit "${genfun_status}"
	}
fi

#
# Prints a message indicating the onset of a given process, provided that
# EINFO_QUIET is false. It is expected that eend eventually be called, so as to
# indicate whether the process completed successfully or not.
#
ebegin()
{
	local msg

	if ! yesno "${EINFO_QUIET}"; then
		msg=$*
		while _ends_with_newline "${msg}"; do
			msg=${msg%"${genfun_newline}"}
		done
		_eprint "${GOOD}" "${msg} ...${genfun_newline}"
	fi
}

#
# Takes the positional parameters as the definition of a simple command then
# prints the command as an informational message with einfo before executing it.
# Should the command fail, a diagnostic message shall be printed and the shell
# be made to exit by calling the die function.
#
edo()
{
	genfun_cmd=$(quote_args "$@")
	einfo "Executing: ${genfun_cmd}"
	"$@" || die "Failed to execute command: ${genfun_cmd}"
}

#
# Prints an indicator to convey the completion of a given process, provided that
# EINFO_QUIET is false. It is expected that it be paired with an earlier call to
# ebegin. The first parameter shall be taken as an exit status value, making it
# possible to distinguish between success and failure. If unspecified, it shall
# default to 0. The remaining parameters, if any, shall be taken as a diagnostic
# message to convey as an error where the exit status is not 0.
#
eend()
{
	GENFUN_CALLER=${GENFUN_CALLER:-eend} _eend eerror "$@"
}

#
# Declare the eerror, einfo and ewarn functions. These wrap errorn, einfon and
# ewarnn respectively, the difference being that a newline is appended.
#
for _ in eerror einfo ewarn; do
	eval "
		$_ ()
		{
			${_}n \"\${*}\${genfun_newline}\"
		}
	"
done

#
# Prints an error message without appending a newline, provided that
# EERROR_QUIET is false. If printed, the message shall also be conveyed to the
# esyslog function.
#
eerrorn()
{
	if ! yesno "${EERROR_QUIET}"; then
		_eprint "${BAD}" "$@" >&2
		esyslog "daemon.err" "${0##*/}" "$@"
	fi
	return 1
}

#
# Decreases the level of indentation used by various printing functions. If no
# numerical parameter is given, or if it is negative, increase by 2 spaces.
#
eindent()
{
	if ! is_int "$1" || [ "$1" -le 0 ]; then
		set -- 2
	fi
	_esetdent "$(( ${#genfun_indent} + $1 ))"
}

#
# Prints an informational message without appending a newline, provided that
# EINFO_QUIET is false.
#
einfon()
{
	if ! yesno "${EINFO_QUIET}"; then
		_eprint "${GOOD}" "$@"
	fi
}

#
# Decreases the level of indentation used by various printing functions. If no
# numerical parameter is given, or if it is negative, decrease by 2 spaces.
#
eoutdent()
{
	if ! is_int "$1" || [ "$1" -le 0 ]; then
		set -- 2
	fi
	_esetdent "$(( ${#genfun_indent} - $1 ))"
}

#
# This is based on the eqatag function defined by isolated-functions.sh in
# portage. If the first parameter is the -v option, it shall be disregarded.
# Discounting said option, at least one parameter is required, which shall be
# taken as a tag name. Thereafter, zero or more parameters shall be accepted in
# the form of "key=val", followed by zero or more parameters beginning with a
# <slash>. An object shall be composed in which the tag is the value of a "tag"
# key, the key/value pairs the value of a "data" key, and the <slash>-prefixed
# parameters the value of a "files" key. The resulting object shall be rendered
# as JSON by jq(1) before being logged by the logger(1) utility.
#
eqatag()
{
	local arg i json positional tag

	case ${genfun_has_jq} in
		0)
			return 1
			;;
		'')
			if ! hash jq 2>/dev/null; [ "$(( genfun_has_jq = $? ))" -eq 0 ]; then
				warn "eqatag: this function requires that jq be installed"
				return 1
			fi
	esac
	# Acknowledge the -v option for isolated-functions API compatibility.
	if [ "$1" = "-v" ]; then
		shift
	fi
	if [ "$#" -eq 0 ]; then
		warn "eqatag: no tag specified"
		return 1
	fi
	positional=0
	tag=$1
	shift
	i=0
	for arg; do
		if [ "$(( i += 1 ))" -eq 1 ]; then
			set --
		fi
		case ${arg} in
			[!=/]*=?*)
				if [ "${positional}" -eq 1 ]; then
					_warn_for_args eqatag "${arg}"
					return 1
				fi
				set -- "$@" --arg "${arg%%=*}" "${arg#*=}"
				;;
			/*)
				if [ "${positional}" -eq 0 ]; then
					set -- "$@" --args --
					positional=1
				fi
				set -- "$@" "${arg}"
				;;
			*)
				_warn_for_args eqatag "${arg}"
				return 1
		esac
	done
	json=$(
		jq -cn '{
			eqatag: {
				tag:   $ARGS.named["=tag"],
				data:  $ARGS.named | with_entries(select(.key | startswith("=") | not)),
				files: $ARGS.positional
			}
		}' --arg "=tag" "${tag}" "$@"
	) \
	&& logger -p user.debug -t "${0##*/}" -- "${json}"
}

#
# Prints a QA warning message, provided that EINFO_QUIET is false. If printed,
# the message shall also be conveyed to the esyslog function. For now, this is
# implemented merely as an ewarn wrapper.
#
eqawarn()
{
	ewarn "$@"
}

#
# Invokes the logger(1) utility, provided that EINFO_LOG is true. The first
# parameter shall be taken as a priority level, the second as the message tag,
# and the remaining parameters as the message to be logged.
#
esyslog()
{
	local pri tag msg

	if [ "$#" -lt 2 ]; then
		warn "esyslog: too few arguments (got $#, expected at least 2)"
		return 1
	elif yesno "${EINFO_LOG}" && hash logger 2>/dev/null; then
		pri=$1
		tag=$2
		shift 2
		msg=$*
		if _is_visible "${msg}"; then
			# This is not strictly portable because POSIX defines
			# no options whatsoever for logger(1).
			logger -p "${pri}" -t "${tag}" -- "${msg}"
		fi
	fi
}

#
# Prints a warning message without appending a newline, provided that
# EINFO_QUIET is false. If printed, the message shall also be conveyed to the
# esyslog function.
#
ewarnn()
{
	if ! yesno "${EINFO_QUIET}"; then
		_eprint "${WARN}" "$@" >&2
		esyslog "daemon.warning" "${0##*/}" "$@"
	fi
}

#
# This behaves as the eend function does, except that the given diagnostic
# message shall be presented as a warning rather than an error.
#
ewend()
{
	GENFUN_CALLER=${GENFUN_CALLER:-ewend} _eend ewarn "$@"
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
# Determines whether the kernel cmdline contains the specified parameter as a
# component of a comma-separated list specified in the format of gentoo=<list>.
#
get_bootparam()
(
	# Gentoo cmdline parameters are comma-delimited, so a search
	# string containing a comma must not be allowed to match.
	# Similarly, the empty string must not be allowed to match.
	case $1 in ''|*,*) return 1 ;; esac

	# Reset the value of IFS because there is no telling what it may be.
	IFS=$(printf ' \n\t')

	if [ "${TEST_GENFUNCS}" = 1 ]; then
		read -r cmdline
	else
		read -r cmdline < /proc/cmdline
	fi || return

	# Disable pathname expansion. The definition of this function
	# is a compound command that incurs a subshell. Therefore, the
	# prior state of the option does not need to be recalled.
	set -f
	for opt in ${cmdline}; do
		gentoo_opt=${opt#gentoo=}
		if [ "${opt}" != "${gentoo_opt}" ]; then
			case ,${gentoo_opt}, in
				*,"$1",*) return 0
			esac
		fi
	done
	return 1
)

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
# Takes the first parameter as a reference file/directory then determines
# whether any of the following parameters refer to newer files/directories.
#
is_older_than()
{
	local ref

	if [ "$#" -eq 0 ]; then
		warn "is_older_than: too few arguments (got $#, expected at least 1)"
		return 1
	elif [ -e "$1" ]; then
		ref=$1
	else
		ref=
	fi
	shift
	{ test "$#" -gt 0 && printf '%s\0' "$@"; } \
	| "${genfun_bin_find}" -L -files0-from - ${ref:+-newermm} ${ref:+"${ref}"} -printf '\n' -quit \
	| read -r _
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
# Declare the vebegin, veerror, veindent, veinfo, veinfon, veoutdent and vewarn
# functions. These differ from their non-v-prefixed counterparts in that they
# only have an effect where EINFO_VERBOSE is true.
#
for _ in vebegin veerror veindent veinfo veinfon veoutdent vewarn; do
	eval "
		$_ ()
		{
			if yesno \"\${EINFO_VERBOSE}\"; then
				${_#v} \"\$@\"
			fi
		}
	"
done

veend()
{
	if yesno "${EINFO_VERBOSE}"; then
		GENFUN_CALLER=veend eend "$@"
	elif [ "$#" -gt 0 ] && { ! is_int "$1" || [ "$1" -lt 0 ]; }; then
		_warn_for_args veend "$1"
		false
	else
		return "$1"
	fi
}

vewend()
{
	if yesno "${EINFO_VERBOSE}"; then
		GENFUN_CALLER=vewend ewend "$@"
	elif [ "$#" -gt 0 ] && { ! is_int "$1" || [ "$1" -lt 0 ]; }; then
		_warn_for_args vewend "$1"
		false
	else
		return "$1"
	fi
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

#
# Determines whether the first parameter is truthy. The values taken to be true
# are "yes", "true", "on" and "1", whereas their opposites are taken to be
# false. The empty string is also taken to be false. All pattern matching is
# performed case-insensitively.
#
yesno()
{
	local arg

	if [ "$#" -eq 0 ]; then
		warn "yesno: too few arguments (got $#, expected 1)"
		return 1
	fi
	arg=$1
	for _ in 1 2; do
		case ${arg} in
			[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|[Oo][Ff][Ff]|0|'')
				return 1
				;;
			[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|[Oo][Nn]|1)
				return 0
		esac
		if [ "$_" -ne 1 ] || ! is_identifier "$1"; then
			break
		else
			# The value appears to be a legal variable name. Treat
			# it as a name reference and try again, once only.
			eval "arg=\$$1"
		fi
	done
	_warn_for_args yesno "$@"
	false
}

#
# Called by eend, ewend, veend and vewend. See the definition of eend for an
# overall description of its purpose.
#
_eend()
{
	local col efunc msg retval

	efunc=$1
	shift
	if [ "$#" -eq 0 ]; then
		retval=0
	elif ! is_int "$1" || [ "$1" -lt 0 ]; then
		_warn_for_args "${GENFUN_CALLER}" "$1"
		retval=1
		msg=
	else
		retval=$1
		shift
		msg=$*
	fi

	if [ "${retval}" -ne 0 ]; then
		# If a message was given, print it with the specified function.
		if _is_visible "${msg}"; then
			"${efunc}" "${msg}"
		fi
		# Generate an indicator for ebegin's unsuccessful conclusion.
		if _update_tty_level <&1; [ "${genfun_tty}" -eq 0 ]; then
			msg="[ !! ]"
		else
			msg="${BRACKET}[ ${BAD}!!${BRACKET} ]${NORMAL}"
		fi
	elif yesno "${EINFO_QUIET}"; then
		return "${retval}"
	else
		# Generate an indicator for ebegin's successful conclusion.
		if _update_tty_level <&1; [ "${genfun_tty}" -eq 0 ]; then
			msg="[ ok ]"
		else
			msg="${BRACKET}[ ${GOOD}ok${BRACKET} ]${NORMAL}"
		fi
	fi

	if [ "${genfun_tty}" -eq 2 ]; then
		# Save the cursor position with DECSC, move it up by one line
		# with CUU, position it horizontally with CHA, print the
		# indicator, then restore the cursor position with DECRC.
		col=$(( genfun_cols > 6 ? genfun_cols - 6 : 1 ))
		printf '\0337\033[1A\033[%dG %s\0338' "$(( col + genfun_offset ))" "${msg}"
	else
		# The standard output refers either to an insufficiently capable
		# terminal or to something other than a terminal. Print the
		# indicator, using <space> characters to indent to the extent
		# that the last character falls on the 80th column. This hinges
		# on the fair assumption that a newline was already printed.
		printf '%80s\n' "${msg}"
	fi

	return "${retval}"
}

#
# Determines whether the given string is newline-terminated.
#
_ends_with_newline()
{
	test "${genfun_newline}" \
	&& ! case $1 in *"${genfun_newline}") false ;; esac
}

#
# Called by ebegin, eerrorn, einfon, and ewarnn.
#
_eprint()
{
	local color

	color=$1
	shift

	if [ -t 1 ]; then
		printf ' %s*%s %s%s' "${color}" "${NORMAL}" "${genfun_indent}" "$*"
	else
		printf ' * %s%s' "${genfun_indent}" "$*"
	fi
}

#
# Called by eindent, eoutdent, veindent and veoutdent. It is here that the
# variable containing the horizontal whitespace is updated.
#
_esetdent()
{
	if [ "$1" -lt 0 ]; then
		set -- 0
	fi
	genfun_indent=$(printf "%${1}s" '')
}

#
# Tries to determine whether the terminal supports ECMA-48 SGR color sequences.
#
_has_color_terminal()
{
	local colors

	# The tput(1) invocation is not portable, though ncurses suffices. In
	# this day and age, it is exceedingly unlikely that it will be needed.
	if _has_dumb_terminal; then
		false
	elif colors=$(tput colors 2>/dev/null) && is_int "${colors}"; then
		test "${colors}" -gt 0
	else
		true
	fi
}

#
# Determines whether the terminal is a dumb one.
#
_has_dumb_terminal()
{
	! case ${TERM} in *dumb*) false ;; esac
}

#
# Determines whether the first parameter contains any visible characters.
#
_is_visible()
{
	! case $1 in *[[:graph:]]*) false ;; esac
}

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

# All function declarations end here! Initialisation code only from hereon.
# shellcheck disable=2034
RC_GOT_FUNCTIONS=yes

# This shall be incremented by one upon any change being made to the public API.
# It was introduced by gentoo-functions-1.7 with an initial value of 1.
# shellcheck disable=2034
GENFUN_API_LEVEL=1

# Assign the LF ('\n') character for later expansion. POSIX Issue 8 permits
# $'\n' but it may take years for it to be commonly implemented.
genfun_newline='
'

# In Emacs, M-x term opens an "eterm-color" terminal, whose implementation of
# the CHA (ECMA-48 CSI) sequence suffers from an off-by-one error.
if [ "${INSIDE_EMACS}" ] && [ "${TERM}" = "eterm-color" ]; then
	genfun_offset=-1
else
	genfun_offset=0
fi

# Store the path to the true binary. It is potentially used by _update_columns.
if [ "${BASH}" ]; then
	genfun_bin_true=$(whenceforth true)
fi

# Store the name of the GNU find binary. Some platforms may have it as "gfind".
hash gfind 2>/dev/null && genfun_bin_find=gfind || genfun_bin_find=find

# Determine whether the use of color is to be wilfully avoided.
if [ -n "${NO_COLOR}" ]; then
	# See https://no-color.org/.
	RC_NOCOLOR=yes
else
	for _ in "$@"; do
		case $_ in
			--nocolor|--nocolour|-C)
				RC_NOCOLOR=yes
				break
		esac
	done
fi

if ! _has_color_terminal || yesno "${RC_NOCOLOR}"; then
	unset -v BAD BRACKET GOOD HILITE NORMAL WARN
else
	# Define some ECMA-48 SGR sequences for color support. These variables
	# are public, in so far as users of the library may be expanding them.
	# Conveniently, these sequences are documented by console_codes(4).
	BAD=$(printf '\033[31;01m')
	BRACKET=$(printf '\033[34;01m')
	GOOD=$(printf '\033[32;01m')
	# shellcheck disable=2034
	HILITE=$(printf '\033[36;01m')
	NORMAL=$(printf '\033[0m')
	WARN=$(printf '\033[33;01m')
fi
