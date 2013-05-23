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

char **register_call_stats_generators(size_t *count, struct interpreter *interpreter, char **error_out) {
	*count = callback_count;
	char **result = malloc(callback_count * sizeof *result);
	const char *error = NULL;
	for (size_t i = 0; i < callback_count; i ++) {
		const char *stats = interpreter_call_str(interpreter, stats_callbacks[i], &error);
		if (error) { // There's an error. Cancel the creation of result and propagate the error.
			assert(!stats);
			*error_out = strdup(error);
			for (size_t j = 0; j < i; j ++)
				free(result[j]);
			free(result);
			return NULL;
		}
		result[i] = strdup(stats);
	}
	return result;
}

const char *const *get_stat_defs(const lua_callback **callbacks, size_t *size) {
	check_array(&stats_modules);
	if (callbacks)
		*callbacks = stats_callbacks;
	if (size)
		*size = callback_count;
	return stats_modules.data;
}

void register_datastore_provider(const char *ns, lua_datastore datastore) {
	// TODO: Strdup the data store
	fprintf(stderr, "Registering new data store part %d for ns %s\n", datastore, ns);
}
