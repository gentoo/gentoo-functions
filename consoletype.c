/*
 * consoletype.c
 * simple app to figure out whether the current terminal
 * is serial, console (vt), or remote (pty).
 *
 * Copyright 1999-2007 Gentoo Foundation
 * Distributed under the terms of the GNU General Public License v2
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include "headers.h"

enum termtype {
	IS_VT = 0,
	IS_SERIAL = 1,
	IS_PTY = 2,
	IS_UNK = 3
};

const char * const tty_names[] = {
	"vt",
	"serial",
	"pty",
	"unknown"
};

static inline int check_ttyname(void)
{
	char *tty = ttyname(0);

	if (tty == NULL)
		return IS_UNK;

	if (strncmp(tty, "/dev/", 5) == 0)
		tty += 5;

	if (!strncmp (tty, "ttyS", 4) || !strncmp (tty, "cuaa", 4))
		return IS_SERIAL;
	else if (!strncmp (tty, "pts/", 4) || !strncmp (tty, "ttyp", 4))
		return IS_PTY;
	else if (!strncmp (tty, "tty", 3))
		return IS_VT;
	else
		return IS_UNK;
}

static inline int check_devnode(void)
{
#if defined(__linux__)
	int maj;
	struct stat sb;

	fstat(0, &sb);
	maj = major(sb.st_rdev);
	if (maj != 3 && (maj < 136 || maj > 143)) {
#if defined(TIOCLINUX)
		unsigned char twelve = 12;
		if (ioctl (0, TIOCLINUX, &twelve) < 0)
			return IS_SERIAL;
#endif
		return IS_VT;
	} else
		return IS_PTY;
#endif
	return IS_UNK;
}

int main(int argc, char *argv[])
{
	int rc;
	int type = check_ttyname();
	if (type == IS_UNK)
		type = check_devnode();
	puts(tty_names[type]);
	if (argc > 1 && strcmp(argv[1], "stdout") == 0)
		rc = 0;
	else
		rc = type;
	return rc;
}
