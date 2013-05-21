#include "communication.h"
#include "nuci_datastore.h"
#include "register.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libnetconf.h>
#include <libnetconf/datastore_custom.h>

/**
 * @brief Message & reply
 */
struct rpc_communication {
	nc_rpc *msg; // Incoming message
	nc_reply *reply; // Reply to send
};

static void(*clb_print_error)(const char *message) = NULL;

static void clb_print_error_default(const char *message) {
	fprintf(stderr, "Module Communication Error:\n %s\n", message);
}

static void comm_test_values(void) {
	if (clb_print_error == NULL) {
		clb_print_error = clb_print_error_default;
	}
}

void comm_set_print_error_callback(void(*clb)(const char *message)) {
	clb_print_error = clb;
}

static bool config_ds_init(const char *datastore_model_path, struct srv_config *config) {
	// Create a data store. The thind parameter is NULL, so <get> returns the same as
	// <get-config> in this data store.
	config->config_datastore = ncds_new(NCDS_TYPE_CUSTOM, datastore_model_path, NULL);

	if (config->config_datastore == NULL) {
		clb_print_error("Datastore preparing failed.");
		return false;
	}

	// Set the callbacks
	if (ncds_custom_set_data(config->config_datastore, nuci_ds_get_custom_data(), ds_funcs) != 0) {
		clb_print_error("Linking datastore with functions.");
		return false;
	}

	// Activate datastore structure for use.
	config->config_dsid = ncds_init(config->config_datastore);
	if (config->config_dsid <= 0) { //Optionally: ncds_init has 4 different error return types
		clb_print_error("Couldn't activate the config data store.");
		return false;
	}

	return true;
}

static struct interpreter *interpreter;

static char *get_stats(const char *model, const char *running, struct nc_err **e) {
	(void) model;
	(void) running;
	(void) e;
	// Get all the results of the generators
	size_t result_count;
	char **results = register_call_stats_generators(&result_count, interpreter);
	size_t len = 0;
	// Compute how much space we need for the whole data
	for (size_t i = 0; i < result_count; i ++)
		len += strlen(results[i]);
	// Get the result
	char *result = malloc(len + 1);
	// Concatenate the results together and free the separate results
	result[0] = '\0';
	for (size_t i = 0; i < result_count; i ++) {
		strcat(result, results[i]);
		free(results[i]);
	}
	free(results);

	return result;
}

static bool stats_ds_init(const char *datastore_model_path, struct srv_config *config) {
	// New data store, no config but function to generate the statistics.
	config->stats_datastore = ncds_new(NCDS_TYPE_EMPTY, datastore_model_path, get_stats);

	// Activate it
	config->stats_dsid = ncds_init(config->stats_datastore);
	if (config->stats_dsid <= 0) {
		fprintf(stderr, "Couldn't activate the statistics data store (%d).", (int) config->stats_dsid);
		return false;
	}

	return true;
}

bool comm_init(const char *config_model_path, const char *stats_model_path, struct srv_config *config, struct interpreter *interpreter_) {
	// Wipe it out, so we have NULLs everywhere we didn't set something yet
	memset(config, 0, sizeof *config);
	// ID of the config data store.
	comm_test_values();

	//Initialize libnetconf for system-wide usage. This initialization is shared across all the processes.
	if (nc_init(0) == -1) {
		clb_print_error("libnetconf initiation failed.");
		return false;
	}

	// Get the config data store
	if (!config_ds_init(config_model_path, config)) {
		comm_cleanup(config);
		return false;
	}
	// Get the statistics data store
	if (!stats_ds_init(stats_model_path, config)) {
		comm_cleanup(config);
		return false;
	}
	/*
	 * Register the basic capabilities into the list. Hardcode the values - unfortunately,
	 * the libnetconf has constants for these, but does not publish them.
	 */
	register_capability("urn:ietf:params:netconf:base:1.0");
	register_capability("urn:ietf:params:netconf:base:1.1");
	register_capability("urn:ietf:params:netconf:capability:writable-running:1.0");
	// Generate the capabilities for the library
	struct nc_cpblts *capabilities = nc_cpblts_new(get_capabilities());

	// Accept NETCONF session from a client.
	config->session = nc_session_accept(capabilities);
	// Capabilities are no longer needed
	nc_cpblts_free(capabilities);

	if (config->session == NULL) {
		clb_print_error("Session not established.\n");
		comm_cleanup(config);
		return false;
	}

	// Add to the list of sessions.
	nc_session_monitor(config->session);

	interpreter = interpreter_;

	return true;
}

