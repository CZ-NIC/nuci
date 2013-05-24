#ifndef NUCI_DATASTORE_H
#define NUCI_DATASTORE_H

#include <unistd.h>
#include <stdbool.h>

struct ncds_custom_funcs;

extern const struct ncds_custom_funcs *ds_funcs;

struct nuci_ds_data;
struct nuci_lock_info;

//Get pointer to datastore's custom data
struct nuci_ds_data *nuci_ds_get_custom_data();

#endif // NUCI_DATASTORE_H
