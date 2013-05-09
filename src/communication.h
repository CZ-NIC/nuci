#ifndef __communication_h__
#define __communication_h__

#include <libnetconf.h>
/**
 * @brief Holds server configuration
 */
struct srv_config {
	struct nc_session *session; ///<Session ID
	ncds_id dsid; ///< Working Datastore's datastore ID
	struct ncds_ds *datastore; ///<Datastore handler
};

/**
 * @brief Message & reply
 */
struct rpc_communication {
	nc_rpc *msg; ///<Incoming message
	nc_rpc *reply; ///<Generated reply
};


int comm_init(); 
void comm_start_loop();
void comm_cleanup();




#endif //__netconf_h__

