# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# shellcheck shell=sh disable=3043

# This file contains functions that pertain to TTY handling or that are useful
# where reading from or writing to a TTY. Please refer to ../functions.sh for
# coding conventions.

# The following variables affect initialisation and/or function behaviour.

# BASH             : whether bash-specific features may be employed
# COLUMNS          : may be used by _update_columns() to get the column count
# EPOCHREALTIME    : potentially used by _update_time() to get the time
# TERM             : used to detect dumb terminals

#------------------------------------------------------------------------------#

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

	# shellcheck disable=2154
	if [ "$#" -ge 2 ] && is_int "$2"; then
		length=$2
	elif _update_tty_level <&1; [ "${genfun_tty}" -eq 2 ]; then
		length=${genfun_cols}
	else
		length=80
	fi
	c=${1--}
	c=${c%"${c#?}"}
	hr=
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
# Determines whether the terminal is a dumb one.
#
_has_dumb_terminal()
{
	! case ${TERM} in *dumb*) false ;; esac
}

#
# Considers the first parameter as a number of milliseconds and determines
# whether fewer have elapsed since the last occasion on which the function was
# called, or whether the last genfun_time update resulted in integer overflow.
#
_should_throttle()
{
	_update_time || return

	# shellcheck disable=2329
	_should_throttle()
	{
		_update_time || return
		if [ "$(( (genfun_time < 0 && genfun_last_time >= 0) || genfun_time - genfun_last_time > $1 ))" -eq 1 ]
		then
			genfun_last_time=${genfun_time}
			false
		fi

	}

	genfun_last_time=${genfun_time}
	false
}

#
# Determines whether the terminal on STDIN is able to report its dimensions.
# Upon success, the number of columns shall be stored in genfun_cols.
#
_update_columns()
{
	local IFS

	if from_portage; then
		# Python's pty module is broken. For now, expect for portage to
		# have exported COLUMNS to the environment.
		set -- 0 "${COLUMNS}"
	elif _should_throttle 1000 && [ "${genfun_cols}" ]; then
		# Preserve the cached number of columns for up to 1 second.
		return
	else
		IFS=' '
		# shellcheck disable=2046
		set -- $(stty size 2>/dev/null)
	fi
	[ "$#" -eq 2 ] && is_int "$2" && [ "$2" -gt 0 ] && genfun_cols=$2
}

#
# Determines either the number of milliseconds elapsed since the unix epoch or
# the approximate number of milliseconds that the operating system has been
# online, depending on the capabilities of the shell and/or platform. Upon
# success, the number shall be assigned to genfun_time. Otherwise, the return
# value shall be greater than 0.
#
_update_time()
{
	# shellcheck disable=3028
	if [ "${BASH}" ] && [ "${EPOCHREALTIME}" != "${EPOCHREALTIME}" ]; then
		eval '
			_update_time() {
				local s

				s=${EPOCHREALTIME}
				genfun_time=${s:0:-7}${s: -6:3}
			}
		'
	elif [ -f /proc/uptime ] && [ ! "${YASH_VERSION}" ]; then
		# Yash is blacklisted because it dies upon integer overflow.
		_update_time()
		{
			local cs s

			IFS='. ' read -r s cs _ < /proc/uptime \
			&& genfun_time=${s}${cs}0
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
	# shellcheck disable=2034
	if [ ! -t 0 ]; then
		genfun_tty=0
	elif _has_dumb_terminal || ! _update_columns; then
		genfun_tty=1
	else
		genfun_tty=2
	fi
}
