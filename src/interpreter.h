#ifndef INTERPRETER_H
#define INTERPRETER_H

/*
 * The Lua interpreter is hidden inside this module.
 */

// Opaque handle to the interpreter
struct interpreter;

// Create a lua interpreter and load the standard libraries
struct interpreter *interpreter_create(void);
// Destroy the lua interpreter
void interpreter_destroy(struct interpreter *interpreter);

#endif
