#ifndef NUCI_LOGGING_H
#define NUCI_LOGGING_H

#include <stdarg.h>

enum log_level {
	NLOG_DISABLE,
	NLOG_FATAL,
	NLOG_ERROR,
	NLOG_WARN,
	NLOG_INFO,
	NLOG_DEBUG,
	NLOG_TRACE
};

void nlog(enum log_level log_level, const char *format, ...) __attribute__((format(printf, 2, 3)));
void vnlog(enum log_level log_level, const char *format, va_list args);

void log_set_stderr(enum log_level from_level);
void log_set_syslog(enum log_level from_level);

#endif
