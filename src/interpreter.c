#include "interpreter.h"
#include "register.h"

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>
#include <assert.h>
#include <sys/types.h>
#include <dirent.h>

static int register_string(lua_State *lua, void (*function)(const char*), const char *name) {
	int param_count = lua_gettop(lua);
	if (param_count != 1)
		luaL_error(lua, "%s expects 1 parameter, %d given", name, param_count);
	const char *capability = lua_tostring(lua, 1);
	if (!capability)
		luaL_error(lua, "A non-string parameter passed to %s", name);
	function(capability);
	return 0; // No results from this function
}

static int register_capability_lua(lua_State *lua) {
	return register_string(lua, register_capability, "register_capability");
}

static int register_submodel_lua(lua_State *lua) {
	return register_string(lua, register_submodel, "register_submodel");
}

static int register_stat_generator_lua(lua_State *lua) {
	int param_count = lua_gettop(lua);
	if (param_count != 2)
		luaL_error(lua, "register_stat_generator expects 2 parameter, %d given", param_count);
	lua_callback callback = luaL_ref(lua, LUA_REGISTRYINDEX); // Copy the function to the registry
	register_stat_generator(lua_tostring(lua, 1), callback);
	return 0; // No results
}

static int register_datastore_provider_lua(lua_State *lua) {
	int param_count = lua_gettop(lua);
	if (param_count != 2)
		luaL_error(lua, "register_datastore_provider expects 2 parameter, %d given", param_count);
	lua_datastore datastore = luaL_ref(lua, LUA_REGISTRYINDEX); // Copy the object to the registry
	register_datastore_provider(lua_tostring(lua, 1), datastore);
	return 0; // No results
}

static void error(const char *format, ...) {
	// TODO: Unify logging
	va_list args;
	va_start(args, format);
	vfprintf(stderr, format, args);
	va_end(args);
}

struct interpreter {
	lua_State *state;
};

static void add_func(struct interpreter *interpreter, const char *name, lua_CFunction function) {
	lua_pushcfunction(interpreter->state, function);
	lua_setglobal(interpreter->state, name);
}

struct interpreter *interpreter_create(void) {
	struct interpreter *result = malloc(sizeof *result);
	*result = (struct interpreter) {
		.state = luaL_newstate()
	};
	luaL_openlibs(result->state);
	add_func(result, "register_capability", register_capability_lua);
	add_func(result, "register_submodel", register_submodel_lua);
	add_func(result, "register_stat_generator", register_stat_generator_lua);
	add_func(result, "register_datastore_provider", register_datastore_provider_lua);
	return result;
}

bool interpreter_load_plugins(struct interpreter *interpreter, const char *path) {
	DIR *dir = opendir(path);
	if (!dir) {
		error("Can't read directory %s (%s)\n", path, strerror(errno));
		return false;
	}

	size_t path_len = strlen(path);
	struct dirent *ent;
	while ((ent = readdir(dir))) {
		// First, check if it ends with .lua
		const char *dot = rindex(ent->d_name, '.');
		// Either no file extention, or the extention is not lua nor luac
		if (!dot || (strcmp(dot, ".lua") != 0 && strcmp(dot, ".luac") != 0))
			continue;

		size_t complete_len = strlen(ent->d_name) + path_len + 2; // 1 for '\0', 1 for '/'
		char filename[complete_len];
		assert((size_t ) snprintf(filename, complete_len, "%s/%s", path, ent->d_name) == complete_len - 1);
		if (luaL_dofile(interpreter->state, filename) != 0) {
			// The error is on the top of the string, at index -1
			error("Failure to load lua plugin %s: %s\n", ent->d_name, lua_tostring(interpreter->state, -1));
			return false;
		}
	}

	closedir(dir);
	return true;
}

void interpreter_destroy(struct interpreter *interpreter) {
	lua_close(interpreter->state);
	free(interpreter);
}

const char *interpreter_call_str(struct interpreter *interpreter, lua_callback callback) {
	lua_State *lua = interpreter->state;
	lua_checkstack(lua, LUA_MINSTACK); // Make sure it works even when called multiple times from C
	// Copy the function to the stack
	lua_rawgeti(lua, LUA_REGISTRYINDEX, callback);
	// No parameters for the callback functions, none pushed. We want 1 result.
	// TODO: Handle failure somehow? lua_pcall?
	lua_call(lua, 0, 1);
	return lua_tostring(lua, -1); // The thing on top is the string. Hopefuly.
}

const char *interpreter_get_config(struct interpreter *interpreter, lua_datastore datastore, const char **error) {
	assert(error);
	lua_State *lua = interpreter->state;
	lua_checkstack(lua, LUA_MINSTACK); // Make sure it works even when called multiple times from C
	// Pick up the data store
	lua_rawgeti(lua, LUA_REGISTRYINDEX, datastore);
	lua_getfield(lua, -1, "get_config"); // The function
	lua_pushvalue(lua, -2); // The first parameter of a method is the object it is called on
	// Single parameter - the object.
	// Two results - the string and error. In case of success, the second is nil.
	lua_call(lua, 1, 2);
	// Convert the error only if there's one.
	if (!lua_isnil(lua, -1))
		*error = lua_tostring(lua, -1);
	if (lua_isnil(lua, -2))
		return NULL;
	else
		return lua_tostring(lua, -2);
}

void interpreter_set_config(struct interpreter *interpreter, lua_datastore datastore, const char *config, const char **error) {
	assert(error);
	lua_State *lua = interpreter->state;
	lua_checkstack(lua, LUA_MINSTACK); // Make sure it works even when called multiple times from C
	// Pick up the data store
	lua_rawgeti(lua, LUA_REGISTRYINDEX, datastore);
	lua_getfield(lua, -1, "set_config"); // The function
	lua_pushvalue(lua, -2); // The datastore is the first parameter
	lua_pushstring(lua, config);
	// Two parameters - the object and the config
	// Single result, if set, it is the error
	lua_call(lua, 2, 1);
	if (!lua_isnil(lua, -1))
		*error = lua_tostring(lua, -1);
}
