#ifndef REGISTER_H
#define REGISTER_H

#include "interpreter.h"

#include <stddef.h>

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
void register_stat_generator(const char *substats_path, lua_callback callback);

/*
 * Call all the statistics generarots and return their answers.
 *
 * Count of the generators is returned in count. The result is newly
 * allocated array of strings, the results of the generators. It is
 * up to the caller to free it.
 */
char **register_call_stats_generators(size_t *count, struct interpreter *interpreter);

/*
 * Provide list of all the spec submodules to include into the main module, registered
 * through register_stat_generator.
 *
 * Same form as get_capabilities.
 */
const char *const *get_stat_defs();

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
