#ifndef NUCI_DATASTORE_H
#define NUCI_DATASTORE_H

#include <unistd.h>
#include <stdbool.h>

struct ncds_custom_funcs;

extern const struct ncds_custom_funcs *ds_funcs;

//Get pointer to datastore's custom data
void * nuci_ds_get_custom_data();

#endif // NUCI_DATASTORE_H
