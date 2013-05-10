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

#endif
