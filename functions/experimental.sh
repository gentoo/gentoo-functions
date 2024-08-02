# Copyright 2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# shellcheck shell=sh disable=3043

# This file contains functions considered experimental in nature. Any functions
# defined here may eventually be promoted to the core library or to a distinct
# module. They may also be dropped without warning, either because they were
# not considered as being sufficiently within the scope of gentoo-functions as
# a project or because they were deemed to be insufficiently useful. As such, it
# serves as a staging ground for new ideas. Note that GENFUN_API_LEVEL must
# never be incremented on account of any changes made to this module.

warn "sourcing the experimental module from gentoo-functions; no stability guarantee is provided"

#
# Considers the first parameter as an URL then attempts to fetch it with either
# curl(1) or wget(1). If the URL does not contain a scheme then the https://
# scheme shall be presumed. Both utilities shall be invoked in a manner that
# suppresses all output unless an error occurs, and whereby HTTP redirections
# are honoured. Upon success, the body of the response shall be printed to the
# standard output. Otherwise, the return value shall be greater than 0.
#
fetch()
{
	if hash curl 2>/dev/null; then
		fetch()
		{
			if [ "$#" -gt 0 ]; then
				# Discard any extraneous parameters.
				set -- "$1"
			fi
			curl -f -sS -L --connect-timeout 10 --proto-default https -- "$@"
		}
	elif hash wget 2>/dev/null; then
		fetch()
		{
			if [ "$#" -gt 0 ]; then
				# Discard any extraneous parameters.
				case $1 in
					''|ftp://*|ftps://*|https://*)
						set -- "$1"
						;;
					*)
						set -- "https://$1"
				esac
			fi
			wget -nv -O - --connect-timeout 10 -- "$@"
		}
	else
		warn "fetch: this function requires that curl or wget be installed"
		return 127
	fi

	fetch "$@"
}

#
# Expects three parameters, all of which must be integers, and determines
# whether the first is numerically greater than or equal to the second, and
# numerically lower than or equal to the third.
#
int_between()
{
	if [ "$#" -lt 3 ]; then
		warn "int_between: too few arguments (got $#, expected 3)"
		false
	elif ! is_int "$2" || ! is_int "$3"; then
		_warn_for_args int_between "$@"
		false
	else
		is_int "$1" && [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]
	fi
}

#
# Returns 0 provided that two conditions hold. Firstly, that the standard input
# is connected to a tty. Secondly, that the standard output has not been closed.
# This technique is loosely based on the IO::Interactive::Tiny module from CPAN.
#
is_interactive()
{
	test -t 0 && { true 3>&1; } 2>/dev/null
}

#
# Collects the intersection of the parameters up to - but not including - a
# sentinel value then determines whether the resulting set is a subset of the
# intersection of the remaining parameters. If the SENTINEL variable is set, it
# shall be taken as the value of the sentinel. Otherwise, the value of the
# sentinel shall be defined as <hyphen-dash><hyphen-dash>. If the sentinel value
# is not encountered or if either set is empty then the return value shall be
# greater than 1.
#
is_subset()
{
	SENTINEL=${SENTINEL-'--'} awk -f - -- "$@" <<-'EOF'
	BEGIN {
		argc = ARGC
		ARGC = 1
		for (i = 1; i < argc; i++) {
			word = ARGV[i]
			if (word == ENVIRON["SENTINEL"]) {
				break
			} else {
				set1[word]
			}
		}
		if (i == 1 || argc - i < 2) {
			exit 1
		}
		for (i++; i < argc; i++) {
			word = ARGV[i]
			set2[word]
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
# Continuously reads lines from the standard input, prepending each with a
# timestamp before printing to the standard output. Timestamps shall be in the
# format of "%FT%T%z", per strftime(3). Output buffering shall not be employed.
#
prepend_ts()
{
	if hash gawk 2>/dev/null; then
		prepend_ts()
		{
			gawk '{ print strftime("%FT%T%z"), $0; fflush(); }'
		}
	elif hash ts 2>/dev/null; then
		prepend_ts()
		{
			ts '%FT%T%z'
		}
	elif bash -c '(( BASH_VERSINFO >= 4 ))' 2>/dev/null; then
		prepend_ts()
		{
			bash -c 'while read -r; do printf "%(%FT%T%z)T %s\n" -1 "${REPLY}"; done'
		}
	else
		warn "prepend_ts: this function requires that either bash, gawk or moreutils be installed"
		return 1
	fi

	prepend_ts
}

#
# Expects three parameters and determines whether the first is lexicographically
# greater than or equal to the second, and lexicographically lower than or equal
# to the third. The effective system collation shall affect the results, given
# the involvement of the sort(1) utility.
#
str_between()
{
	local i

	if [ "$#" -ne 3 ]; then
		warn "str_between: wrong number of arguments (got $#, expected 3)"
		false
	else
		set -- "$2" "$1" "$3"
		i=0
		printf '%s\n' "$@" |
		sort |
		while IFS= read -r line; do
			eval "[ \"\${line}\" = \"\$$(( i += 1 ))\" ]" || ! break
		done
	fi
}

#
# Takes the first parameter as a string (s), the second parameter as a numerical
# position (m) and, optionally, the third parameter as a numerical length (n).
# It shall then print a <newline> terminated substring of s that is at most, n
# characters in length and which begins at position m, numbering from 1. If n is
# omitted, or if n specifies more characters than are left in the string, the
# length of the substring shall be limited by the length of s. The function
# shall return 0 provided that none of the parameters are invalid.
#
substr()
{
	local i str

	if [ "$#" -lt 2 ]; then
		warn "substr: too few arguments (got $#, expected at least 2)"
		return 1
	elif ! is_int "$2"; then
		_warn_for_args substr "$2"
		return 1
	elif [ "$#" -ge 3 ]; then
		if ! is_int "$3"; then
			_warn_for_args substr "$3"
			return 1
		elif [ "$3" -lt 0 ]; then
			set -- "$1" "$2" 0
		fi
	fi
	str=$1
	i=0
	while [ "$(( i += 1 ))" -lt "$2" ]; do
		str=${str#?}
	done
	i=0
	while [ "${#str}" -gt "${3-${#str}}" ]; do
		str=${str%?}
	done
	if [ "${#str}" -gt 0 ]; then
		printf '%s\n' "${str}"
	fi
}

#
# Takes the first parameter as either a relative pathname or an integer
# referring to a number of iterations. To be recognised as a pathname, the first
# four characters must form the special prefix, ".../". It recurses upwards from
# the current directory until either the relative pathname is found to exist,
# the specified number of iterations has occurred, or the root directory is
# encountered. In the event that the root directory is reached without either of
# the first two conditions being satisfied, the return value shall be 1.
# Otherwise, the value of PWD shall be printed to the standard output.
#
up()
{
	local i

	i=0
	while [ "${PWD}" != / ]; do
		chdir ../
		case $1 in
			.../*)
				test -e "${1#.../}"
				;;
			*)
				test "$(( i += 1 ))" -eq "$1"
		esac \
		&& pwd && return
	done
}
