#include "interpreter.h"

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <stdlib.h>

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

void interpreter_destroy(struct interpreter *interpreter) {
	lua_close(interpreter->state);
	free(interpreter);
}
