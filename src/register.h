/*
 * Copyright 2013, CZ.NIC
 *
 * This file is part of NUCI configuration server.
 *
 * NUCI is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 * NUCI is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with NUCI.  If not, see <http://www.gnu.org/licenses/>.
 */

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
