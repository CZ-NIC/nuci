#include "interpreter.h"

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

struct interpreter *interpreter_create(void) {
	struct interpreter *result = malloc(sizeof *result);
	*result = (struct interpreter) {
		.state = luaL_newstate()
	};
	luaL_openlibs(result->state);
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
		size_t len = strlen(ent->d_name);
		if (len < 4 || strcmp(".lua", ent->d_name + len - 4) != 0)
			// Too short or different last 4 leters.
			continue;

		size_t complete_len = len + path_len + 2; // 1 for '\0', 1 for '/'
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
