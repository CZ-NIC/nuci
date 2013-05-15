#include "communication.h"
#include "nuci_datastore.h"
#include "register.h"

#include <stdio.h>

#include <libnetconf.h>
#include <libnetconf/datastore_custom_public.h>

/**
 * @brief Message & reply
 */
struct rpc_communication {
	nc_rpc *msg; ///<Incoming message
	nc_rpc *reply; ///<Generated reply
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
	if (ncds_custom_set_data(config->config_datastore, NULL, ds_funcs) != 0) {
		clb_print_error("Linking datastore to a file failed.");
		return false;
	}

	// Activate datastore structure for use.
	config->config_dsid = ncds_init(config->config_datastore);
	if (config->config_dsid <= 0) { //Optionally: ncds_init has 4 different error return types
		ncds_free(config->config_datastore);
		return false;
	}

	return true;
}

bool comm_init(const char *datastore_model_path, struct srv_config *config) {
	// ID of the config data store.
	comm_test_values();

	//Initialize libnetconf for system-wide usage. This initialization is shared across all the processes.
	if (nc_init(NC_INIT_NOTIF | NC_INIT_NACM) == -1) {
		clb_print_error("libnetconf initiation failed.");
		return false;
	}

	// Get the config data store
	if (!config_ds_init(datastore_model_path, config))
		return false;
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
		ncds_free(config->config_datastore);
		return false;
	}

	return true;
}

void comm_start_loop(const struct srv_config *config) {
	struct rpc_communication communication;
	NC_MSG_TYPE msg_type;
	const nc_msgid msgid;
	NC_SESSION_STATUS session_status;

	while (true) {
		session_status = nc_session_get_status(config->session);
		if (session_status == NC_SESSION_STATUS_CLOSING  || session_status == NC_SESSION_STATUS_CLOSED || session_status == NC_SESSION_STATUS_ERROR) {
			break;
		}

		//Another NC_SESSION_STATUS option are:
		//if (session_status == NC_SESSION_STATUS_DUMMY) //Not our case
		//if (session_status == NC_SESSION_STATUS_WORKING) //All is OK, go ahead
		//if (session_status == NC_SESSION_STATUS_STARTUP) //All is OK, go ahead


		// 1/3 - Process incoming requests
		msg_type = nc_session_recv_rpc(config->session, -1, &communication.msg);
			//[in]	timeout	Timeout in milliseconds, -1 for infinite timeout, 0 for non-blocking
		if (msg_type == NC_MSG_UNKNOWN) {
			clb_print_error("Broken message recieved");
			nc_rpc_free(communication.msg);
			continue;
		}

		// 2/3 - Reply to the client's request
		communication.reply = ncds_apply_rpc(config->config_dsid, config->session, communication.msg);

		if (communication.reply == NULL) {
			//nothing to do
			nc_rpc_free(communication.msg);
			continue;
		}

		msgid = nc_session_send_reply(config->session, communication.msg, communication.reply);
		if (msgid == 0) {
			clb_print_error("I can't send reply");
			//continue is not necessary
			//messages are freed at end of loop
		}

		// 3/3 - Free all unused objects
		nc_rpc_free(communication.msg);
		nc_reply_free(communication.reply);
	}
}

void comm_cleanup(const struct srv_config *config) {
	if (nc_session_get_status(config->session) == NC_SESSION_STATUS_WORKING) {
		//Close NETCONF connection with the server
		nc_session_close(config->session, NC_SESSION_TERM_CLOSED);
		//WARNING!!! - Only nc_session_free() and nc_session_get_status() functions are allowed after this call.
	}

	//Cleanup the session structure and free all the allocated resources
	nc_session_free(config->session);

	//Close the specified datastore and free all the resources
	ncds_free(config->config_datastore);

	//Close internal libnetconf structures and subsystems
	nc_close(0);
}
