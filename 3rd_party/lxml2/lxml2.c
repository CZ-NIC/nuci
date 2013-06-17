/*
* Copyright (C) 2012 Alvin Difuntorum <alvinpd09@gmail.com>
* Copyright (C) 2013 Robin Obůrka <robin.oburka@nic.cz>
* Copyright (C) 2013 Michal Vaner <michal.vaner@nic.cz>
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

#include "lxml2.h"

#include <libxml/parser.h>
#include <libxml/tree.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdbool.h>
#include <assert.h>

#define LXML2_XMLDOC		"xmlDocPtr"
#define LXML2_XMLNODE		"xmlNodePtr"

struct lxml2Object {
	xmlDocPtr doc;
};

#define luaL_newlibtable(L,l)	\
  lua_createtable(L, 0, sizeof(l)/sizeof((l)[0]) - 1)

#define luaL_newlib(L,l)	(luaL_newlibtable(L,l), luaL_setfuncs(L,l,0))

// ================= BEGIN of 5.2 Features INJECTION ====================
/*
** set functions from list 'l' into table at top - 'nup'; each
** function gets the 'nup' elements at the top as upvalues.
** Returns with only the table at the stack.
*/
static void luaL_setfuncs (lua_State *L, const luaL_Reg *l, int nup) {
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

static void luaL_setmetatable (lua_State *L, const char *tname) {
  luaL_getmetatable(L, tname);
  lua_setmetatable(L, -2);
}

// ================= END of 5.2 Features INJECTION ====================



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

	return 1;
}

static int lxml2mod_ReadMemory(lua_State *L)
{
	size_t len;
	const char *memory = luaL_checklstring(L, 1, &len);

	xmlDocPtr doc = xmlReadMemory(memory, len, "<memory>", NULL, 0);
	if (!doc)
		return luaL_error(L, "Failed to read xml string");

	struct lxml2Object *xml2 = lua_newuserdata(L, sizeof(*xml2));
	luaL_setmetatable(L, LXML2_XMLDOC);

	xml2->doc = doc;

	return 1;
}

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

	if (cur) {
		lua_pushstring(L, (const char *) cur->name);
		/*
		 * The XML_DOCUMENT_NODE has garbage in the ns. We are probably
		 * not supposed to look in there.
		 */
		if (cur->ns && cur->type != XML_DOCUMENT_NODE) {
			lua_pushstring(L, (const char *) cur->ns->href);
			return 2;
		}
		return 1;
	} else {
		return 0;
	}
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

static int lxml2xmlNode_iterate_next(lua_State *L)
{
	if (lua_isnil(L, 2)) { // The first iteration
		// Copy the state
		lua_pushvalue(L, 1);
	} else {
		lua_remove(L, 1); // Drop the state and call next on the value
		lxml2xmlNode_next(L);
	}
	return 1;
}

static int lxml2xmlNode_iterate(lua_State *L)
{
	lua_pushcfunction(L, lxml2xmlNode_iterate_next); // The 'next' function
	lxml2xmlNode_ChildrenNode(L); // The 'state'
	// One implicit nil.
	return 2;
}

static int lxml2xmlNode_getProp(lua_State *L)
{
	xmlNodePtr cur = lua_touserdata(L, 1);
	const char *name = luaL_checkstring(L, 2);
	const char *ns = lua_tostring(L, 3);
	xmlChar *prop;
	if (ns) {
		prop = xmlGetNsProp(cur, (const xmlChar *) name, (const xmlChar *) ns);
	} else {
		prop = xmlGetNoNsProp(cur, (const xmlChar *) name);
	}
	lua_pushstring(L, (char *) prop);
	xmlFree(prop);
	return 1;
}

static int lxml2xmlNode_getText(lua_State *L)
{
	xmlNodePtr cur = lua_touserdata(L, 1);
	if (cur->type == XML_TEXT_NODE) {// This is directly the text node, get the content
		lua_pushstring(L, (const char *) cur->content);
		return 1;
	} else {// Scan the direct children if one of them is text. Pick the first one to be so.
		for (xmlNodePtr child = cur->children; child; child = child->next)
			if (child->type == XML_TEXT_NODE) {
				lua_pushstring(L, (const char *) child->content);
				return 1;
			}
		// No text found and run out of children.
		return 0;
	}
}

static int lxml2xmlNode_setText(lua_State *L)
{
	xmlNodePtr cur = lua_touserdata(L, 1);
	const char *text = lua_tostring(L, 2);
	if (cur->type != XML_TEXT_NODE) { // It either is a TEXT_NODE already, or we try to find one inside.
		bool found = false;
		for (xmlNodePtr child = cur->children; child; child = child->next)
			if (child->type == XML_TEXT_NODE) {
				found = true;
				cur = child;
				break;
			}
		if (!found) {
			return luaL_error(L, "Don't know how to add text to node without one");
		}
	}
	assert(cur->type == XML_TEXT_NODE);
	xmlFree(cur->content);
	cur->content = (xmlChar *) xmlMemoryStrdup(text);
	return 0;
}

static int lxml2xmlNode_parent(lua_State *L)
{
	xmlNodePtr cur = lua_touserdata(L, 1);

	if (cur && cur->parent) {
		lua_pushlightuserdata(L, cur->parent);
		luaL_setmetatable(L, LXML2_XMLNODE);
		return 1;
	}

	return 0;
}

static const luaL_Reg lxml2xmlNode[] = {
	{ "first_child", lxml2xmlNode_ChildrenNode },
	{ "name", lxml2xmlNode_name },
	{ "next", lxml2xmlNode_next },
	{ "iterate", lxml2xmlNode_iterate },
	{ "attribute", lxml2xmlNode_getProp },
	{ "text", lxml2xmlNode_getText },
	{ "set_text", lxml2xmlNode_setText },
	{ "parent", lxml2xmlNode_parent },
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
	{ "root", lxml2xmlDoc_GetRootElement },
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
	lua_setfield(L, -2, name);
}

/*
 * Lua libxml2 binding registration
 */

int lxml2_init(lua_State *L)
{
	// New table for the package
	lua_newtable(L);
	add_func(L, "read_file", lxml2mod_ReadFile);
	add_func(L, "read_memory", lxml2mod_ReadMemory);
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
