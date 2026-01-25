# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# shellcheck shell=sh disable=3043

# This file contains several internal functions pertaining to TTY handling.
# Please refer to ../functions.sh for coding conventions.

# The following variables affect initialisation and/or function behaviour.

# BASH             : whether bash-specific features may be employed
# BASHPID          : may be used by _update_columns() and _update_pid()
# COLUMNS          : may be used by _update_columns() to get the column count
# EPOCHREALTIME    : potentially used by _update_time() to get the time
# TERM             : used to detect dumb terminals

#------------------------------------------------------------------------------#

#
# Determines whether the terminal is a dumb one.
#
_has_dumb_terminal()
{
	! case ${TERM} in *dumb*) false ;; esac
}

#
# Considers the first parameter as a number of centiseconds and determines
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
	# shellcheck disable=3044
	if [ "${BASH}" ] && shopt -q checkwinsize; then
		genfun_bin_true=$(whenceforth -x true)
	fi

	_update_columns()
	{
		local IFS

		# Two optimisations are applied. Firstly, the rate at which
		# updates can be performed is throttled to intervals of half a
		# second. Secondly, if running on bash then the COLUMNS variable
		# may be gauged, albeit only in situations where doing so can be
		# expected to work reliably.
		# shellcheck disable=3028
		if from_portage; then
			# Python's pty module is broken. For now, expect for
			# portage to have exported COLUMNS to the environment.
			set -- 0 "${COLUMNS}"
		elif _should_throttle 50; then
			test "${genfun_cols}"
			return
		elif [ "${genfun_bin_true}" ] && [ "$$" = "${BASHPID}" ]; then
			# To execute the true binary is faster than stty(1).
			"${genfun_bin_true}"
			set -- 0 "${COLUMNS}"
		else
			# This use of stty(1) is portable as of POSIX-1.2024.
			IFS=' '
			# shellcheck disable=2046
			set -- $(stty size 2>/dev/null)
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
	# shellcheck disable=3028
	if [ "${BASH}" ] && [ "${EPOCHREALTIME}" != "${EPOCHREALTIME}" ]; then
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
	elif [ -f /proc/uptime ] && [ ! "${YASH_VERSION}" ]; then
		# Yash is blacklisted because it dies upon integer overflow.
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
	# shellcheck disable=2034
	if [ ! -t 0 ]; then
		genfun_tty=0
	elif _has_dumb_terminal || ! _update_columns; then
		genfun_tty=1
	else
		genfun_tty=2
	fi
}
