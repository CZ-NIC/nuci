#include "register.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct interpreter *test_interpreter;

// List containing just NULL
static const char **capabilities = NULL;
static size_t capability_used = 1, capability_capacity = 1;

static void check_capabilities() {
	if (!capabilities)
		capabilities = calloc(1, capability_capacity * sizeof *capabilities);
}

void register_capability(const char *cap_uri) {
	fprintf(stderr, "Registering capability: %s\n", cap_uri);
	check_capabilities();
	if (capability_used == capability_capacity)
		capabilities = realloc(capabilities, (capability_capacity *= 2) * sizeof *capabilities);
	capabilities[capability_used - 1] = strdup(cap_uri);
	capabilities[capability_used ++] = NULL;
}

const char *const *get_capabilities() {
	return capabilities;
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
