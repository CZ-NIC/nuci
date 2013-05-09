#ifndef INTERPRETER_H
#define INTERPRETER_H

/*
 * The Lua interpreter is hidden inside this module.
 */

struct interpreter;

struct interpreter *interpreter_create(void);
void interpreter_destroy(struct interpreter *interpreter);

#endif
