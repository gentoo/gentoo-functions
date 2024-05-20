# Copyright 1999-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# shellcheck shell=sh disable=3043

# This file contains a series of function declarations followed by some
# initialisation code. Functions intended for internal use shall be prefixed
# with an <underscore> and shall not be considered as being a part of the public
# API. With the exception of those declared by the local builtin, all variables
# intended for internal use shall be prefixed with "genfun_" to indicate so,
# and to reduce the probability of name space conflicts.

# The following variables affect initialisation and/or function behaviour.

# BASH          : whether bash-specific features may be employed
# BASHPID       : potentially used by _update_columns() to detect subshells
# COLUMNS       : potentially used by _update_columns() to get the column count
# EERROR_QUIET  : whether error printing functions should be silenced
# EINFO_LOG     : whether printing functions should call esyslog()
# EINFO_QUIET   : whether info message printing functions should be silenced
# EINFO_VERBOSE : whether v-prefixed functions should do anything
# IFS           : multiple message operands are joined by its first character
# INSIDE_EMACS  : whether to work around an emacs-specific bug in _eend()
# NO_COLOR      : whether colored output should be suppressed
# RC_NOCOLOR    : like NO_COLOR but deprecated
# TEST_GENFUNCS : used for testing the behaviour of get_bootparam()
# TERM          : may influence message formatting and whether color is used

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
		printf '%s: %s\n' "${0##*/}" "$*" >&2
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
edo() {
	genfun_cmd=$(_print_args "$@")
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
		$_ () {
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
eqatag() {
	local arg argc json positional tag

	case ${genfun_has_jq} in
		0)
			return 1
			;;
		1)
			;;
		*)
			if command -v jq >/dev/null; then
				genfun_has_jq=1
			else
				ewarn "The eqatag() function requires that jq be installed"
				genfun_has_jq=0
				return 1
			fi
	esac
	# Acknowledge the -v option for isolated-functions API compatibility.
	if [ "$1" = "-v" ]; then
		shift
	fi
	if [ "$#" -eq 0 ]; then
		die "eqatag: no tag specified"
	fi
	tag=$1
	shift
	argc=$#
	positional=0
	for arg; do
		case ${arg} in
			[!=/]*=?*)
				if [ "${positional}" -eq 1 ]; then
					_throw_invalid_args eqatag "${arg}"
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
				_throw_invalid_args eqatag "${arg}"
		esac
	done
	shift "${argc}"
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
eqawarn() {
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
		die "esyslog: too few arguments (got $#, expected at least 2)"
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
# Takes the first parameter as a reference file/directory then determines
# whether any of the following parameters refer to newer files/directories.
#
is_older_than()
{
	local ref has_gfind

	if [ "$#" -lt 2 ]; then
		die "is_older_than: too few arguments (got $#, expected at least 2)"
	elif [ -e "$1" ]; then
		ref=$1
	else
		ref=
	fi
	shift

	# Consult the hash table in the present shell, prior to forking.
	hash gfind 2>/dev/null; has_gfind=$(( $? == 0 ))

	for path; do
		if [ -e "${path}" ]; then
			printf '%s\0' "${path}"
		fi
	done |
	{
		set -- -L -files0-from - ${ref:+-newermm} ${ref:+"${ref}"} -printf '\n' -quit
		if [ "${has_gfind}" -eq 1 ]; then
			gfind "$@"
		else
			find "$@"
		fi
	} |
	read -r _
}

#
# Declare the vebegin, veerror, veindent, veinfo, veinfon, veoutdent and vewarn
# functions. These differ from their non-v-prefixed counterparts in that they
# only have an effect where EINFO_VERBOSE is true.
#
for _ in vebegin veerror veindent veinfo veinfon veoutdent vewarn; do
	eval "
		$_ () {
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
		_throw_invalid_args veend "$1"
	else
		return "$1"
	fi
}

vewend()
{
	if yesno "${EINFO_VERBOSE}"; then
		GENFUN_CALLER=vewend ewend "$@"
	elif [ "$#" -gt 0 ] && { ! is_int "$1" || [ "$1" -lt 0 ]; }; then
		_throw_invalid_args vewend "$1"
	else
		return "$1"
	fi
}

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
		die "yesno: too few arguments (got $#, expected 1)"
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
			! break
		else
			# The value appears to be a legal variable name. Treat
			# it as a name reference and try again, once only.
			eval "arg=\$$1"
		fi
	done || _throw_invalid_args yesno "$1"
	return 1
}

#
# Called by eend, ewend, veend and vewend. See the definition of eend for an
# overall description of its purpose.
#
_eend()
{
	local efunc msg retval

	efunc=$1
	shift
	if [ "$#" -eq 0 ]; then
		retval=0
	elif ! is_int "$1" || [ "$1" -lt 0 ]; then
		_throw_invalid_args "${GENFUN_CALLER}" "$1"
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
		printf '\0337\033[1A\033[%dG %s\0338' "$(( genfun_cols - 6 + genfun_offset ))" "${msg}"
	else
		# The standard output does not refer to a sufficiently capable
		# terminal. Print only the indicator.
		printf ' %s\n' "${msg}"
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
# Prints the positional parameters in a manner that approximates the behaviour
# of the ${*@Q} expansion in bash. The output shall be POSIX sh compatible as of
# Issue 8. This should probably be made to exist as a standalone awk script.
#
_print_args() {
	awk -v q=\' -f - -- "$@" <<-'EOF'
		BEGIN {
			argc = ARGC
			ARGC = 1
			for (arg_idx = 1; arg_idx < argc; arg_idx++) {
				arg = ARGV[arg_idx]
				if (arg !~ /[\001-\037\177]/) {
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
# Prints a diganostic message concerning invalid function arguments then exits.
# The first argument shall be taken as a function identifier. The remaining
# arguments shall be safely rendered as a part of the diagnostic.
#
_throw_invalid_args()
{
	local ident plural

	ident=$1
	shift
	[ "$#" -gt 1 ] && plural=s || plural=
	die "${ident}: invalid argument${plural}: $(_print_args "$@")"
}

#
# Determines whether the terminal on STDIN is able to report its dimensions.
# Upon success, the number of columns shall be stored in genfun_cols.
#
_update_columns()
{
	# Command substitutions are rather slow in bash. Using the COLUMNS
	# variable helps but checkwinsize won't work properly in subshells.
	# shellcheck disable=3028,3044
	if [ "$$" = "${BASHPID}" ] && shopt -q checkwinsize; then
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

# All function declarations end here! Initialisation code only from hereon.
# shellcheck disable=2034
RC_GOT_FUNCTIONS=yes

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
	# shellcheck disable=3045
	genfun_bin_true=$(type -P true)
fi

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
