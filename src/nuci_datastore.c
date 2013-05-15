#include "nuci_datastore.h"

#include <stdio.h>
#include <stdlib.h>

#include <libnetconf.h>
#include <libnetconf/datastore_custom_public.h>

#include <libxml/tree.h>
#include <libxml/xpath.h>

/*
int nuci_ds_init(void *data, struct ncds_ds* ds) {
	fprintf(stderr, "CALLBACKS_DEBUG: \"init\" called\n");
	return 0; //on success, non-zero else
}
*/
static void nuci_ds_free(void *data) {
	fprintf(stderr, "CALLBACKS_DEBUG: I had chance to free custom data.\n");
	free(data);
}
/*
int nuci_ds_was_changed(void *data, struct ncds_ds* ds) {
	fprintf(stderr, "CALLBACKS_DEBUG: \"was_changed\" called\n");
	return 0;
}

int nuci_ds_rollback(void *data, struct ncds_ds* ds) {
	fprintf(stderr, "CALLBACKS_DEBUG: \"rollback\" called\n");
	return 0;
}

const struct ncds_lockinfo* nuci_ds_get_lockinfo(void *data, struct ncds_ds* ds, NC_DATASTORE target) {
	fprintf(stderr, "CALLBACKS_DEBUG: \"get_lockinfo\" called\n");
	return 0;
}

int nuci_ds_lock(void *data, struct ncds_ds* ds, const struct nc_session* session, NC_DATASTORE target, struct nc_err** error) {
	fprintf(stderr, "CALLBACKS_DEBUG: \"lock\" called\n");
	return 0;
}

int nuci_ds_unlock(void *data, struct ncds_ds* ds, const struct nc_session* session, NC_DATASTORE target, struct nc_err** error) {
	fprintf(stderr, "CALLBACKS_DEBUG: \"unlock\" called\n");
	return 0;
}
*/
static char* nuci_ds_getconfig(void *data, NC_DATASTORE target) {
	fprintf(stderr, "CALLBACKS_DEBUG: \"getconfig\" called\n");
	return strdup("<xyz/>");
}
/*
int nuci_ds_copyconfig(void *data, struct ncds_ds* ds, const struct nc_session* session, const nc_rpc* rpc, NC_DATASTORE target, NC_DATASTORE source, char* config, struct nc_err** error) {
	fprintf(stderr, "CALLBACKS_DEBUG: \"copyconfig\" called\n");
	return 0;
}

int nuci_ds_deleteconfig(void *data, struct ncds_ds* ds, const struct nc_session* session, NC_DATASTORE target, struct nc_err** error) {
	fprintf(stderr, "CALLBACKS_DEBUG: \"deleteconfig\" called\n");
	return 0;
}
*/	//zjistit co vraci const char *config
static int nuci_ds_editconfig(void *data, NC_DATASTORE target, const char * config, NC_EDIT_DEFOP_TYPE defop, NC_EDIT_ERROPT_TYPE errop) {
	fprintf(stderr, "CALLBACKS_DEBUG: \"editconfig\" called\n");
	return 0;
}

struct ncds_custom_funcs *nuci_ds_fill_callbacks(void) {
	struct ncds_custom_funcs *cb = (struct ncds_custom_funcs *)calloc(1, sizeof(struct ncds_custom_funcs));

	//cb->init = nuci_ds_init;
	cb->free = nuci_ds_free;
	//cb->was_changed = nuci_ds_was_changed;
	//cb->rollback = nuci_ds_rollback;
	//cb->get_lockinfo = nuci_ds_get_lockinfo;
	//cb->lock = nuci_ds_lock;
	//cb->unlock = nuci_ds_unlock;
	cb->getconfig = nuci_ds_getconfig;
	//cb->copyconfig = nuci_ds_copyconfig;
	//cb->deleteconfig = nuci_ds_deleteconfig;
	cb->editconfig = nuci_ds_editconfig;

	return cb;
}
