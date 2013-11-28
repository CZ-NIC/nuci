/*
 * Copyright 2013, CZ.NIC
 *
 * This file is part of NUCI configuration server.
 *
 * NUCI is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 * NUCI is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with NUCI.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef INTERPRETER_H
#define INTERPRETER_H

#include <stdbool.h>
#include <lua.h>

/*
 * The Lua interpreter is hidden inside this module.
 */

// Opaque handle to the interpreter
struct interpreter;

// Create a lua interpreter and load the standard libraries
struct interpreter *interpreter_create(void);
// Destroy the lua interpreter
void interpreter_destroy(struct interpreter *interpreter);

lua_State *interpreter_get_lua(struct interpreter *interpreter);

/*
 * Scan given directory and load and run all *.lua files there on given interpreter.
 *
 * In case of error, return false (and log the error).
 *
 * No specific order of loading is not guaranteed.
 */
bool interpreter_load_plugins(struct interpreter *interpreter, const char *path);

/*
 * And, with the right tricks, we can even compress the whole datastore
 * lua object into a single int!
 */
typedef int lua_datastore;

/*
 * Call the get_config method of the data store. The result is owned by lua and may
 * disappear any time more lua is called.
 *
 * This is meant for the methods get and get_config, which have the same interface.
 *
 * In case of error, NULL is returned and the error is flagged.
 */
const char *interpreter_get(struct interpreter *interpreter, lua_datastore datastore, const char *method);

/*
 * Call the set_config method of the data store, possibly storing the data there.
 *
 * In case of error, it is flagged by flag_error.
 */
void interpreter_set_config(struct interpreter *interpreter, lua_datastore datastore, const char *config, const char *default_op, const char *error_opt);

char *interpreter_process_user_rpc(struct interpreter *interpreter, lua_datastore ds, char *procedure, char *data);


// Error handling

/*
 * Flag if the last operation failed with error. If so, the error_index
 * is the position on lua stack containing the error description, which
 * is either lua string or lua table. It makes sure the error gets on
 * top of the stack, for future use by nc_err_create_from_lua.
 */
void flag_error(struct interpreter *interpreter, bool error, int error_index);

struct nc_err;
/*
 * Turn the error on top of stack to the libnetconf's error structure. Returns
 * NULL if there was no error. It is expected to be called sometime after
 * flag_error (though from different function probably).
 *
 * Merge with original if there was previous error. Original may be NULL.
 */
struct nc_err *nc_err_create_from_lua(struct interpreter *interpreter, struct nc_err *original);

/*
 * Do a commit or rollback (depending on the value of success).
 *
 * This aborts the program in case of any error.
 *
 * If it is successfull, it returns true, false otherwise (and it also flags error
 * and sets it, so you can call nc_err_create_from_lua later).
 */
bool interpreter_commit(struct interpreter *interpreter, bool success);

#endif
