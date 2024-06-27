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
# Returns 0 provided that two conditions hold. Firstly, that the standard input
# is connected to a tty. Secondly, that the standard output has not been closed.
# This technique is loosely based on the IO::Interactive::Tiny module from CPAN.
#
is_interactive()
{
	test -t 0 && { true 3>&1; } 2>/dev/null
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
