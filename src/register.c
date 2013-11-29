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

#include "register.h"

#include <stdlib.h>
#include <string.h>
#include <assert.h>

struct string_array {
	const char **data;
	size_t capacity, used;
};

#define ARRAY_INITIALIZER {\
	.capacity = 1, \
	.used = 1 \
}

static void check_array(struct string_array *array) {
	if (!array->data)
		array->data = calloc(1, array->capacity * sizeof *array->data);
}

static void insert_string(struct string_array *array, const char *string) {
	check_array(array);
	if (array->used == array->capacity)
		array->data = realloc(array->data, (array->capacity *= 2) * sizeof *array->data);
	array->data[array->used - 1] = strdup(string);
	array->data[array->used ++] = NULL;
}

static struct string_array datastore_models = ARRAY_INITIALIZER;
static lua_datastore *datastores;
static size_t datastore_count;

void register_datastore_provider(const char *model_path, lua_datastore datastore) {
	insert_string(&datastore_models, model_path);
	datastores = realloc(datastores, (++ datastore_count) * sizeof *datastores);
	datastores[datastore_count - 1] = datastore;
}

const char *const *get_datastore_providers(const lua_datastore **datastores_, size_t *size) {
	check_array(&datastore_models);
	if (datastores_)
		*datastores_ = datastores;
	if (size)
		*size = datastore_count;
	return datastore_models.data;
}
