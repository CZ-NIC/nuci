#include "../src/xmlwrap/xmlwrap.h"

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <libxml/parser.h>
#include <libxml/tree.h>

static lua_State *lua;

int main(int argc, const char *argv[]) {
	(void) argc;

	//libxml2 init
	xmlInitParser();
		LIBXML_TEST_VERSION

	//lua init
	lua = luaL_newstate();
	luaL_openlibs(lua);

	xmlwrap_init(lua);
	for (const char **arg = argv + 1; *arg; arg ++) {
		fprintf(stderr, "Running file %s\n", *arg);
		fprintf(stderr, "================================================================================\n");
		if (luaL_dofile(lua, *arg) != 0) {
			fprintf(stderr, "Failure test %s: %s\n", *arg, lua_tostring(lua, -1));
			return 1;
		}
	}

	//lua cleanup
	lua_close(lua);

	//libxml2 cleanup
	xmlCleanupParser();
	xmlMemoryDump();

	return 0;
}
