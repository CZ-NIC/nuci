#include "communication.h"
#include "nuci_datastore.h"
#include "register.h"
#include "interpreter.h"
#include "model.h"
#include "logging.h"

#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <stdlib.h>

#include <libnetconf.h>
#include <libnetconf/datastore_custom.h>

#define LUA_PLUGIN_PATH PLUGIN_PATH "/lua_plugins"

// One data store
struct datastore {
	ncds_id id;
	struct ncds_ds *datastore;
	char *ns;
	lua_datastore lua;
};

/**
 * @brief Message & reply
 */
struct rpc_communication {
	nc_rpc *msg; // Incoming message
	nc_reply *reply; // Reply to send
};

struct srv_config global_srv_config;

static void(*clb_print_error)(const char *message) = NULL;

static void clb_print_error_default(const char *message) {
	nlog(NLOG_ERROR, "Module communication error: %s", message);
}

static void comm_test_values(void) {
	if (clb_print_error == NULL) {
		clb_print_error = clb_print_error_default;
	}
}

void comm_set_print_error_callback(void(*clb)(const char *message)) {
	clb_print_error = clb;
}

static char *get_ds_stats(const char *model, const char *running, struct nc_err **e) {
	(void) running;
	char *model_uri = extract_model_uri_string(model);
	lua_datastore datastore;
	bool found = false;
	for (size_t i = 0; i < global_srv_config.config_datastore_count; i ++)
		if (strcmp(model_uri, global_srv_config.config_datastores[i].ns) == 0) {
			found = true;
			datastore = global_srv_config.config_datastores[i].lua;
			break;
		}
	free(model_uri);
	assert(found); // We should not be called with namespace we don't know

	const char *result = interpreter_get(global_srv_config.interpreter, datastore, "get");
	if ((*e = nc_err_create_from_lua(global_srv_config.interpreter, *e))) {
		return NULL;
	} else {
		return strdup(result);
	}

	return strdup(result);
}

static bool config_ds_init(const char *datastore_model_path, struct datastore *datastore, lua_datastore lua_datastore, struct nuci_lock_info *lock_info, struct interpreter *interpreter, bool locking_enabled) {
	// Create a data store. The thind parameter is NULL, so <get> returns the same as
	// <get-config> in this data store.
	datastore->ns = extract_model_uri_file(datastore_model_path);
	datastore->lua = lua_datastore;
	datastore->datastore = ncds_new(NCDS_TYPE_CUSTOM, datastore_model_path, get_ds_stats);

	if (datastore->datastore == NULL) {
		clb_print_error("Datastore preparing failed.");
		return false;
	}

	// Set the callbacks
	ncds_custom_set_data(datastore->datastore, nuci_ds_get_custom_data(lock_info, interpreter, lua_datastore, locking_enabled), ds_funcs);

	// Activate datastore structure for use.
	datastore->id = ncds_init(datastore->datastore);
	if (datastore->id <= 0) { //Optionally: ncds_init has 4 different error return types
		clb_print_error("Couldn't activate the config data store.");
		return false;
	}

	return true;
}

