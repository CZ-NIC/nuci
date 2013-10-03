#include "../src/xmlwrap.h"
#include "../src/interpreter.h"
#include "../src/logging.h"

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <libxml/parser.h>
#include <libxml/tree.h>

int main(int argc, const char *argv[]) {
	(void) argc;
	(void) argv;

	log_set_stderr(NLOG_TRACE);
	log_set_syslog(NLOG_DISABLE);

	//libxml2 init
	xmlInitParser();
	LIBXML_TEST_VERSION

	struct interpreter *interpreter = interpreter_create();
	lua_State *lua = interpreter_get_lua(interpreter);

	for (const char **arg = argv + 1; *arg; arg ++) {
		fprintf(stderr, "Running file %s\n", *arg);
		fprintf(stderr, "================================================================================\n");
		if (luaL_dofile(lua, *arg) != 0) {
			fprintf(stderr, "Failure test %s: %s\n", *arg, lua_tostring(lua, -1));
			return 1;
		}
	}

	interpreter_destroy(interpreter);

	//libxml2 cleanup
	xmlCleanupParser();
	xmlMemoryDump();

	return 0;
}
