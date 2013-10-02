#include "logging.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

static enum log_level stderr_level = NLOG_INFO, syslog_level = NLOG_WARN;

static const char *names[] = {
	[NLOG_FATAL] = "\x1b[31mFATAL\x1b[0m: ",
	[NLOG_ERROR] = "\x1b[31mERROR\x1b[0m: ",
	[NLOG_WARN]  = "\x1b[35mWARN\x1b[0m:  ",
	[NLOG_INFO]  = "\x1b[34mINFO\x1b[0m:  ",
	[NLOG_DEBUG] = "DEBUG: ",
	[NLOG_TRACE] = "TRACE: "
};

void vnlog(enum log_level log_level, const char *format, va_list args) {
	bool log_stderr = log_level >= stderr_level;
	bool log_syslog = log_level >= syslog_level;
	if (!log_stderr && !log_syslog)
		return; // Don't do the formatting if we don't log anything.
	// Format the message
	va_list copy;
	va_copy(copy, args);
	int size = vsnprintf(NULL, 0, format, copy);
	va_end(copy);
	char *message = malloc(size + 1);
	va_copy(copy, args);
	vsnprintf(message, size + 1, format, copy);
	va_end(copy);
	if (log_stderr)
		fprintf(stderr, "%s%s\n", names[log_level], message);
	free(message);
}

void nlog(enum log_level log_level, const char *format, ...) {
	va_list args;
	va_start(args, format);
	vnlog(log_level, format, args);
	va_end(args);
}
