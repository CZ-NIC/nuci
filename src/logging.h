/*
 * Copyright 2013, CZ.NIC
 *
 * This file is part of NUCI configuration server.
 *
 * NUCI is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 * NUCI is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with NUCI.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef NUCI_LOGGING_H
#define NUCI_LOGGING_H

#include <stdarg.h>
#include <stdbool.h>

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
void die(const char *message, ...) __attribute__((format(printf, 1, 2))) __attribute__((noreturn));
bool would_log(enum log_level level);

void log_set_stderr(enum log_level from_level);
void log_set_syslog(enum log_level from_level);

enum log_level get_log_level(const char *name);

#endif
