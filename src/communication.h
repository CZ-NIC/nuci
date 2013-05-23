#ifndef COMMUNICATION_H
#define COMMUNICATION_H

#include <stdbool.h>
#include <libnetconf.h>

struct interpreter;

// One data store
struct datastore {
	ncds_id id;
	struct ncds_ds *datastore;
};

struct stats_mapping;

/*
 * Holds server configuration
 */
struct srv_config {
	// The session (connection) to the client.
	struct nc_session *session;
	// The configuration data store.
	struct datastore config_ds;
	// The statistics data stores
	struct datastore *stats_datastores;
	struct stats_mapping *stats_mappings;
	size_t stats_datastore_count;
};

void comm_set_print_error_callback(void(*clb)(const char *message));
bool comm_init(const char *config_model_path, const char *stats_model_path, struct srv_config *config_out, struct interpreter *interpreter);
void comm_start_loop(const struct srv_config *config);
void comm_cleanup(struct srv_config *config);

#endif // COMMUNICATION_H
