#include "communication.h"
#include "nuci_datastore.h"

#include <stdio.h>

#include <libnetconf.h>

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

bool comm_init(const char *datastore_model_path, struct srv_config *config) {
	//Fill with real values!!
	//////////////////////////////////////////////////////////////////////////////////////////////////////////////
	char *const srv_cpblts[] = {
		"urn:ietf:params:netconf:base:1.0",
		"urn:ietf:params:netconf:base:1.1",
		"urn:ietf:params:netconf:capability:writable-running:1.0",
		NULL
	};
	//////////////////////////////////////////////////////////////////////////////////////////////////////////////
	struct nc_cpblts *my_capabilities; // Server's capabilities
	int init;

	comm_test_values();

	//Initialize libnetconf for system-wide usage. This initialization is shared across all the processes.
	init = nc_init(NC_INIT_NOTIF | NC_INIT_NACM);
	if (init == -1) {
		clb_print_error("libnetconf initiation failed.");
		return false;
	}

	//Create new datastore structure with transaction API support.
	// 1/3 - Create new
	config->datastore = ncds_new(NCDS_TYPE_CUSTOM, datastore_model_path, NULL);
		//3th parameter is: char *(*)(const char *model, const char *running, struct nc_err **e) get_state
		//------------------------------------------------------------------------------------------------
		//Pointer to a callback function that returns a serialized XML document containing the state
		//configuration data of the device. The parameters it receives are a serialized configuration
		//data model in YIN format and the current content of the running datastore.
		//If NULL is set, <get> operation is performed in the same way as <get-config>.
	if (config->datastore == NULL) {
		clb_print_error("Datastore preparing failed.");
		return false;
	}

	// 2/3 - Assign file to datastore
	if (ncds_custom_set_data(config->datastore, NULL, nuci_ds_fill_callbacks()) != 0) {
		clb_print_error("Linking datastore to a file failed.");
		return false;
	}

	// 3/3 (Init datastore)
	// Activate datastore structure for use.
	// The datastore configuration is checked and if everything is correct, datastore gets its unique ID to be used for datastore operations (ncds_apply_rpc()).
	config->dsid = ncds_init(config->datastore);
	//config.dsid = 1;
	if (config->dsid <= 0) { //Optionally: ncds_init has 4 different error return types
		ncds_free(config->datastore);
		return false;
	}

	//Prepare capabilities configuration
	//my_capabilities = nc_session_get_cpblts_default();
	my_capabilities = nc_cpblts_new(srv_cpblts);

	//Accept NETCONF session from a client.
	config->session = nc_session_accept(my_capabilities);
	if (config->session == NULL) {
		clb_print_error("Session not established.\n");
		nc_cpblts_free(my_capabilities);
		return false;
	}

	nc_cpblts_free(my_capabilities);

	//REQUESTED by RFC 6022
	//Add the session into the internal list of monitored sessions that
	//are returned as part of netconf-state information defined in RFC 6022.
	nc_session_monitor(config->session);

	/*
	 * According to http://code.google.com/p/libnetconf/source/detail?r=459b9c17508e3b2d5aee5e29cd43aa236795d531
	 * libevent is used only for example server
	 */

	 return true;
}

void comm_start_loop(const struct srv_config *config) {
	int loop = 1;
	struct rpc_communication communication;
	NC_MSG_TYPE msg_type;
	const nc_msgid msgid;
	NC_SESSION_STATUS session_status;

	while (loop) {
		session_status = nc_session_get_status(config->session);
		if (session_status == NC_SESSION_STATUS_CLOSING  || session_status == NC_SESSION_STATUS_CLOSED || session_status == NC_SESSION_STATUS_ERROR) {
			loop = 0;
			continue;
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
		communication.reply = ncds_apply_rpc(config->dsid, config->session, communication.msg);

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
	ncds_free(config->datastore);

	//Close internal libnetconf structures and subsystems
	nc_close(0);
}
