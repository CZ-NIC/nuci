#include "../src/xmlwrap/xmlwrap.h"

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

static lua_State *lua;

int main(int argc, const char *argv[]) {
	(void) argc;
	lua = luaL_newstate();
	luaL_openlibs(lua);
	xmlwrap_init(lua);
	for (const char **arg = argv + 1; *arg; arg ++) {
		if (luaL_dofile(lua, *arg) != 0) {
			fprintf(stderr, "Failure test %s: %s\n", *arg, lua_tostring(lua, -1));
			return 1;
		}
	}
	return 0;
}
