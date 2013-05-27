#ifndef INTERPRETER_H
#define INTERPRETER_H

#include <stdbool.h>

/*
 * The Lua interpreter is hidden inside this module.
 */

// Opaque handle to the interpreter
struct interpreter;

// Create a lua interpreter and load the standard libraries
struct interpreter *interpreter_create(void);
// Destroy the lua interpreter
void interpreter_destroy(struct interpreter *interpreter);

/*
 * Scan given directory and load and run all *.lua files there on given interpreter.
 *
 * In case of error, return false (and log the error).
 *
 * No specific order of loading is not guaranteed.
 */
bool interpreter_load_plugins(struct interpreter *interpreter, const char *path);

/*
 * Every function in lua can be encoded into single int. Neat, isn't it?
 */
typedef int lua_callback;

/*
 * And, with the right tricks, we can even compress the whole datastore
 * lua object into a single int!
 */
typedef int lua_datastore;

/*
 * Call a callback and return the result as a string. The string is
 * allocated by lua and will disappear some time later (it can any time
 * any more lua call is called).
 *
 * The error is set in case something goes wrong (and the result is then
 * NULL).
 */
const char *interpreter_call_str(struct interpreter *interpreter, lua_callback callback, const char **error);

/*
 * Call the get_config method of the data store, returning the result and storing the error into
 * error.
 *
 * Both the result and the error string may disappear any time more lua code is called.
 */
const char *interpreter_get_config(struct interpreter *interpreter, lua_datastore datastore, const char **error);

/*
 * Call the set_config method of the data store, possibly storing the data there.
 *
 * The error may disappear any time more lua code is called.
 */
void interpreter_set_config(struct interpreter *interpreter, lua_datastore datastore, const char *config, const char *default_op, const char *error_opt, const char **error, const char **err_type);

#endif
