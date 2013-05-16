#include "register.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct interpreter *test_interpreter;

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
	array->data[array->used - 1] = string;
	array->data[array->used ++] = NULL;
}

static struct string_array capabilities = ARRAY_INITIALIZER;

void register_capability(const char *cap_uri) {
	insert_string(&capabilities, strdup(cap_uri));
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

static struct string_array stats_submodels = ARRAY_INITIALIZER;

static lua_callback *stats_callbacks;
static size_t callback_count;

void register_stat_generator(const char *substats_path, lua_callback callback) {
	insert_string(&stats_submodels, substats_path);
	stats_callbacks = realloc(stats_callbacks, (++ callback_count) * sizeof *stats_callbacks);
	stats_callbacks[callback_count - 1] = callback;
	if (test_interpreter)
		fprintf(stderr, "Testing callback: %s\n", interpreter_call_str(test_interpreter, callback));
}

char **register_call_stats_generators(size_t *count, struct interpreter *interpreter) {
	*count = callback_count;
	char **result = malloc(callback_count * sizeof *result);
	for (size_t i = 0; i < callback_count; i ++)
		result[i] = strdup(interpreter_call_str(interpreter, stats_callbacks[i]));
	return result;
}

const char *const *get_stat_defs() {
	check_array(&stats_submodels);
	return stats_submodels.data;
}

void register_datastore_provider(const char *ns, lua_datastore datastore) {
	// TODO: Strdup the data store
	fprintf(stderr, "Registering new data store part %d for ns %s\n", datastore, ns);
	if (test_interpreter) {
		const char *error = NULL;
		interpreter_set_config(test_interpreter, datastore, "Test config", &error);
		fprintf(stderr, "Set congig: %s\n", error);
		error = NULL;
		const char *getconfig = interpreter_get_config(test_interpreter, datastore, &error);
		fprintf(stderr, "Get congig: %s/%s\n", getconfig, error);
	}
}
