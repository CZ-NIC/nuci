/*
 * Copyright 2013, CZ.NIC z.s.p.o. (http://www.nic.cz/)
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
struct nuci_ds_data *nuci_ds_get_custom_data(struct nuci_lock_info *lock_info, struct interpreter *interpreter, lua_datastore datastore, bool locking_enabled);

#endif // NUCI_DATASTORE_H
