#include "logging.h"

#include <stdio.h>
#include <stdlib.h>
#include <syslog.h>
#include <strings.h>

static enum log_level stderr_level = NLOG_INFO, syslog_level = NLOG_WARN;

static const char *names[] = {
	[NLOG_FATAL] = "\x1b[31mFATAL\x1b[0m: ",
	[NLOG_ERROR] = "\x1b[31mERROR\x1b[0m: ",
	[NLOG_WARN]  = "\x1b[35mWARN\x1b[0m:  ",
	[NLOG_INFO]  = "\x1b[34mINFO\x1b[0m:  ",
	[NLOG_DEBUG] = "DEBUG: ",
	[NLOG_TRACE] = "TRACE: "
};

static int syslog_prios[] = {
	[NLOG_FATAL] = LOG_CRIT,
	[NLOG_ERROR] = LOG_ERR,
	[NLOG_WARN] = LOG_WARNING,
	[NLOG_INFO] = LOG_INFO,
	[NLOG_DEBUG] = LOG_DEBUG,
	[NLOG_TRACE] = LOG_DEBUG
};

void vnlog(enum log_level log_level, const char *format, va_list args) {
	bool log_stderr = log_level <= stderr_level;
	bool log_syslog = log_level <= syslog_level;
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

	if (log_syslog)
		syslog(LOG_MAKEPRI(LOG_DAEMON, syslog_prios[log_level]), "%s", message);
	free(message);
}

void nlog(enum log_level log_level, const char *format, ...) {
	va_list args;
	va_start(args, format);
	vnlog(log_level, format, args);
	va_end(args);
}

void die(const char *format, ...) {
	va_list args;
	va_start(args, format);
	vnlog(NLOG_FATAL, format, args);
	va_end(args);
	abort();
}

void log_set_stderr(enum log_level level) {
	stderr_level = level;
}

void log_set_syslog(enum log_level level) {
	syslog_level = level;
}

struct level_name {
	const char *name;
	enum log_level level;
};

static struct level_name level_names[] = {
	{ "trace", NLOG_TRACE },
	{ "debug", NLOG_DEBUG },
	{ "info", NLOG_INFO },
	{ "warning", NLOG_WARN },
	{ "warn", NLOG_WARN },
	{ "error", NLOG_ERROR },
	{ "fatal", NLOG_FATAL },
	{ "critical", NLOG_FATAL },
	{ "off", NLOG_DISABLE },
	{ "disable", NLOG_DISABLE },
	{ "disabled", NLOG_DISABLE },
	{ NULL }
};

enum log_level get_log_level(const char *name) {
	for (const struct level_name *level = level_names; level; level ++)
		if (strcasecmp(name, level->name) == 0)
			return level->level;
	die("Log level %s not recognized", name);
}

bool would_log(enum log_level level) {
	return (level <= stderr_level) || (level <= syslog_level);
}
