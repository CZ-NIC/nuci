/*
 * Copyright 2013, CZ.NIC z.s.p.o. (http://www.nic.cz/)
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

#ifndef COMMUNICATION_H
#define COMMUNICATION_H

#include <stdbool.h>
#include <stddef.h>

struct interpreter;
struct datastore;
struct stats_mapping;
struct nuci_lock_info;

/*
 * Holds server configuration
 */
struct srv_config {
	// The lua interpreter
	struct interpreter *interpreter;
	// Lock info (to be freed at the end)
	struct nuci_lock_info *lock_info;
	// The session (connection) to the client.
	struct nc_session *session;
	// The configuration data store.
	struct datastore *config_datastores;
	size_t config_datastore_count;
};

extern struct srv_config global_srv_config;

void comm_set_print_error_callback(void(*clb)(const char *message));
bool comm_init(struct srv_config *config_out, struct interpreter *interpreter);
void comm_start_loop(const struct srv_config *config);
void comm_cleanup(struct srv_config *config);

#endif // COMMUNICATION_H
