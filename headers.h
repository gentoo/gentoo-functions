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
#if defined(__GLIBC__) || defined(__CYGWIN__)
# define HAVE_SYS_SYSMACROS_H
# define HAVE_ERROR_H
#endif

#if !defined(_WIN32)
# define HAVE_UNISTD_H
# define HAVE_SYS_IOCTL_H
# define HAVE_TTYNAME
#endif

/* Now we actually include crap ;) */
#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif
#ifdef HAVE_ERROR_H
# include <error.h>
#endif
#ifdef HAVE_SYS_IOCTL_H
# include <sys/ioctl.h>
#endif
#ifdef HAVE_SYS_SYSMACROS_H
# include <sys/sysmacros.h>
#endif

#if defined(__GNUC_STDC_INLINE__) && (__GNUC_STDC_INLINE__ - 0)
# define inline inline
#else
# define inline
#endif
