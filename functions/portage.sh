# Copyright 2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# shellcheck shell=sh disable=3043

# This file contains alternative implementations for some of the functions and
# utilities provided by portage and its supporting eclasses. Please refer to
# ../functions.sh for coding conventions.

# The following variables affect initialisation and/or function behaviour.

# IFS              : multiple message operands are joined by its first character
# RC_GOT_FUNCTIONS : whether the rc module may be used for printing messages

#------------------------------------------------------------------------------#

#
# Prints a diagnostic message prefixed with the basename of the running script
# before exiting. It shall preserve the value of $? as it was at the time of
# invocation unless its value was 0, in which case the exit status shall be 1.
#
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

#
# Takes the positional parameters as the definition of a simple command then
# prints the command as an informational message with einfo before executing it.
# Should the command fail, a diagnostic message shall be printed and the shell
# be made to exit by calling the die function.
#
edo()
{
	genfun_cmd=$(quote_args "$@")
	if [ "${RC_GOT_FUNCTIONS}" ]; then
		einfo "Executing: ${genfun_cmd}"
	else
		printf 'Executing: %s\n' "${genfun_cmd}"
	fi
	"$@" || die "Failed to execute command: ${genfun_cmd}"
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
	if [ "${RC_GOT_FUNCTIONS}" ]; then
		ewarn "$@"
	else
		warn "$@"
	fi
}
