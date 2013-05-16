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
	return capabilities.data;
}

void register_submodel(const char *path) {
	// TODO: Implement the function. This is just a dummy function to check it is called.
	// TODO: Strdup the path
	fprintf(stderr, "Registering submodule: %s\n", path);
}

void register_stat_generator(const char *substats_path, lua_callback callback) {
	fprintf(stderr, "Registering new stat generator %d for %s\n", callback, substats_path);
	if (test_interpreter)
		fprintf(stderr, "Testing callback: %s\n", interpreter_call_str(test_interpreter, callback));
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
