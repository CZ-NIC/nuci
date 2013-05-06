#include <stdio.h>
#include <stdlib.h>

#include "main.h"

//LIBs
#include "../headers/libnetconf/libnetconf.h"
/*
 * nuci skeleton
 * 
 * Tohle se skoro blizi fungujicimu zakladu. Jedina nevyresena vec je,
 * jak zavirat session. Aktualne se to nechava na klientovi.
 * Jakmile klient zavre spojeni, ja to zdetekuji, uvolnim zpravy,
 * vyskocim ze smycky. Netusim jak - a jestli je potreba - iniciovat
 * uzavreni spojeni ze strany serveru.
 * 
 */

static const char *DATASTORE_MODEL_PATH = "datastore.yin";
static const char *DATASTORE_CALLBACKS_PATH = "datastore.so";
static const char *DATASTORE_FILE_PATH = "datastore.xml";

struct srv_config {
	struct nc_session *session; ///<Session ID
	ncds_id dsid; ///< Working Datastore's datastore ID
};

struct rpc_communication {
	nc_rpc *msg;
	nc_rpc *reply;
};

void callback_print(NC_VERB_LEVEL level, const char* msg) {
	fprintf(stderr, "Message: %s\n", msg);
}

int main(int argc, char **argv) {
	struct srv_config config; ///< Server configuration 
	struct ncds_ds* datastore; ///< Datastore handler
	struct nc_cpblts *my_capabilities; ///< Server's capabilities 
	int init;
	int loop = 1;
	

	/* set verbosity and function to print libnetconf's messages */
	nc_verbosity(NC_VERB_DEBUG);
	nc_callback_print(callback_print);

	//Initialize libnetconf for system-wide usage. This initialization is shared across all the processes.
	init = nc_init(NC_INIT_NOTIF | NC_INIT_NACM);
	if (init == -1) {
		callback_print(NC_VERB_ERROR, "libnetconf initiation failed.");
		return 1;
	}

	//Create new datastore structure with transaction API support.
	// 1/3 - Create new
	datastore = ncds_new_transapi(NCDS_TYPE_FILE, DATASTORE_MODEL_PATH, DATASTORE_CALLBACKS_PATH);
	if (datastore == NULL) {
		callback_print(NC_VERB_ERROR, "Datastore preparing failed.");
		return 1;
	}
	
	// 2/3 - Assign file to datastore
	if (ncds_file_set_path(datastore, DATASTORE_FILE_PATH) != 0) {
		callback_print(NC_VERB_ERROR, "Linking datastore to a file failed.");
		return 1;
	}
	
	// 3/3 (Init datastore)
	// Activate datastore structure for use. 
	// The datastore configuration is checked and if everything is correct, datastore gets its unique ID to be used for datastore operations (ncds_apply_rpc()).
	config.dsid = ncds_init(datastore);
	if (config.dsid <= 0) {
		ncds_free(datastore);
		callback_print(NC_VERB_ERROR, "Initiating datastore failed.");
		return 1;
	}

	//device initialization
	//If init == 1 - someone else already called nc_init() since last system-wide nc_close() or system reboot
	if (init == 0) {
		/*
		 * Asi nic
		 * Pokud jsem se neztratil v tom examplu, tak vsechno co se tady delo
		 * melo souvislost jen a pouze s modelem agent-server.
		 * 
		 */
	}

	//Prepare capabilities configuration
	my_capabilities = nc_session_get_cpblts_default();
	nc_cpblts_free(my_capabilities);

	//Accept NETCONF session from a client.
	config.session = nc_session_accept(my_capabilities);
	if (config.session == NULL) {
		callback_print(NC_VERB_ERROR, "Session not established.\n");
		return 1;
	}

	//REQUESTED by RFC 6022
	//Add the session into the internal list of monitored sessions that 
	//are returned as part of netconf-state information defined in RFC 6022.
	nc_session_monitor(config.session);

	/*
	 * According to http://code.google.com/p/libnetconf/source/detail?r=459b9c17508e3b2d5aee5e29cd43aa236795d531
	 * libevent is used only for example server
	 */ 
	 
	 struct rpc_communication communication; ///< Message & Reply struct
	 NC_MSG_TYPE msg_type;
	 const nc_msgid msgid;
	 NC_SESSION_STATUS session_status;
	 
	 while (loop) {
		session_status = nc_session_get_status(config.session);
		if (session_status == NC_SESSION_STATUS_CLOSING  || session_status == NC_SESSION_STATUS_CLOSED || session_status == NC_SESSION_STATUS_ERROR) {
			loop = 0;
			continue;
		}
		
		//if (session_status == NC_SESSION_STATUS_WORKING || session_status == NC_SESSION_STATUS_STARTUP) {
			//all is OK
		//}
		
		////////////////////////////////////////////////////////////////
		////////////////////////////////////////////////////////////////
		////////////////////////////////////////////////////////////////
		
		// 1/3 - Process incoming requests
		msg_type = nc_session_recv_rpc(config.session, -1, &communication.msg);
			//[in]	timeout	Timeout in milliseconds, -1 for infinite timeout, 0 for non-blocking 
		if (msg_type == NC_MSG_UNKNOWN) {
			callback_print(NC_VERB_ERROR, "Broken message recieved");
			nc_rpc_free(communication.msg);
			continue;
		}
			
		// 2/3 - Reply to the client's request
		communication.reply = ncds_apply_rpc(config.dsid, config.session, communication.msg);
		
		if (communication.reply == NULL) {
			//nothing to do
			nc_rpc_free(communication.msg);
			continue;
		}
		
		msgid = nc_session_send_reply(config.session, communication.msg, communication.reply);
		if (msgid == 0) {
			callback_print(NC_VERB_ERROR, "I can't send reply");
			//zadne continue - stejne uz neni co delat
			//uvolneni messages se provede stejne na konci smycky!!!!
		}
		
		// 3/3 - Free all unused objects
		nc_rpc_free(communication.msg);
		nc_reply_free(communication.reply);
	 }
	 

	if (nc_session_get_status(config.session) == NC_SESSION_STATUS_WORKING) {
		//Close NETCONF connection with the server
		nc_session_close(config.session, NC_SESSION_TERM_CLOSED);
		//WARNING!!! - Only nc_session_free() and nc_session_get_status() functions are allowed after this call.
	}
	
	//Cleanup the session structure and free all the allocated resources
	nc_session_free(config.session);
	
	//Close the specified datastore and free all the resources
	ncds_free(datastore);

	//Close internal libnetconf structures and subsystems
	nc_close(0);

	
	return 0;
}
