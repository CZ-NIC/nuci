#ifndef NUCI_DATASTORE_H
#define NUCI_DATASTORE_H

#include <libnetconf.h>
#include <libxml/tree.h>
#include <libxml/xpath.h>
#include <libnetconf/published_interface.h>

struct ncds_custom_funcs *nuci_ds_fill_callbacks(void);

//int nuci_ds_init (void *data, struct ncds_ds* ds);
void nuci_ds_free(void *data);
//int nuci_ds_was_changed(void *data, struct ncds_ds* ds);
//int nuci_ds_rollback(void *data, struct ncds_ds* ds);
//const struct ncds_lockinfo* nuci_ds_get_lockinfo(void *data, struct ncds_ds* ds, NC_DATASTORE target);
//int nuci_ds_lock(void *data, struct ncds_ds* ds, const struct nc_session* session, NC_DATASTORE target, struct nc_err** error);
//int nuci_ds_unlock(void *data, struct ncds_ds* ds, const struct nc_session* session, NC_DATASTORE target, struct nc_err** error);
char *nuci_ds_getconfig(void *data, NC_DATASTORE target);
//int nuci_ds_copyconfig(void *data, struct ncds_ds* ds, const struct nc_session* session, const nc_rpc* rpc, NC_DATASTORE target, NC_DATASTORE source, char* config, struct nc_err** error);
//int nuci_ds_deleteconfig(void *data, struct ncds_ds* ds, const struct nc_session* session, NC_DATASTORE target, struct nc_err** error);
int nuci_ds_editconfig(void *data, NC_DATASTORE target, const char * config, NC_EDIT_DEFOP_TYPE defop, NC_EDIT_ERROPT_TYPE errop);

#endif // NUCI_DATASTORE_H