bool comm_init(struct srv_config *config, struct interpreter *interpreter_) {
	// Wipe it out, so we have NULLs everywhere we didn't set something yet
	memset(config, 0, sizeof *config);
	comm_test_values();

	//Initialize libnetconf for system-wide usage. This initialization is shared across all the processes.
	if (nc_init(0) == -1) {
		clb_print_error("libnetconf initiation failed.");
		return false;
	}

	config->lock_info = lock_info_create();
	bool locking_enabled = true;

	size_t config_datastore_count;
	const lua_datastore *lua_datastores;
	const char *const *datastore_paths = get_datastore_providers(&lua_datastores, &config_datastore_count);
	config->config_datastores = calloc(config_datastore_count, sizeof *config->config_datastores);
	for (size_t i = 0; i < config_datastore_count; i ++) {
		char *filename = model_path(datastore_paths[i]);
		bool result = config_ds_init(filename, &config->config_datastores[i], lua_datastores[i], config->lock_info, interpreter_, locking_enabled);
		locking_enabled = false;
		free(filename);
		if (!result) {
			comm_cleanup(config);
			return false;
		}
		/*
		 * Trick. Keep the count accurate during the creation (don't set it in one jump at the
		 * beginning or end, so it is correct even if the creation fail and we abort it.
		 *
		 * Used in the free at the end.
		 */
		config->config_datastore_count ++;
	}

	/*
	 * Register the basic capabilities into the list. Hardcode the values - unfortunately,
	 * the libnetconf has constants for these, but does not publish them.
	 */
	const char *const caps[] = {
		"urn:ietf:params:netconf:base:1.0",
		"urn:ietf:params:netconf:base:1.1",
		"urn:ietf:params:netconf:capability:writable-running:1.0",
		NULL
	};
	struct nc_cpblts *capabilities = nc_cpblts_new(caps);

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

	config->interpreter = interpreter_;

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
	bool loop = true; //Break is not enough for handling close-session request

	while (loop) {
		struct rpc_communication communication;
		// Make sure there's no garbage if we don't set something in it.
		memset(&communication, 0, sizeof communication);

		//Check session status
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

		//Get more informations about request
		NC_RPC_TYPE req_type = nc_rpc_get_type(communication.msg);
		NC_OP req_op = nc_rpc_get_op(communication.msg);

		//Handle session request-class
		if (req_type == NC_RPC_SESSION) {
			switch(req_op) {
			case NC_OP_CLOSESESSION:
				//Stop loop is OK: session will be physically killed by comm_cleanup()
				loop = false;
				communication.reply = nc_reply_ok();
				break;

			default:
				communication.reply = nc_reply_error(nc_err_new(NC_ERR_OP_NOT_SUPPORTED));
				break;
			}
		} else if (req_type == NC_RPC_UNKNOWN) {
			//User rpc is expected now

			//libnetconf for all getters says: Caller is responsible for freeing the returned string with free().
			char *ns = nc_rpc_get_ns(communication.msg);
			char *rpc_procedure = nc_rpc_get_op_name(communication.msg);
			char *rpc_data = nc_rpc_get_op_content(communication.msg);

			bool ds_found = false;
			communication.reply = NULL;

			//find namespace
			for (size_t i = 0; i < config->config_datastore_count; i ++) {
				if (strcmp(ns, config->config_datastores[i].ns) == 0) {
					ds_found = true;
					char *xml = NULL;
					char *xml_part = interpreter_process_user_rpc(config->interpreter, config->config_datastores[i].lua, rpc_procedure, rpc_data);
					/*
					 * We have the answer. However, we need to do some manual juggling
					 * to generate the answer, since libnetconf wants to put <data> or <ok>
					 * into everything.
					 */
					if (xml_part) {
						const char *format = "<rpc-reply xmlns='urn:ietf:params:xml:ns:netconf:base:1.0'>%s</rpc-reply>";
						int size = snprintf(NULL, 0, format, xml_part);
						xml = malloc(size + 1);
						snprintf(xml, size + 1, format, xml_part);
						communication.reply = nc_reply_build(xml);
						free(xml);
					}
					break;
				}
			}

			//Unknown datastore
			if (!ds_found) {
				communication.reply = nc_reply_error(nc_err_new(NC_ERR_UNKNOWN_NS));

			//Some interpreter error
			} else if (!communication.reply) { // Reply could be NULL even if the data store was found
				//This is for all cases: If lua detect some error enterpreter is better send any status message.
				communication.reply = nc_reply_error(nc_err_create_from_lua(config->interpreter, NULL));
			}

			//cleanup
			free(ns);
			free(rpc_procedure);
			free(rpc_data);

			//TODO
			//Check if libnetconf is testing rpc content

		} else {
			//Reply to the client's request
			communication.reply = ncds_apply_rpc2all(config->session, communication.msg, NULL);

			if (communication.reply == NULL || communication.reply == NCDS_RPC_NOT_APPLICABLE) {
				//NC_ERR_UNKNOWN_ELEM sounds good for now
				communication.reply = nc_reply_error(nc_err_new(NC_ERR_UNKNOWN_ELEM));
			}
			bool error = nc_reply_get_type(communication.reply) == NC_REPLY_ERROR;
			if (error)
				nlog(NLOG_WARN, "An error message to send: %s\n", nc_reply_get_errormsg(communication.reply));
			bool finished = false;
			while (!finished) {
				bool failed = !interpreter_commit(config->interpreter, !error);
				if (failed) {
					nc_reply_free(communication.reply);
					communication.reply = nc_reply_error(nc_err_create_from_lua(config->interpreter, NULL));
					if (error)
						die("Rollback failed (%s), no idea what to do about that", nc_reply_get_errormsg(communication.reply));
					else {
						nlog(NLOG_INFO, "Commit failed, doing rollback instead");
						error = true;
						assert(communication.reply);
					}
				} else
					finished = true;
			}
		}

		//send reply
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

	// Close data stores and free memory for service info around them
	for (size_t i = 0; i < config->config_datastore_count; i ++) {
		if (config->config_datastores[i].datastore)
			ncds_free(config->config_datastores[i].datastore);
		config->config_datastores[i].datastore = NULL;
		free(config->config_datastores[i].ns);
	}

	if (config->lock_info)
		lock_info_free(config->lock_info);

	//Close internal libnetconf structures and subsystems
	nc_close(0);
}
