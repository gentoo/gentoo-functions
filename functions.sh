# Copyright 1999-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

#
# All functions in this file should be written in POSIX sh. Please do
# not use bashisms.
#

RC_GOT_FUNCTIONS="yes"

#
#    hard set the indent used for e-commands.
#    num defaults to 0
# This is a private function.
#
_esetdent()
{
	local i="$1"
	[ -z "$i" ] || [ "$i" -lt 0 ] && i=0
	RC_INDENTATION=$(printf "%${i}s" '')
}

#
#    increase the indent used for e-commands.
#
eindent()
{
	local i="$1"
	[ -n "$i" ] && [ "$i" -gt 0 ] || i=${RC_DEFAULT_INDENT}
	_esetdent $(( ${#RC_INDENTATION} + i ))
}

#
#    decrease the indent used for e-commands.
#
eoutdent()
{
	local i="$1"
	[ -n "$i" ] && [ "$i" -gt 0 ] || i=${RC_DEFAULT_INDENT}
	_esetdent $(( ${#RC_INDENTATION} - i ))
}

#
# this function was lifted from OpenRC. It returns 0 if the argument  or
# the value of the argument is "yes", "true", "on", or "1" or 1
# otherwise.
#
yesno()
{
	[ -z "$1" ] && return 1

	case "$1" in
		[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|[Oo][Nn]|1) return 0;;
		[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|[Oo][Ff][Ff]|0) return 1;;
	esac

	local value=
	eval "value=\$${1}"
	case "$value" in
		[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|[Oo][Nn]|1) return 0;;
		[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|[Oo][Ff][Ff]|0) return 1;;
		*) vewarn "\$$1 is not set properly"; return 1;;
	esac
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
		case ${msg} in
			*[[:graph:]]*)
				# This is not strictly portable because POSIX
				# defines no options whatsoever for logger(1).
				logger -p "${pri}" -t "${tag}" -- "${msg}"
		esac
	fi
}

#
#    show an informative message (without a newline)
#
einfon()
{
	if yesno "${EINFO_QUIET}"; then
		return 0
	fi
	if ! yesno "${RC_ENDCOL}" && [ "${LAST_E_CMD}" = "ebegin" ]; then
		printf "\n"
	fi
	printf " ${GOOD}*${NORMAL} ${RC_INDENTATION}$*"
	LAST_E_CMD="einfon"
	return 0
}

#
#    show an informative message (with a newline)
#
einfo()
{
	einfon "$*\n"
	LAST_E_CMD="einfo"
	return 0
}

#
#    show a warning message (without a newline) and log it
#
ewarnn()
{
	if yesno "${EINFO_QUIET}"; then
		return 0
	else
		if ! yesno "${RC_ENDCOL}" && [ "${LAST_E_CMD}" = "ebegin" ]; then
			printf "\n" >&2
		fi
		printf " ${WARN}*${NORMAL} ${RC_INDENTATION}$*" >&2
	fi

	# Log warnings to system log
	esyslog "daemon.warning" "${0##*/}" "$@"

	LAST_E_CMD="ewarnn"
	return 0
}

#
#    show a warning message (with a newline) and log it
#
ewarn()
{
	if yesno "${EINFO_QUIET}"; then
		return 0
	else
		if ! yesno "${RC_ENDCOL}" && [ "${LAST_E_CMD}" = "ebegin" ]; then
			printf "\n" >&2
		fi
		printf " ${WARN}*${NORMAL} ${RC_INDENTATION}$*\n" >&2
	fi

	# Log warnings to system log
	esyslog "daemon.warning" "${0##*/}" "$@"

	LAST_E_CMD="ewarn"
	return 0
}

#
#    show an error message (without a newline) and log it
#
eerrorn()
{
	if yesno "${EERROR_QUIET}"; then
		return 1
	else
		if ! yesno "${RC_ENDCOL}" && [ "${LAST_E_CMD}" = "ebegin" ]; then
			printf "\n" >&2
		fi
		printf " ${BAD}*${NORMAL} ${RC_INDENTATION}$*" >&2
	fi

	# Log errors to system log
	esyslog "daemon.err" "${0##*/}" "$@"

	LAST_E_CMD="eerrorn"
	return 1
}

#
#    show an error message (with a newline) and log it
#
eerror()
{
	if yesno "${EERROR_QUIET}"; then
		return 1
	else
		if ! yesno "${RC_ENDCOL}" && [ "${LAST_E_CMD}" = "ebegin" ]; then
			printf "\n" >&2
		fi
		printf " ${BAD}*${NORMAL} ${RC_INDENTATION}$*\n" >&2
	fi

	# Log errors to system log
	esyslog "daemon.err" "${0##*/}" "$@"

	LAST_E_CMD="eerror"
	return 1
}

#
#    show a message indicating the start of a process
#
ebegin()
{
	local msg="$*"
	if yesno "${EINFO_QUIET}"; then
		return 0
	fi

	msg="${msg} ..."
	einfon "${msg}"
	if yesno "${RC_ENDCOL}"; then
		printf "\n"
	fi

	LAST_E_LEN="$(( 3 + ${#RC_INDENTATION} + ${#msg} ))"
	LAST_E_CMD="ebegin"
	return 0
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
	local retval="${1:-0}" efunc="${2:-eerror}" msg
	shift 2

	if [ "${retval}" != "0" ]; then
		if [ -n "$*" ]; then
			"${efunc}" "$*"
		fi
		msg="${BRACKET}[ ${BAD}!!${BRACKET} ]${NORMAL}"
	elif yesno "${EINFO_QUIET}"; then
		return 0
	else
		msg="${BRACKET}[ ${GOOD}ok${BRACKET} ]${NORMAL}"
	fi

	if yesno "${RC_ENDCOL}"; then
		printf "${ENDCOL}  ${msg}\n"
	else
		[ "${LAST_E_CMD}" = ebegin ] || LAST_E_LEN=0
		printf "%$(( COLS - LAST_E_LEN - 6 ))s%b\n" '' "${msg}"
	fi

	return "${retval}"
}

#
#    indicate the completion of process
#    if error, show errstr via eerror
#
eend()
{
	local retval="${1:-0}"
	[ $# -eq 0 ] || shift

	_eend "${retval}" eerror "$*"

	LAST_E_CMD="eend"
	return "${retval}"
}

#
#    indicate the completion of process
#    if error, show errstr via ewarn
#
ewend()
{
	local retval="${1:-0}"
	[ $# -eq 0 ] || shift

	_eend "${retval}" ewarn "$*"

	LAST_E_CMD="ewend"
	return "${retval}"
}

# v-e-commands honor EINFO_VERBOSE which defaults to no.
# The condition is negated so the return value will be zero.
veinfo()
{
	yesno "${EINFO_VERBOSE}" && einfo "$@"
}

veinfon()
{
	yesno "${EINFO_VERBOSE}" && einfon "$@"
}

vewarn()
{
	yesno "${EINFO_VERBOSE}" && ewarn "$@"
}

veerror()
{
	yesno "${EINFO_VERBOSE}" && eerror "$@"
}

vebegin()
{
	yesno "${EINFO_VERBOSE}" && ebegin "$@"
}

veend()
{
	yesno "${EINFO_VERBOSE}" && { eend "$@"; return $?; }
	return "${1:-0}"
}

vewend()
{
	yesno "${EINFO_VERBOSE}" && { ewend "$@"; return $?; }
	return "${1:-0}"
}

veindent()
{
	yesno "${EINFO_VERBOSE}" && eindent
}

veoutdent()
{
	yesno "${EINFO_VERBOSE}" && eoutdent
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

	if [ -e "$1" ]; then
		ref=$1
	else
		ref=
	fi
	[ "$#" -gt 0 ] && shift

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
	read -r line
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

# This is the main script, please add all functions above this point!

# Dont output to stdout?
EINFO_QUIET="${EINFO_QUIET:-no}"
EINFO_VERBOSE="${EINFO_VERBOSE:-no}"

# Should we use color?
RC_NOCOLOR="${RC_NOCOLOR:-no}"
# Can the terminal handle endcols?
RC_ENDCOL="yes"

# Default values for e-message indentation and dots
RC_INDENTATION=''
RC_DEFAULT_INDENT=2
RC_DOT_PATTERN=''

# If either STDOUT or STDERR is not a tty, disable coloured output. A useful
# improvement for  the future would be to have the individual logging functions
# act as they should. For example, ewarn prints to STDOUT whereas eerror prints
# to STDERR. For now, this is a reasonable compromise.
if [ ! -t 1 ] || [ ! -t 2 ]; then
	RC_NOCOLOR="yes"
	RC_ENDCOL="no"
fi

for arg in "$@" ; do
	case "${arg}" in
		# Lastly check if the user disabled it with --nocolor argument
		--nocolor|--nocolour|-nc|-C)
			RC_NOCOLOR="yes"
			break
			;;
	esac
done

# Define COLS and ENDCOL so that eend can line up the [ ok ].
if [ -n "${BASH}" ] && shopt -s checkwinsize 2>/dev/null; then
	# As is documented, running an external command will cause bash to set
	# the COLUMNS variable. This technique is effective for >=4.3, though
	# it requires for the checkwinsize shopt to be enabled. By default, it
	# is only enabled for >=5.0.
	/bin/true
fi
if is_int "${COLUMNS}" && [ "${COLUMNS}" -gt 0 ]; then
	# The value of COLUMNS was likely set by a shell such as bash or mksh.
	COLS=${COLUMNS}
else
	# Try to use stty(1) to determine the number of columns. The use of the
	# size operand is not portable.
	COLS=$(
		stty size 2>/dev/null | {
			if read -r h w _; then
				printf '%s\n' "$w"
			fi
		}
	)
	if ! is_int "${COLS}" || [ "${COLS}" -le 0 ]; then
		# Give up and assume 80 available columns.
		COLS=80
	fi
fi

if ! yesno "${RC_ENDCOL}"; then
	ENDCOL=''
elif hash tput 2>/dev/null; then
	ENDCOL="$(tput cuu1)$(tput cuf $(( COLS - 8 )) )"
else
	ENDCOL='\033[A\033['$(( COLS - 8 ))'C'
fi

# Setup the colors so our messages all look pretty
if yesno "${RC_NOCOLOR}"; then
	unset -v BAD BRACKET GOOD HILITE NORMAL WARN
elif { hash tput && tput colors >/dev/null; } 2>/dev/null; then
	genfuncs_bold=$(tput bold) genfuncs_norm=$(tput sgr0)
	BAD="${genfuncs_norm}${genfuncs_bold}$(tput setaf 1)"
	BRACKET="${genfuncs_norm}${genfuncs_bold}$(tput setaf 4)"
	GOOD="${genfuncs_norm}${genfuncs_bold}$(tput setaf 2)"
	HILITE="${genfuncs_norm}${genfuncs_bold}$(tput setaf 6)"
	NORMAL="${genfuncs_norm}"
	WARN="${genfuncs_norm}${genfuncs_bold}$(tput setaf 3)"
	unset -v genfuncs_bold genfuncs_norm
else
	BAD=$(printf '\033[31;01m')
	BRACKET=$(printf '\033[34;01m')
	GOOD=$(printf '\033[32;01m')
	HILITE=$(printf '\033[36;01m')
	NORMAL=$(printf '\033[0m')
	WARN=$(printf '\033[33;01m')
fi

# vim:ts=4
