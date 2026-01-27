/*
 * shquote - intelligently quotes arguments for use as shell input
 *
 * SPDX-License-Identifier: MIT
 *
 * This software is derived from Leah Neukirchen's lr utility.
 */

/*
 * Copyright (C) 2025 Kerin Millar
 * Copyright (C) 2015-2025 Leah Neukirchen <purl.org/net/chneukirchen>
 * Parts of code derived from musl libc, which is
 * Copyright (C) 2005-2014 Rich Felker, et al.
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#define _POSIX_C_SOURCE 200809L

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static int esc_mode = 2;

static void print_shquoted(const char *s);
static int u8decode(const char *cs, uint32_t *cp);

int
main(int argc, char *argv[])
{
	char *var = getenv("POSIXLY_CORRECT");
	if (var != NULL && strlen(var))
		/* Disallow dollar-single quoting. */
		esc_mode = 1;

	for (int i = 1; i < argc; i++) {
		if (i > 1)
			putchar(' ');
		print_shquoted(argv[i]);
	}
	putchar('\n');
	return 0;
}

static void
print_shquoted(const char *s)
{
	uint32_t ignored;
	int l;

	const char *t;
	int esc = 0;

	for (t = s; *t; ) {
		if ((unsigned char)*t < 32 || strchr("'\177", *t)) {
			esc = esc_mode;
			break;
		} else if (strchr("`^#*[]=|\\?${}()\"<>&;~\040", *t)) {
			/* Bias towards single quoting. */
			esc = 1;
			if (esc == esc_mode)
				break;
			t += 1;
		} else {
			if ((l = u8decode(t, &ignored)) < 0) {
				/* Invalid UTF-8 byte sequence encountered. */
				esc = esc_mode;
				break;
			}
			t += l;
		}
	}

	switch (esc) {
	case 0:
		/* Convey verbatim. */
		printf("%s", s);
		break;
	case 1:
		/* Employ single quoting. */
		putchar('\'');
		for (; *s; s++)
			if (*s == '\'')
				printf("'\\''");
			else
				putchar(*s);
		putchar('\'');
		break;
	case 2:
		/* Employ dollar-single quoting. */
		printf("$'");
		for (; *s; s++)
			switch (*s) {
			case '\a': printf("\\a"); break;
			case '\b': printf("\\b"); break;
			case '\e': printf("\\e"); break;
			case '\f': printf("\\f"); break;
			case '\n': printf("\\n"); break;
			case '\r': printf("\\r"); break;
			case '\t': printf("\\t"); break;
			case '\v': printf("\\v"); break;
			case '\\': printf("\\\\"); break;
			case '\'': printf("\\\'"); break;
			default:
				if ((unsigned char)*s < 32
					|| (unsigned char)*s == 127
					|| (l = u8decode(s, &ignored)) < 0) {
					printf("\\%03o", (unsigned char)*s);
				} else {
					printf("%.*s", l, s);
					s += l-1;
				}
			}
		putchar('\'');
	}
}

/* Decode one UTF-8 codepoint into cp, return number of bytes to next one.
 * On invalid UTF-8, return -1, and do not change cp.
 * Invalid codepoints are not checked.
 *
 * This code is meant to be inlined, if cp is unused it can be optimized away.
 */
static int
u8decode(const char *cs, uint32_t *cp)
{
	const uint8_t *s = (uint8_t *)cs;

	if (*s == 0)   { *cp = 0; return 0; }
	if (*s < 0x80) { *cp = *s; return 1; }
	if (*s < 0xc2) { return -1; }  /*cont+overlong*/
	if (*s < 0xe0) { *cp = *s & 0x1f; goto u2; }
	if (*s < 0xf0) {
		if (*s == 0xe0 && (s[1] & 0xe0) == 0x80) return -1; /*overlong*/
		if (*s == 0xed && (s[1] & 0xe0) == 0xa0) return -1; /*surrogate*/
		*cp = *s & 0x0f; goto u3;
	}
	if (*s < 0xf5) {
		if (*s == 0xf0 && (s[1] & 0xf0) == 0x80) return -1; /*overlong*/
		if (*s == 0xf4 && (s[1] > 0x8f)) return -1; /*too high*/
		*cp = *s & 0x07; goto u4;
	}
	return -1;

u4:	if ((*++s & 0xc0) != 0x80) return -1;  *cp = (*cp << 6) | (*s & 0x3f);
u3:	if ((*++s & 0xc0) != 0x80) return -1;  *cp = (*cp << 6) | (*s & 0x3f);
u2:	if ((*++s & 0xc0) != 0x80) return -1;  *cp = (*cp << 6) | (*s & 0x3f);
	return s - (uint8_t *)cs + 1;
}
