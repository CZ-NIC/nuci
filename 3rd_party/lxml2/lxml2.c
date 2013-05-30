/*
* Copyright (C) 2012 Alvin Difuntorum <alvinpd09@gmail.com>
*
* Permission is hereby granted, free of charge, to any person obtaining
* a copy of this software and associated documentation files (the
* "Software"), to deal in the Software without restriction, including
* without limitation the rights to use, copy, modify, merge, publish,
* distribute, sublicense, and/or sell copies of the Software, and to
* permit persons to whom the Software is furnished to do so, subject to
* the following conditions:
*
* The above copyright notice and this permission notice shall be
* included in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#include <stdio.h>
#include <stdlib.h>

#include "lxml2.h"

#define LXML2_XMLDOC		"xmlDocPtr"
#define LXML2_XMLNODE		"xmlNodePtr"

/*
 * We doesn't need it now, but it should be useful.
 */
#if 0
static void lua_stack_dump(lua_State *L, const char *func)
{
	int i;
	int top = lua_gettop(L);

	printf("%s stack: ", func);
	for (i = 1; i <= top; i++) { /* repeat for each level */
		int t = lua_type(L, i);

		switch (t) {
		case LUA_TSTRING: { /* strings */
			printf("%d:'%s'", i, lua_tostring(L, i));
			break;
			}
		case LUA_TBOOLEAN: { /* booleans */
			printf(lua_toboolean(L, i) ? "true" : "false");
			break;
			}
		case LUA_TNUMBER: { /* numbers */
			printf("%d:%g", i, lua_tonumber(L, i));
			break;
		}
		default: { /* other values */
			printf("%d:%s", i, lua_typename(L, t));
			break;
			}
		}
		printf(" "); /* put a separator */
	}

	printf("\n"); /* end the listing */
}
#endif
/*
 * Creates an xmlDocPtr document and returns the handle to lua
 */
static int lxml2mod_ReadFile(lua_State *L)
{
	int options = lua_tointeger(L, 3);
	const char *filename = luaL_checkstring(L, 1);
	const char *encoding = lua_tostring(L, 2);

	xmlDocPtr doc = NULL;
	struct lxml2Object *xml2 = NULL;

	doc = xmlReadFile(filename, encoding, options);
	if (!doc)
		return luaL_error(L, "Failed to open xml file: %s", filename);

	xml2 = lua_newuserdata(L, sizeof(*xml2));
	luaL_setmetatable(L, LXML2_XMLDOC);

	xml2->doc = doc;

	//don't do this in nuci
	//lua_stack_dump(L, __func__);
	return 1;
}

/* stop using module
static const luaL_Reg lxml2mod[] = {
	{ "ReadFile", lxml2mod_ReadFile },
	{ NULL, NULL }
};
*/

/*
 * lxml2xmlNode object handlers
 */

static int lxml2xmlNode_ChildrenNode(lua_State *L)
{
	xmlNodePtr cur = lua_touserdata(L, 1);

	if (cur && cur->xmlChildrenNode) {
		lua_pushlightuserdata(L, cur->xmlChildrenNode);
		luaL_setmetatable(L, LXML2_XMLNODE);
	} else {
		lua_pushnil(L);
	}

	return 1;
}

static int lxml2xmlNode_name(lua_State *L)
{
	xmlNodePtr cur = lua_touserdata(L, 1);

	if (cur)
		lua_pushstring(L, (const char *) cur->name);
	else
		lua_pushnil(L);

	return 1;
}

static int lxml2xmlNode_next(lua_State *L)
{
	xmlNodePtr cur = lua_touserdata(L, 1);

	if (cur && cur->next) {
		lua_pushlightuserdata(L, cur->next);
		luaL_setmetatable(L, LXML2_XMLNODE);
	} else {
		lua_pushnil(L);
	}

	return 1;
}

static int lxml2xmlNode_tostring(lua_State *L)
{
	xmlNodePtr cur = lua_touserdata(L, 1);

	lua_pushfstring(L, "(xmlNode@%p)", cur);

	return 1;
}

static const luaL_Reg lxml2xmlNode[] = {
	{ "ChildrenNode", lxml2xmlNode_ChildrenNode },
	{ "Name", lxml2xmlNode_name },
	{ "Next", lxml2xmlNode_next },
	// { "__gc", lxml2xmlNode_gc }, # FIXME Anything to free here?
	{ "__tostring", lxml2xmlNode_tostring },
	{ NULL, NULL }
};

/*
 * lxml2xmlDoc object handlers
 */

