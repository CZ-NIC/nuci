#ifndef NUCI_DATASTORE_H
#define NUCI_DATASTORE_H

#include "interpreter.h"

#include <unistd.h>
#include <stdbool.h>

struct ncds_custom_funcs;

extern const struct ncds_custom_funcs *ds_funcs;

struct nuci_ds_data;
struct nuci_lock_info;

struct nuci_lock_info *lock_info_create(void);
void lock_info_free(struct nuci_lock_info *info);

//Get pointer to datastore's custom data
struct nuci_ds_data *nuci_ds_get_custom_data(struct nuci_lock_info *lock_info, struct interpreter *interpreter, lua_datastore datastore);

#endif // NUCI_DATASTORE_H
