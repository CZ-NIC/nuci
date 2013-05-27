#include "register.h"

#include <stdio.h>
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

static struct string_array capabilities = ARRAY_INITIALIZER;

void register_capability(const char *cap_uri) {
	insert_string(&capabilities, cap_uri);
}

const char *const *get_capabilities() {
	check_array(&capabilities);
	return capabilities.data;
}

static struct string_array config_submodels = ARRAY_INITIALIZER;

void register_submodel(const char *path) {
	insert_string(&config_submodels, path);
}

const char *const *get_submodels() {
	check_array(&config_submodels);
	return config_submodels.data;
}

static struct string_array stats_modules = ARRAY_INITIALIZER;

static lua_callback *stats_callbacks;
static size_t callback_count;

void register_stat_generator(const char *stats_spec, lua_callback callback) {
	insert_string(&stats_modules, stats_spec);
	stats_callbacks = realloc(stats_callbacks, (++ callback_count) * sizeof *stats_callbacks);
	stats_callbacks[callback_count - 1] = callback;
}

const char *const *get_stat_defs(const lua_callback **callbacks, size_t *size) {
	check_array(&stats_modules);
	if (callbacks)
		*callbacks = stats_callbacks;
	if (size)
		*size = callback_count;
	return stats_modules.data;
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
	check_array(&stats_modules);
	if (datastores_)
		*datastores_ = datastores;
	if (size)
		*size = datastore_count;
	return datastore_models.data;
}
