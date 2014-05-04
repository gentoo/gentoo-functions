/*
 * header.h
 * Dirty little file to include header files w/out autotools.
 *
 * Copyright 1999-2007 Gentoo Foundation
 * Distributed under the terms of the GNU General Public License v2
 */

/* Common includes */
#define HAVE_TIOCNOTTY
#define HAVE_SETSID

/* OS-specific includes */
#if defined(__GLIBC__)
# define HAVE_SYS_SYSMACROS_H
# define HAVE_ERROR_H
#endif

/* Now we actually include crap ;) */
#ifdef HAVE_ERROR_H
# include <error.h>
#endif
#ifdef HAVE_SYS_SYSMACROS_H
# include <sys/sysmacros.h>
#endif