static int lxml2xmlDoc_GetRootElement(lua_State *L)
{
	xmlNodePtr cur = NULL;
	struct lxml2Object *xml2 = lua_touserdata(L, 1);

	cur = xmlDocGetRootElement(xml2->doc);
	if (cur) {
		lua_pushlightuserdata(L, cur);
		luaL_setmetatable(L, LXML2_XMLNODE);
	} else {
		lua_pushnil(L);
	}

	//don't do this in nuci
	//lua_stack_dump(L, __func__);

	return 1;
}

static int lxml2xmlDoc_NodeListGetString(lua_State *L)
{
	xmlChar *v;
	xmlDocPtr doc = lua_touserdata(L, 1);
	xmlDocPtr cur = lua_touserdata(L, 2);

	v = xmlNodeListGetString(doc, cur->xmlChildrenNode, 1);
	if (v) {
		lua_pushfstring(L, "%s", v);
		xmlFree(v);
	} else {
		lua_pushnil(L);
	}

	return 1;
}

static int lxml2xmlDoc_gc(lua_State *L)
{
	struct lxml2Object *xml2 = lua_touserdata(L, 1);

	if (xml2->doc != NULL)
		xmlFreeDoc(xml2->doc);

	return 0;
}

static int lxml2xmlDoc_tostring(lua_State *L)
{
	struct lxml2Object *xml2 = lua_touserdata(L, 1);

	lua_pushfstring(L, "(xml2:xmlDoc@%p:%p)", xml2, xml2->doc);

	return 1;
}

static const luaL_Reg lxml2xmlDoc[] = {
	{ "GetRootElement", lxml2xmlDoc_GetRootElement },
	{ "NodeListGetString", lxml2xmlDoc_NodeListGetString },
	{ "__gc", lxml2xmlDoc_gc },
	{ "__tostring", lxml2xmlDoc_tostring },
	{ NULL, NULL }
};

/*
 * Register function in the package on top of stack.
 */
static void add_func(lua_State *L, const char *name, lua_CFunction function) {
	lua_pushcfunction(L, function);
	lua_setglobal(L, name);
}

/*
 * Lua libxml2 binding registration
 */

int lxml2_init(lua_State *L)
{
	// New table for the package
	lua_newtable(L);
	add_func(L, "ReadFile", lxml2mod_ReadFile);
	// Push the package as lxml2 (which pops it)
	lua_setglobal(L, "lxml2");

	/*
	 * Register metatables
	 */

	/* Register metatable for the xmlDoc objects */

	luaL_newmetatable(L, LXML2_XMLDOC); /* create metatable to handle xmlDoc objects */
	lua_pushvalue(L, -1);               /* push metatable */
	lua_setfield(L, -2, "__index");     /* metatable.__index = metatable */
	luaL_setfuncs(L, lxml2xmlDoc, 0);   /* add xmlDoc methods to the new metatable */
	lua_pop(L, 1);                      /* pop new metatable */

	/* Register metatable for the xmlNode objects */

	luaL_newmetatable(L, LXML2_XMLNODE); /* create metatable to handle xmlNode objects */
	lua_pushvalue(L, -1);               /* push metatable */
	lua_setfield(L, -2, "__index");     /* metatable.__index = metatable */
	luaL_setfuncs(L, lxml2xmlNode, 0);  /* add xmlNode methods to the new metatable */
	lua_pop(L, 1);

	return 1;
}

// ================= BEGIN of 5.2 Features INJECTION ====================
/*
** set functions from list 'l' into table at top - 'nup'; each
** function gets the 'nup' elements at the top as upvalues.
** Returns with only the table at the stack.
*/
void luaL_setfuncs (lua_State *L, const luaL_Reg *l, int nup) {
//It doesn't work with "static"
  luaL_checkstack(L, nup, "too many upvalues");
  for (; l->name != NULL; l++) {  /* fill the table with given functions */
	int i;
	for (i = 0; i < nup; i++)  /* copy upvalues to the top */
	  lua_pushvalue(L, -nup);
	lua_pushcclosure(L, l->func, nup);  /* closure with those upvalues */
	lua_setfield(L, -(nup + 2), l->name);
  }
  lua_pop(L, nup);  /* remove upvalues */
}

void luaL_setmetatable (lua_State *L, const char *tname) {
//It doesn't work with "static"
  luaL_getmetatable(L, tname);
  lua_setmetatable(L, -2);
}

// ================= END of 5.2 Features INJECTION ====================

/* End of file */
