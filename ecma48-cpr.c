/*
 * ecma48-cpr.c
 * Treat STDIN as a tty and report the cursor position using the CPR sequence.
 *
 * Originally distributed as wsize.c by Stephen J. Friedl <steve@unixwiz.net>.
 * Repurposed for gentoo-functions by Kerin F. Millar <kfm@plushkava.net>.
 * This software is in the public domain.
 */

#define _POSIX_C_SOURCE 200809L

#define PROGRAM "ecma48-cpr"
#define READ_TIMEOUT_NS 250000000
#define BUFSIZE 100
#define MAX_LOOPS 20

#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

static struct termios save_tty;
static bool is_timed_out = false;
static bool is_tty_saved = false;

static void cleanup(void);
static void die(char const * const errmsg);
static void on_signal(int const signo);

#ifndef __APPLE__
static timer_t init_timer(void);
#endif

int
main(void) {
	/*
	 * Establish that STDIN is a terminal.
	 */
	if (! isatty(STDIN_FILENO)) {
		die("cannot determine the cursor position because stdin is not a tty");
	}

	/*
	 * Duplicate STDIN to a new file descriptor before reopening it as a
	 * writeable stream.
	 */
	int fd = dup(STDIN_FILENO);
	FILE *tty;
	if (fd < 0) {
		die("failed to dup stdin");
	} else {
		tty = fdopen(fd, "w");
		if (tty == NULL) {
			die("failed to re-open the tty for writing");
		}
	}

	/*
	 * Save the current terminal settings.
	 */
	if (tcgetattr(STDIN_FILENO, &save_tty) != 0) {
		die("failed to obtain the current terminal settings");
	} else {
		is_tty_saved = true;
	}

	/*
	 * Duplicate the current terminal settings for modification.
	 */
	struct termios new_tty = save_tty;
	new_tty = save_tty;

	/*
	 * Turn off ECHO, so that the response from the terminal isn't printed.
	 * Also, the terminal must be operating in its noncanonical mode,
	 * thereby ensuring that its input is always immediately available,
	 * with no processing having been performed.
	 */
	new_tty.c_lflag &= ~(ECHO|ECHOE|ECHOK|ECHONL);
	new_tty.c_lflag &= ~(ICANON);

	/*
	 * Set an interbyte timeout of 1 decisecond. The timer is started only
	 * after the first byte is read, so read(2) will block until then.
	 */
	new_tty.c_cc[VMIN]  = 1;
	new_tty.c_cc[VTIME] = 1;

	/*
	 * Try to apply the new terminal settings.
	 */
	if (tcsetattr(STDIN_FILENO, TCSANOW, &new_tty) != 0) {
		die("failed to modify the terminal settings");
	} else if (tcflush(STDIN_FILENO, TCIFLUSH) != 0) {
		die("failed to flush the terminal's input queue");
	} else if (fprintf(tty, "\033[6n") != 4) {
		die("failed to write the CPR sequence to the terminal");
	} else if (fclose(tty) != 0) {
		die("failed to flush the stream after writing the CPR sequence");
	}

	/*
	 * Prepare to catch our signals. We treat both an interrupt and a
	 * depleted timer as essentially the same thing: fatal errors.
	 */
	struct sigaction act;
	act.sa_handler = on_signal;
	sigemptyset(&act.sa_mask);
	act.sa_flags = 0;
	sigaction(SIGALRM, &act, NULL);

	/*
	 * A timeout is required, just in case read(2) proves unable to read an
	 * initial byte, otherwise causing the program to hang.
	 */
#ifdef __APPLE__
	alarm(1);
#else
	timer_t timerid = init_timer();
#endif

	/*
	 * Read up to (sizeof ibuf - 1) bytes of input in total. Upon each
	 * successful read, scan the input buffer for a valid ECMA4-8 CPR
	 * response. Abort if no such response is found within MAX_LOOPS
	 * iterations.
	 */
	char ibuf[BUFSIZE];
	char const * const imax = ibuf + sizeof ibuf - 1;
	char *iptr = ibuf;
	int maxloops = MAX_LOOPS;
	int row = -1;
	int col = -1;
	ssize_t nr;
	while (--maxloops > 0 && (nr = read(STDIN_FILENO, iptr, imax - iptr)) > 0) {
		iptr += nr;
		*iptr = '\0'; /* NUL-terminate for strchr(3) and sscanf(3) */
		char const *p;
		if ((p = strchr(ibuf, '\033')) != 0) {
			if (sscanf(p, "\033[%d;%dR", &row, &col) == 2) {
				break;
			} else {
				col = -1;
				row = -1;
			}
		}
	}

	/*
	 * Deactivate the timer.
	 */
#ifdef __APPLE__
	alarm(0);
#else
	timer_delete(timerid);
#endif

	/*
	 * Die in the case that the timer fired.
	 */
	if (is_timed_out) {
		die("timed out waiting for the terminal to respond to CPR");
	}

	/*
	 * Restore the original terminal settings.
	 */
	cleanup();

	/*
	 * Print the cursor position, provided both col and row are above zero.
	 */
	if (col < 1 || row < 1) {
		die("failed to read the cursor position");
	} else if (printf("%d %d\n", row, col) == -1 || fflush(stdout) == EOF) {
		return EXIT_FAILURE;
	} else {
		return EXIT_SUCCESS;
	}
}

#ifndef __APPLE__
static timer_t
init_timer(void) {
	struct itimerspec timer;
	struct sigevent event;
	timer_t timerid;
	event.sigev_notify = SIGEV_SIGNAL;
	event.sigev_signo = SIGALRM;
	event.sigev_value.sival_ptr = &timerid;
	if (timer_create(CLOCK_REALTIME, &event, &timerid) == -1) {
		die("failed to create a per-process timer");
	} else {
		timer.it_value.tv_sec = 0;
		timer.it_value.tv_nsec = READ_TIMEOUT_NS;
		timer.it_interval.tv_sec = 0;
		timer.it_interval.tv_nsec = 0;
		if (timer_settime(timerid, 0, &timer, NULL) == -1) {
			die("failed to configure the per-process timer");
		}
	}
	return timerid;
}
#endif

/*
 * Tries to restore the terminal settings. Only one attempt will ever be made.
 */
static void
cleanup(void) {
	bool const is_saved = is_tty_saved;
	if (is_saved) {
		tcsetattr(STDIN_FILENO, TCSANOW, &save_tty);
		is_tty_saved = false;
	}
}

static void
die(char const * const errmsg) {
	cleanup();
	fprintf(stderr, "%s: %s\n", PROGRAM, errmsg);
	exit(EXIT_FAILURE);
}

static void
on_signal(int const signo) {
	is_timed_out = true;
}
