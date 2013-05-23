#ifndef REGISTER_H
#define REGISTER_H

#include "interpreter.h"

#include <stddef.h>

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
 * Return the complete list of all registered capabilities.
 *
 * An array of strings is returned, NULL terminated.
 */
const char *const *get_capabilities();

/*
 * Register a path to file containing submodule definition.
 *
 * It'll be incorporated into the main XML file.
 */
void register_submodel(const char *path);

/*
 * Get list of submodules, as defined by register_submodel.
 *
 * Same form as get_capabilities.
 */
const char *const *get_submodels();

/*
 * Register a function that is called to produce the XML statistics.
 *
 * All the registered callbacks should then be called and their output
 * concatenated to generate the desired statistics.
 */
void register_stat_generator(const char *stats_spec_path, lua_callback callback);

/*
 * Provide list of all the spec submodules to include into the main module, registered
 * through register_stat_generator.
 *
 * Resutl is of the same form as get_capabilities. The callbacks is output-only array of
 * the callbacks (indeces match) and size is output-only size of both arrayrs (excluding the
 * NULL at the end of the specs string array).
 */
const char *const *get_stat_defs(const lua_callback **callbacks, size_t *size);

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
