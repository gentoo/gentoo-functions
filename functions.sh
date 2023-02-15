# Copyright 1999-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# shellcheck shell=sh disable=3043

# shellcheck disable=2034
RC_GOT_FUNCTIONS="yes"

#
#    This is a private function, called by ebegin, eerrorn, einfon, and ewarnn.
#
_eprint() {
	local color
	color=$1
	shift

	if [ -z "${genfun_endcol}" ] && [ "${genfun_lastcall}" = "ebegin" ]; then
		printf '\n'
	fi
	if [ -t 1 ]; then
		printf ' %s*%s %s%s' "${color}" "${NORMAL}" "${genfun_indent}" "$*"
	else
		printf ' * %s%s' "${genfun_indent}" "$*"
	fi
}

#
#    hard set the indent used for e-commands.
#    num defaults to 0
# This is a private function.
#
_esetdent()
{
	if ! is_int "$1" || [ "$1" -lt 0 ]; then
		set -- 0
	fi
	genfun_indent=$(printf "%${1}s" '')
}

#
#    increase the indent used for e-commands.
#
eindent()
{
	if ! is_int "$1" || [ "$1" -le 0 ]; then
		set -- 2
	fi
	_esetdent "$(( ${#genfun_indent} + $1 ))"
}

#
#    decrease the indent used for e-commands.
#
eoutdent()
{
	if ! is_int "$1" || [ "$1" -le 0 ]; then
		set -- 2
	fi
	_esetdent "$(( ${#genfun_indent} - $1 ))"
}

#
# this function was lifted from OpenRC. It returns 0 if the argument  or
# the value of the argument is "yes", "true", "on", or "1" or 1
# otherwise.
#
yesno()
{
	for _ in 1 2; do
		case $1 in
			[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|[Oo][Ff][Ff]|0|'')
				return 1
				;;
			[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|[Oo][Nn]|1)
				return 0
		esac
		if [ "$_" -gt 1 ]; then
			! break
		else
			# Using eval can be very dangerous. Check whether the
			# value is a legitimate variable name before proceeding
			# to treat it as one.
			(
				LC_ALL=C
				case $1 in
					''|_|[[:digit:]]*|*[!_[:alnum:]]*) exit 1
				esac
			) || ! break
			# Treat the value as a nameref then try again.
			eval "set -- \"\$$1\""
		fi
	done || vewarn "Invalid argument given to yesno (expected a boolean-like or a legal name)"
	return 1
}

