#ifndef COMMUNICATION_H
#define COMMUNICATION_H

#include <stdbool.h>
#include <libnetconf.h>

/**
 * @brief Holds server configuration
 */
struct srv_config {
	struct nc_session *session; ///<Session ID
	ncds_id dsid; ///< Working Datastore's datastore ID
	struct ncds_ds *datastore; ///<Datastore handler
};

void comm_set_print_error_callback(void(*clb)(const char *message));
bool comm_init(const char *datastore_model_path, struct srv_config *config_out);
void comm_start_loop(const struct srv_config *config);
void comm_cleanup(const struct srv_config *config);

#endif // COMMUNICATION_H
