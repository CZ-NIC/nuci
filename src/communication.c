#include "communication.h"
#include "nuci_datastore.h"
#include "register.h"
#include "interpreter.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include <libnetconf.h>
#include <libnetconf/datastore_custom.h>
#include <libxml/parser.h>
#include <libxml/tree.h>

// One data store
struct datastore {
	ncds_id id;
	struct ncds_ds *datastore;
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

static bool config_ds_init(const char *datastore_model_path, struct datastore *datastore, lua_datastore lua_datastore, struct nuci_lock_info *lock_info, struct interpreter *interpreter) {
	// Create a data store. The thind parameter is NULL, so <get> returns the same as
	// <get-config> in this data store.
	datastore->datastore = ncds_new(NCDS_TYPE_CUSTOM, datastore_model_path, NULL);

	if (datastore->datastore == NULL) {
		clb_print_error("Datastore preparing failed.");
		return false;
	}

	// Set the callbacks
	ncds_custom_set_data(datastore->datastore, nuci_ds_get_custom_data(lock_info, interpreter, lua_datastore), ds_funcs);

	// Activate datastore structure for use.
	datastore->id = ncds_init(datastore->datastore);
	if (datastore->id <= 0) { //Optionally: ncds_init has 4 different error return types
		clb_print_error("Couldn't activate the config data store.");
		return false;
	}

	return true;
}

/*
 * Take the model spec (yin) specs and extract the namespace uri of the model.
 * Pass the result onto the caller for free.
 */
static char *extract_model_uri(xmlDoc *doc) {
	assert(doc); // By now, someone should have validated the model before us.
	xmlNode *node = xmlDocGetRootElement(doc);
	assert(node);
	char *model_uri = NULL;
	for (xmlNode *current = node->children; current; current = current->next) {
		if (xmlStrcmp(current->name, (const xmlChar *) "namespace") == 0 && xmlStrcmp(current->ns->href, (const xmlChar *) "urn:ietf:params:xml:ns:yang:yin:1") == 0) {
			xmlChar *uri = xmlGetProp(current, (const xmlChar *) "uri");
			// Get a proper string, not some xml* beast.
			model_uri = strdup((const char *) uri);
			xmlFree(uri);
		}
	}
	xmlFreeDoc(doc);
	return model_uri;
}

static char *extract_model_uri_string(const char *model) {
	return extract_model_uri(xmlReadMemory(model, strlen(model), "model.xml", NULL, 0));
}

static char *extract_model_uri_file(const char *file) {
	return extract_model_uri(xmlParseFile(file));
}

struct stats_mapping {
	char *namespace;
	lua_callback callback;
};

static char *get_stats(const char *model, const char *running, struct nc_err **e) {
	(void) running;
	char *model_uri = extract_model_uri_string(model);
	lua_callback callback;
	bool callback_found = false;
	for (size_t i = 0; i < global_srv_config.stats_datastore_count; i ++)
		if (strcmp(model_uri, global_srv_config.stats_mappings[i].namespace) == 0) {
			callback_found = true;
			callback = global_srv_config.stats_mappings[i].callback;
			break;
		}
	free(model_uri);
	assert(callback_found); // We should not be called with namespace we don't know

	const char *result = interpreter_call_str(global_srv_config.interpreter, callback);
	if ((*e = nc_err_create_from_lua(global_srv_config.interpreter))) {
		return NULL;
	} else {
		return strdup(result);
	}

	return strdup(result);
}

static bool stats_ds_init(const char *datastore_model_path, struct datastore *datastore) {
	// New data store, no config but function to generate the statistics.
	datastore->datastore = ncds_new(NCDS_TYPE_EMPTY, datastore_model_path, get_stats);

	// Activate it
	datastore->id = ncds_init(datastore->datastore);
	if (datastore->id <= 0) {
		fprintf(stderr, "Couldn't activate the statistics data store for %s (%d).", datastore_model_path, (int) datastore->id);
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

	size_t config_datastore_count;
	const lua_datastore *lua_datastores;
	const char *const *datastore_paths = get_datastore_providers(&lua_datastores, &config_datastore_count);
	config->config_datastores = calloc(config_datastore_count, sizeof *config->config_datastores);
	for (size_t i = 0; i < config_datastore_count; i ++) {
		size_t len = strlen(PLUGIN_PATH) + strlen(datastore_paths[i]) + 2; // For the '/' and for '\0'
		char filename[len];
		size_t print_len = snprintf(filename, len, "%s/%s", PLUGIN_PATH, datastore_paths[i]);
		assert(print_len == len - 1);
		if (!config_ds_init(filename, &config->config_datastores[i], lua_datastores[i], config->lock_info, interpreter_)) {
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

	// FIXME: There are two very similar parts of code. Can we unify them a bit?
	// Create the statistics data stores.
	size_t stats_plugin_count;
	const lua_callback *callbacks;
	const char *const *stats_specs = get_stat_defs(&callbacks, &stats_plugin_count);
	config->stats_datastores = calloc(stats_plugin_count, sizeof *config->stats_datastores);
	config->stats_mappings = calloc(stats_plugin_count, sizeof *config->stats_mappings);
	for (size_t i = 0; i < stats_plugin_count; i ++) {
		size_t len = strlen(PLUGIN_PATH) + strlen(stats_specs[i]) + 2; // For the '/' and for '\0'
		char filename[len];
		size_t print_len = snprintf(filename, len, "%s/%s", PLUGIN_PATH, stats_specs[i]);
		assert(print_len == len - 1);
		if (!stats_ds_init(filename, &config->stats_datastores[i])) {
			comm_cleanup(config);
			return false;
		}
		/*
		 * Trick. Keep the count accurate during the creation (don't set it in one jump at the
		 * beginning or end, so it is correct even if the creation fail and we abort it.
		 *
		 * Used in the free at the end.
		 */
		config->stats_datastore_count ++;
		// Store mapping for the namespace->callback.
		config->stats_mappings[i].namespace = extract_model_uri_file(filename);
		config->stats_mappings[i].callback = callbacks[i];
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
		} else {
			//Reply to the client's request
			communication.reply = ncds_apply_rpc2all(config->session, communication.msg, NULL);

			if (communication.reply == NULL || communication.reply == NCDS_RPC_NOT_APPLICABLE) {
				//NC_ERR_UNKNOWN_ELEM sounds good for now
				communication.reply = nc_reply_error(nc_err_new(NC_ERR_UNKNOWN_ELEM));
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
	}

	if (config->lock_info)
		lock_info_free(config->lock_info);

	for (size_t i = 0; i < config->stats_datastore_count; i ++) {
		if (config->stats_datastores[i].datastore)
			ncds_free(config->stats_datastores[i].datastore);
		config->stats_datastores[i].datastore = NULL;
		if (config->stats_mappings[i].namespace)
			free(config->stats_mappings[i].namespace);
		config->stats_mappings[i].namespace = NULL;
	}

	free(config->stats_datastores);
	free(config->stats_mappings);

	//Close internal libnetconf structures and subsystems
	nc_close(0);
}