#
#    use the system logger to log a message
#
esyslog()
{
	local pri tag msg

	if [ "$#" -lt 2 ]; then
		printf 'Too few arguments for esyslog (got %d, expected at least 2)\n' "$#" >&2
		return 1
	elif [ -n "${EINFO_LOG}" ] && hash logger 2>/dev/null; then
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
#    show an informative message (without a newline)
#
einfon()
{
	if ! yesno "${EINFO_QUIET}"; then
		_eprint "${GOOD}" "$@"
		genfun_lastcall="einfon"
	fi
}

#
#    show an informative message (with a newline)
#
einfo()
{
	einfon "$*
"
	genfun_lastcall="einfo"
}

#
#    show a warning message (without a newline) and log it
#
ewarnn()
{
	if ! yesno "${EINFO_QUIET}"; then
		_eprint "${WARN}" "$@" >&2
		esyslog "daemon.warning" "${0##*/}" "$@"
		genfun_lastcall="ewarnn"
	fi
}

#
#    show a warning message (with a newline) and log it
#
ewarn()
{
	ewarnn "$*
"
	genfun_lastcall="ewarn"
}

#
#    show an error message (without a newline) and log it
#
eerrorn()
{
	if ! yesno "${EERROR_QUIET}"; then
		_eprint "${BAD}" "$@" >&2
		esyslog "daemon.err" "${0##*/}" "$@"
		genfun_lastcall="eerrorn"
	fi
	return 1
}

#
#    show an error message (with a newline) and log it
#
eerror()
{
	eerrorn "$*
"
	genfun_lastcall="eerror"
	return 1
}

#
#    show a message indicating the start of a process
#
ebegin()
{
	local msg

	if ! yesno "${EINFO_QUIET}"; then
		msg="$* ..."
		_eprint "${GOOD}" "${msg}"
		if [ -n "${genfun_endcol}" ]; then
			printf '\n'
		fi
		genfun_lastbegun_strlen="$(( 3 + ${#genfun_indent} + ${#msg} ))"
		genfun_lastcall="ebegin"
	fi
}

#
#    indicate the completion of process, called from eend/ewend
#    if error, show errstr via efunc
#
#    This function is private to functions.sh.  Do not call it from a
#    script.
#
_eend()
{
	local cols efunc is_tty msg retval

	efunc=$1
	shift
	if [ "$#" -eq 0 ]; then
		retval=0
	elif ! is_int "$1" || [ "$1" -lt 0 ]; then
		printf 'Invalid argument given to %s (the exit status code must be an integer >= 0)\n' "${CALLER}" >&2
		retval=0
		shift
	else
		retval=$1
		shift
	fi

	if [ -t 1 ]; then
		is_tty=1
		cols=${genfun_cols}
	else
		# STDOUT is not currently a TTY. Therefore, the width of the
		# controlling terminal, if any, is irrelevant. For this call,
		# consider the number of columns as being 80.
		is_tty=0
		cols=80
	fi

	if [ "${retval}" -ne 0 ]; then
		# If a message was given, print it with the specified function.
		if _is_visible "$*"; then
			"${efunc}" "$*"
		fi
		# Generate an indicator for ebegin's unsuccessful conclusion.
		if [ "${is_tty}" -eq 0 ]; then
			msg="[ !! ]"
		else
			msg="${BRACKET}[ ${BAD}!!${BRACKET} ]${NORMAL}"
		fi
	elif yesno "${EINFO_QUIET}"; then
		return "${retval}"
	else
		# Generate an indicator for ebegin's successful conclusion.
		if [ "${is_tty}" -eq 0 ]; then
			msg="[ ok ]"
		else
			msg="${BRACKET}[ ${GOOD}ok${BRACKET} ]${NORMAL}"
		fi
	fi

	if [ "${is_tty}" -eq 1 ] && [ -n "${genfun_endcol}" ]; then
		printf '%s  %s\n' "${genfun_endcol}" "${msg}"
	else
		[ "${genfun_lastcall}" = ebegin ] || genfun_lastbegun_strlen=0
		printf "%$(( cols - genfun_lastbegun_strlen - 6 ))s%s\n" '' "${msg}"
	fi

	return "${retval}"
}

#
#    indicate the completion of process
#    if error, show errstr via eerror
#
eend()
{
	local retval

	CALLER=${CALLER:-eend} _eend eerror "$@"
	retval=$?
	genfun_lastcall="eend"
	return "${retval}"
}

#
#    indicate the completion of process
#    if error, show errstr via ewarn
#
ewend()
{
	local retval

	CALLER=${CALLER:-ewend} _eend ewarn "$@"
	retval=$?
	genfun_lastcall="ewend"
	return "${retval}"
}

# v-e-commands honor EINFO_VERBOSE which defaults to no.
veinfo()
{
	if yesno "${EINFO_VERBOSE}"; then
		einfo "$@"
	fi
}

veinfon()
{
	if yesno "${EINFO_VERBOSE}"; then
		einfon "$@"
	fi
}

vewarn()
{
	if yesno "${EINFO_VERBOSE}"; then
		ewarn "$@"
	fi
}

veerror()
{
	if yesno "${EINFO_VERBOSE}"; then
		eerror "$@"
	fi
}

vebegin()
{
	if yesno "${EINFO_VERBOSE}"; then
		ebegin "$@"
	fi
}

veend()
{
	if yesno "${EINFO_VERBOSE}"; then
		CALLER=veend eend "$@"
	elif [ "$#" -gt 0 ] && { ! is_int "$1" || [ "$1" -lt 0 ]; }; then
		printf 'Invalid argument given to veend (the exit status code must be an integer >= 0)\n' >&2
	else
		return "$1"
	fi
}

vewend()
{
	if yesno "${EINFO_VERBOSE}"; then
		CALLER=vewend ewend "$@"
	elif [ "$#" -gt 0 ] && { ! is_int "$1" || [ "$1" -lt 0 ]; }; then
		printf 'Invalid argument given to vewend (the exit status code must be an integer >= 0)\n' >&2
	else
		return "$1"
	fi
}

veindent()
{
	if yesno "${EINFO_VERBOSE}"; then
		eindent "$@"
	fi
}

veoutdent()
{
	if yesno "${EINFO_VERBOSE}"; then
		eoutdent "$@"
	fi
}

#
#   return 0 if gentoo=param was passed to the kernel
#
#   EXAMPLE:  if get_bootparam "nodevfs" ; then ....
#
get_bootparam()
(
	# Gentoo cmdline parameters are comma-delimited, so a search
	# string containing a comma must not be allowed to match.
	# Similarly, the empty string must not be allowed to match.
	case $1 in ''|*,*) return 1 ;; esac

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
#   return 0 if any of the files/dirs are newer than
#   the reference file
#
#   EXAMPLE: if is_older_than a.out *.o ; then ...
is_older_than()
{
	local ref has_gfind

	if [ "$#" -lt 2 ]; then
		printf 'Too few arguments for is_older_than (got %d, expected at least 2)\n' "$#" >&2
		return 1
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
#   Determine whether the first operand is in the form of an integer. A leading
#   <hypen-minus> shall be permitted. Thereafter, leading zeroes shall not be
#   permitted because the string might later be considered to be octal in an
#   arithmetic context, causing the shell to exit if the number be invalid.
#
is_int() {
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
#   Determine whether the first operand contains any visible characters. This
#   is intended to be a private function.
#
_is_visible() {
	! case $1 in *[[:graph:]]*) false ;; esac
}

# This is the main script, please add all functions above this point!

# Dont output to stdout?
EINFO_QUIET="${EINFO_QUIET:-no}"
EINFO_VERBOSE="${EINFO_VERBOSE:-no}"

# Should we use color?
RC_NOCOLOR="${RC_NOCOLOR:-no}"

# Can the terminal handle endcols? Begin by assuming not.
unset -v genfun_endcol

# Set the initial value for e-message indentation.
genfun_indent=

for arg in "$@" ; do
	case "${arg}" in
		# Lastly check if the user disabled it with --nocolor argument
		--nocolor|--nocolour|-nc|-C)
			RC_NOCOLOR="yes"
			break
			;;
	esac
done

# Define genfun_cols and genfun_endcol so that eend can line up the [ ok ].
# shellcheck disable=3044
if [ -n "${BASH}" ] && shopt -s checkwinsize 2>/dev/null; then
	# As is documented, running an external command will cause bash to set
	# the COLUMNS variable. This technique is effective for >=4.3, though
	# it requires for the checkwinsize shopt to be enabled. By default, it
	# is only enabled for >=5.0.
	/bin/true
fi
if is_int "${COLUMNS}" && [ "${COLUMNS}" -gt 0 ]; then
	# The value of COLUMNS was likely set by a shell such as bash or mksh.
	genfun_cols=${COLUMNS}
else
	# Try to use stty(1) to determine the number of columns. The use of the
	# size operand is not portable.
	genfun_cols=$(
		stty size 2>/dev/null | {
			if read -r _ cols _; then
				printf '%s\n' "${cols}"
			fi
		}
	)
	if ! is_int "${genfun_cols}" || [ "${genfun_cols}" -le 0 ]; then
		# Give up and assume 80 available columns.
		genfun_cols=80
	fi
fi

if [ -z "${genfun_endcol+set}" ]; then
	if hash tput 2>/dev/null; then
		genfun_endcol="$(tput cuu1)$(tput cuf $(( genfun_cols - 8 )) )"
	else
		genfun_endcol='\033[A\033['$(( genfun_cols - 8 ))'C'
	fi
fi

# Setup the colors so our messages all look pretty
if yesno "${RC_NOCOLOR}"; then
	unset -v BAD BRACKET GOOD HILITE NORMAL WARN
elif { hash tput && tput colors >/dev/null; } 2>/dev/null; then
	genfun_bold=$(tput bold) genfun_norm=$(tput sgr0)
	BAD="${genfun_norm}${genfun_bold}$(tput setaf 1)"
	BRACKET="${genfun_norm}${genfun_bold}$(tput setaf 4)"
	GOOD="${genfun_norm}${genfun_bold}$(tput setaf 2)"
	HILITE="${genfun_norm}${genfun_bold}$(tput setaf 6)"
	NORMAL="${genfun_norm}"
	WARN="${genfun_norm}${genfun_bold}$(tput setaf 3)"
	unset -v genfun_bold genfun_norm
else
	BAD=$(printf '\033[31;01m')
	BRACKET=$(printf '\033[34;01m')
	GOOD=$(printf '\033[32;01m')
	HILITE=$(printf '\033[36;01m')
	NORMAL=$(printf '\033[0m')
	WARN=$(printf '\033[33;01m')
fi

# vim:ts=4
