/*
 * File:   lxml2.h
 * Author: difuntoruma
 *
 * Created on November 19, 2012, 3:18 PM
 */

#ifndef __LUA_LIBXML2_H__
#define	__LUA_LIBXML2_H__

#define lua_c

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <libxml/parser.h>
#include <libxml/tree.h>

#define lxml2_dbg(fmt,...)	fprintf(stdout, "%s %d: " fmt, \
					__func__, __LINE__, ##__VA_ARGS__)
#define lxml2_info(fmt,...)	fprintf(stdout, fmt, ##__VA_ARGS__)

struct lxml2Object {
	xmlDocPtr doc;
};

int lxml2_init(lua_State *L);

// ================= BEGIN of 5.2 Features INJECTION ====================
#define LUA_OK 0

#define luaL_newlibtable(L,l)	\
  lua_createtable(L, 0, sizeof(l)/sizeof((l)[0]) - 1)

#define luaL_newlib(L,l)	(luaL_newlibtable(L,l), luaL_setfuncs(L,l,0))

void luaL_setfuncs (lua_State *L, const luaL_Reg *l, int nup);
void luaL_setmetatable (lua_State *L, const char *tname);
// ================= END of 5.2 Features INJECTION ====================

#endif	/* __LUA_LIBXML2_H__ */
