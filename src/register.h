#ifndef REGISTER_H
#define REGISTER_H

#include "interpreter.h"

#include <stddef.h>

/*
 * Interface to register stuff for the lua plugins. Capabilities,
 * namespaces and callbacks.
 */

/*
 * Register (part of) the data store.
 *
 * The data store is something that stores and provides bits of configuration.
 *
 * Supply the corresponding path to the model.
 */
void register_datastore_provider(const char *model_path, lua_datastore datastore);

/*
 * Similar to get_stat_defs, but for the datastore providers.
 */
const char *const *get_datastore_providers(const lua_datastore **datastores, size_t *size);

#endif
