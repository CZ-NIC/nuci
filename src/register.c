#include "register.h"

#include <stdio.h>

void register_capability(const char *cap_uri) {
	// TODO: Implement the function. This is just a dummy function to check it is called.
	// TODO: Strdup the uri
	fprintf(stderr, "Registering capability: %s\n", cap_uri);
}

void register_submodel(const char *path) {
	// TODO: Implement the function. This is just a dummy function to check it is called.
	// TODO: Strdup the path
	fprintf(stderr, "Registering submodule: %s\n", path);
}

void register_stat_generator(lua_callback callback) {
	fprintf(stderr, "Registering new stat generator %d\n", callback);
}

void register_datastore_provider(const char *ns, lua_datastore datastore) {
	// TODO: Strdup the data store
	fprintf(stderr, "Registering new data store part %d for ns %s\n", datastore, ns);
}
