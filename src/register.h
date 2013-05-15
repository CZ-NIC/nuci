#ifndef REGISTER_H
#define REGISTER_H

#include "interpreter.h"

extern struct interpreter *test_interpreter;

/*
 * Interface to register stuff for the lua plugins. Capabilities,
 * namespaces and callbacks.
 */

/*
 * Add a capability to the list in the <hello> message.
 *
 * The cap_uri is the uri to include there, even if the name sounds like a fish.
 */
void register_capability(const char *cap_uri);

/*
 * Register a path to file containing submodule definition.
 *
 * It'll be incorporated into the main XML file.
 */
void register_submodel(const char *path);

/*
 * Register a function that is called to produce the XML statistics.
 *
 * All the registered callbacks should then be called and their output
 * concatenated to generate the desired statistics.
 */
void register_stat_generator(lua_callback callback);

/*
 * Register (part of) the data store.
 *
 * The data store is something that stores and provides bits of configuration.
 *
 * The data store is called to store data only if the data element has the
 * correct namespace.
 */
void register_datastore_provider(const char *ns, lua_datastore datastore);

#endif