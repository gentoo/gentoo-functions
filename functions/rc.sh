# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# shellcheck shell=sh disable=3043

# This file contains alternative implementations for some of the functions and
# utilities provided by OpenRC. Please refer to ../functions.sh for coding
# conventions.

# The following variables affect initialisation and/or function behaviour.

# EERROR_QUIET  : whether error printing functions should be silenced
# EINFO_LOG     : whether printing functions should call esyslog()
# EINFO_QUIET   : whether info message printing functions should be silenced
# EINFO_VERBOSE : whether v-prefixed functions should do anything
# IFS           : multiple message operands are joined by its first character
# INSIDE_EMACS  : whether to work around an emacs-specific bug in _eend()
# NO_COLOR      : whether colored output should be suppressed
# RC_NOCOLOR    : like NO_COLOR but deprecated
# TERM          : whether to work around an emacs-specific bug in _eend()
# TEST_GENFUNCS : used for testing the behaviour of get_bootparam()

#------------------------------------------------------------------------------#

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
		pri=$1 tag=$2
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

#------------------------------------------------------------------------------#

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
# Determines whether the first parameter contains any visible characters.
#
_is_visible()
{
	! case $1 in *[[:graph:]]*) false ;; esac
}

#------------------------------------------------------------------------------#

# Determine whether the use of color is to be wilfully avoided.
if [ -n "${NO_COLOR}" ]; then
	# See https://no-color.org/.
	RC_NOCOLOR=yes
else
	for _; do
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

# In Emacs, M-x term opens an "eterm-color" terminal, whose implementation of
# the CHA (ECMA-48 CSI) sequence suffers from an off-by-one error.
if [ "${INSIDE_EMACS}" ] && [ "${TERM}" = "eterm-color" ]; then
	genfun_offset=-1
else
	genfun_offset=0
fi

# shellcheck disable=2034
RC_GOT_FUNCTIONS=yes
