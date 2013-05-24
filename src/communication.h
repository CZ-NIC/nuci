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
	// The statistics data stores
	struct datastore *stats_datastores;
	struct stats_mapping *stats_mappings;
	size_t stats_datastore_count;
};

extern struct srv_config global_srv_config;

void comm_set_print_error_callback(void(*clb)(const char *message));
bool comm_init(const char *config_model_path, struct srv_config *config_out, struct interpreter *interpreter);
void comm_start_loop(const struct srv_config *config);
void comm_cleanup(struct srv_config *config);

#endif // COMMUNICATION_H