/*
 * This function send reply to user.
 * It doesn't care if it is OK message or self-generated error.
 * Function destroy communication structures.
 * Return TRUE - function sent reply sucesfully; if was random error
 * Return FALSE - function can't sent reply; session is broken
 */

static bool comm_send_reply(struct nc_session *session, struct rpc_communication *communication) {
	const nc_msgid msgid;

	msgid = nc_session_send_reply(session, communication->msg, communication->reply);
	if (msgid == 0) {
		nc_rpc_free(communication->msg);
		nc_reply_free(communication->reply);

		return false;
	}

	nc_rpc_free(communication->msg);
	nc_reply_free(communication->reply);

	return true;
}

void comm_start_loop(const struct srv_config *config) {
	while (true) {
		struct rpc_communication communication;
		// Make sure there's no garbage if we don't set something in it.
		memset(&communication, 0, sizeof communication);

		//check session status
		NC_SESSION_STATUS session_status = nc_session_get_status(config->session);
		if (session_status == NC_SESSION_STATUS_CLOSING  || session_status == NC_SESSION_STATUS_CLOSED || session_status == NC_SESSION_STATUS_ERROR) {
			break;
		}

		//Another NC_SESSION_STATUS option are:
		//if (session_status == NC_SESSION_STATUS_DUMMY) //Not our case
		//if (session_status == NC_SESSION_STATUS_WORKING) //All is OK, go ahead
		//if (session_status == NC_SESSION_STATUS_STARTUP) //All is OK, go ahead


		//Process incoming requests
		NC_MSG_TYPE msg_type = nc_session_recv_rpc(config->session, -1, &communication.msg);
			//[in]	timeout	Timeout in milliseconds, -1 for infinite timeout, 0 for non-blocking
		if (msg_type == NC_MSG_UNKNOWN) {
			communication.reply = nc_reply_error(nc_err_new(NC_ERR_MALFORMED_MSG));

			clb_print_error("Broken message recieved");
			if (!comm_send_reply(config->session, &communication)) {
				break;
			}

			continue;
		}

		//Reply to the client's request
		communication.reply = ncds_apply_rpc2all(config->session, communication.msg, NULL);

		if (communication.reply == NULL || communication.reply == NCDS_RPC_NOT_APPLICABLE) {
			//NC_ERR_UNKNOWN_ELEM sounds good for now
			communication.reply = nc_reply_error(nc_err_new(NC_ERR_UNKNOWN_ELEM));
			if (!comm_send_reply(config->session, &communication)) {
				clb_print_error("Couldn't send error reply");
				break;
			}

			continue;
		}

		//send non-error reply
		if (!comm_send_reply(config->session, &communication)) {
			clb_print_error("Couldn't send reply");
			break;
		}
	}
}

void comm_cleanup(struct srv_config *config) {
	if (nc_session_get_status(config->session) == NC_SESSION_STATUS_WORKING) {
		//Close NETCONF connection with the server
		nc_session_close(config->session, NC_SESSION_TERM_CLOSED);
	}

	// Cleanup the session structure and free all the allocated resources
	if (config->session)
		nc_session_free(config->session);
	config->session = NULL;

	// Close data stores
	if (config->config_datastore)
		ncds_free(config->config_datastore);
	config->config_datastore = NULL;

	if (config->stats_datastore)
		ncds_free(config->stats_datastore);
	config->stats_datastore = NULL;

	//Close internal libnetconf structures and subsystems
	nc_close(0);
}
