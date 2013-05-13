#include "nuci_datastore.h"

#include <stdio.h>
#include <stdlib.h>

#include <libnetconf.h>

struct ncds_custom_funcs *nuci_ds_fill_callbacks(void) {
	struct ncds_custom_funcs *cb = (struct ncds_custom_funcs *)calloc(1, sizeof(struct ncds_custom_funcs));
	
	cb->init = nuci_ds_init;
	cb->free = nuci_ds_free;
	cb->was_changed = nuci_ds_was_changed;
	cb->rollback = nuci_ds_rollback;
	cb->get_lockinfo = nuci_ds_get_lockinfo;
	cb->lock = nuci_ds_lock;
	cb->unlock = nuci_ds_unlock;
	cb->getconfig = nuci_ds_getconfig;
	cb->copyconfig = nuci_ds_copyconfig;
	cb->deleteconfig = nuci_ds_deleteconfig;
	cb->editconfig = nuci_ds_editconfig;
}

int nuci_ds_init(void *data, struct ncds_ds* ds) {
	return 0; //on success, non-zero else
}

void nuci_ds_free(void *data, struct ncds_ds* ds) {
	struct ncds_ds_custom *c_ds = (struct ncds_ds_custom *) ds;
	free(c_ds->callbacks);
	free(c_ds->data);
	free(c_ds);
}

int nuci_ds_was_changed(void *data, struct ncds_ds* ds) {
	return 0;
	//return ds->callbacks->was_changed(ds->data, ds);
}

int nuci_ds_rollback(void *data, struct ncds_ds* ds) {
	return 0;
}

const struct ncds_lockinfo* nuci_ds_get_lockinfo(void *data, struct ncds_ds* ds, NC_DATASTORE target) {
	return 0;
}

int nuci_ds_lock(void *data, struct ncds_ds* ds, const struct nc_session* session, NC_DATASTORE target, struct nc_err** error) {
	return 0;
}

int nuci_ds_unlock(void *data, struct ncds_ds* ds, const struct nc_session* session, NC_DATASTORE target, struct nc_err** error) {
	return 0;
}

char* nuci_ds_getconfig(void *data, struct ncds_ds* ds, const struct nc_session* session, NC_DATASTORE target, struct nc_err** error) {
	return 0;
}

int nuci_ds_copyconfig(void *data, struct ncds_ds* ds, const struct nc_session* session, const nc_rpc* rpc, NC_DATASTORE target, NC_DATASTORE source, char* config, struct nc_err** error) {
	return 0;
}

int nuci_ds_deleteconfig(void *data, struct ncds_ds* ds, const struct nc_session* session, NC_DATASTORE target, struct nc_err** error) {
	return 0;
}

int nuci_ds_editconfig(void *data, struct ncds_ds *ds, const struct nc_session * session, const nc_rpc* rpc, NC_DATASTORE target, const char * config, NC_EDIT_DEFOP_TYPE defop, NC_EDIT_ERROPT_TYPE errop, struct nc_err **error) {
	return 0;
}

