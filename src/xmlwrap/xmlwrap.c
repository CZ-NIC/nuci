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

#include "xmlwrap.h"

#include <libxml/parser.h>
#include <libxml/tree.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#define WRAP_XMLDOC		"xmlDocPtr"
#define WRAP_XMLNODE		"xmlNodePtr"

struct xmlwrap_object {
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
static void lua_stack_dump(lua_State *L, const char *func) {
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
static int mod_read_file(lua_State *L) {
	int options = lua_tointeger(L, 3);
	const char *filename = luaL_checkstring(L, 1);
	const char *encoding = lua_tostring(L, 2);

	xmlDocPtr doc = NULL;
	struct xmlwrap_object *xml2 = NULL;

	doc = xmlReadFile(filename, encoding, options);
	if (!doc)
		return luaL_error(L, "Failed to open xml file: %s", filename);

	xml2 = lua_newuserdata(L, sizeof(*xml2));
	luaL_setmetatable(L, WRAP_XMLDOC);

	xml2->doc = doc;
	fprintf(stderr, "Created XML DOC from file %p\n", (void *) doc);

	return 1;
}

static int mod_read_memory(lua_State *L) {
	size_t len;
	const char *memory = luaL_checklstring(L, 1, &len);

	xmlDocPtr doc = xmlReadMemory(memory, len, "<memory>", NULL, 0);
	if (!doc)
		return luaL_error(L, "Failed to read xml string");

	struct xmlwrap_object *xml2 = lua_newuserdata(L, sizeof(*xml2));
	luaL_setmetatable(L, WRAP_XMLDOC);

	xml2->doc = doc;
	fprintf(stderr, "Created XML DOC from mem %p\n", (void *) doc);

	return 1;
}

/*
 * Node handlers
 */

static int node_name(lua_State *L) {
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

static const char *translate_node_type(xmlElementType type) {
	switch (type) {
		case XML_ELEMENT_NODE:
			return "XML_ELEMENT_NODE";
		case XML_ATTRIBUTE_NODE:
			return "XML_ATTRIBUTE_NODE";
		case XML_TEXT_NODE:
			return "XML_TEXT_NODE";
		case XML_CDATA_SECTION_NODE:
			return "XML_CDATA_SECTION_NODE";
		case XML_ENTITY_REF_NODE:
			return "XML_ENTITY_REF_NODE";
		case XML_ENTITY_NODE:
			return "XML_ENTITY_NODE";
		case XML_PI_NODE:
			return "XML_PI_NODE";
		case XML_COMMENT_NODE:
			return "XML_COMMENT_NODE";
		case XML_DOCUMENT_NODE:
			return "XML_DOCUMENT_NODE";
		case XML_DOCUMENT_TYPE_NODE:
			return "XML_DOCUMENT_TYPE_NODE";
		case XML_DOCUMENT_FRAG_NODE:
			return "XML_DOCUMENT_FRAG_NODE";
		case XML_NOTATION_NODE:
			return "XML_NOTATION_NODE";
		case XML_HTML_DOCUMENT_NODE:
			return "XML_HTML_DOCUMENT_NODE";
		case XML_DTD_NODE:
			return "XML_DTD_NODE";
		case XML_ELEMENT_DECL:
			return "XML_ELEMENT_DECL";
		case XML_ATTRIBUTE_DECL:
			return "XML_ATTRIBUTE_DECL";
		case XML_ENTITY_DECL:
			return "XML_ENTITY_DECL";
		case XML_NAMESPACE_DECL:
			return "XML_NAMESPACE_DECL";
		case XML_XINCLUDE_START:
			return "XML_XINCLUDE_START";
		case XML_XINCLUDE_END:
			return "XML_XINCLUDE_END";
		case XML_DOCB_DOCUMENT_NODE:
			return "XML_DOCB_DOCUMENT_NODE";
		default:
			return "VALUE IS NOT ON THE LIST";
	}
}


static int node_type(lua_State *L) {
	xmlNodePtr node = lua_touserdata(L, 1);

	if (node == NULL) return luaL_error(L, "type: Invalid node");

	lua_pushstring(L, translate_node_type(node->type));

	return 1;
}

static int node_tostring(lua_State *L) {
	xmlNodePtr node = lua_touserdata(L, 1);

	if (node == NULL) return luaL_error(L, "tostring: Invalid node");

	lua_pushfstring(L, "(xmlNode@%p)", node);

	return 1;
}

static int node_children_node(lua_State *L) {
	xmlNodePtr node = lua_touserdata(L, 1);

	if (node == NULL) return luaL_error(L, "first_child: Invalid node");

	if (node && node->children) {
		lua_pushlightuserdata(L, node->children);
		luaL_setmetatable(L, WRAP_XMLNODE);
	} else {
		lua_pushnil(L);
	}

	return 1;
}

static int node_next(lua_State *L) {
	xmlNodePtr node = lua_touserdata(L, 1);

	if (node == NULL) return luaL_error(L, "next: Invalid node");

	if (node && node->next) {
		lua_pushlightuserdata(L, node->next);
		luaL_setmetatable(L, WRAP_XMLNODE);
	} else {
		lua_pushnil(L);
	}

	return 1;
}

static int node_iterate_next(lua_State *L) {
	if (lua_isnil(L, 2)) { // The first iteration
		// Copy the state
		lua_pushvalue(L, 1);
	} else {
		lua_remove(L, 1); // Drop the state and call next on the value
		node_next(L);
	}
	return 1;
}

static int node_iterate(lua_State *L) {
	lua_pushcfunction(L, node_iterate_next); // The 'next' function
	node_children_node(L); // The 'state'
	// One implicit nil.
	return 2;
}

static int node_get_attr(lua_State *L) {
	xmlNodePtr node = lua_touserdata(L, 1);
	const char *name = luaL_checkstring(L, 2);
	const char *ns = lua_tostring(L, 3);
	xmlChar *prop;

	if (node == NULL) return luaL_error(L, "attribute: Invalid node");
	if (node->type != XML_ELEMENT_NODE) return luaL_error(L, "attribute: Invalid node type (not element node)");

	if (name == NULL) return luaL_error(L, "attribute: Specify attribute name");

	if (ns) {
		prop = xmlGetNsProp(node, BAD_CAST name, BAD_CAST ns);
	} else {
		prop = xmlGetNoNsProp(node, BAD_CAST name);
	}

	lua_pushstring(L, (char *) prop);
	xmlFree(prop);

	return 1;
}

static int node_set_attr(lua_State *L) {
	xmlNodePtr node = lua_touserdata(L, 1);
	const char *name = lua_tostring(L, 2);
	const char *value = lua_tostring(L, 3);
	const char *ns_str = lua_tostring(L, 4);
	xmlNsPtr ns = NULL;

	if (node == NULL) return luaL_error(L, "set_attribute: Invalid node");
	if (node->type != XML_ELEMENT_NODE) return luaL_error(L, "set_attribute: Invalid node type (not element node)");
	if (name == NULL) return luaL_error(L, "set_attribute: Specify attribute name");
	if (value == NULL) return luaL_error(L, "set_attribute: Specify attribute value");

	if (ns_str != NULL) {
		ns = xmlSearchNsByHref(node->doc, node, BAD_CAST ns_str);
		if (ns == NULL) return luaL_error(L, "Namespace not registered yet.");
		if (ns->prefix == NULL) return luaL_error(L, "Namespace has not registered prefix.");
	}

	if (ns == NULL) {
		xmlSetProp(node, BAD_CAST name, BAD_CAST value);
	} else {
		xmlSetNsProp(node, ns, BAD_CAST name, BAD_CAST value);
	}

	return 0;
}

static int node_rm_attr(lua_State *L) {
	xmlNodePtr node = lua_touserdata(L, 1);
	const char *name = lua_tostring(L, 2);
	const char *ns_str = lua_tostring(L, 3);
	xmlNsPtr ns = NULL;
	int ret;

	if (node == NULL) return luaL_error(L, "rm_attribute: Invalid node");
	if (node->type != XML_ELEMENT_NODE) return luaL_error(L, "rm_attribute: Invalid node type (not element node)");
	if (name == NULL) return luaL_error(L, "rm_attribute: Specify attribute name");

	if (ns_str != NULL) {
		ns = xmlSearchNsByHref(node->doc, node, BAD_CAST ns_str);
		if (ns == NULL) return luaL_error(L, "Namespace not defined yet.");
	}

	if (ns == NULL) {
		ret = xmlUnsetProp(node, BAD_CAST name);
	} else {
		ret = xmlUnsetNsProp(node, ns, BAD_CAST name);
	}

	/**
	 * Boolean variable indicates TRUE as 1 and FALSE as 0
	 * xmlUnset*Prop returns O for OK and -1 for error
	 * 0(ok) + 1 = 1(true) and -1(error) + 1 = 0(false)
	 */
	lua_pushboolean(L, ret+1);

	return 1;
}
//#define MY_OWN_GET_TEXT
#ifdef MY_OWN_GET_TEXT
/**
 * Function expected parent node off all text and CDATA nodes you want
 */
static int node_get_text(lua_State *L) {
	xmlNodePtr node = lua_touserdata(L, 1);

	if (node == NULL) return luaL_error(L, "get_text: Invalid parent node");
	if (node->type != XML_ELEMENT_NODE) return luaL_error(L, "get_text: Invalid parent node type (not element node)");

	char *str = NULL;
	size_t len;

	/**
	 * This loop needs some explanation:
	 * Multiple realloc is inefficient. However, data that we are expecting,
	 * will be composed from one or two text nodes. I hope this solution will not be an issue.
	 */
	for (xmlNodePtr child = node->children; child; child = child->next) {
		if (child->type == XML_TEXT_NODE || child->type == XML_CDATA_SECTION_NODE) {
			if (str == NULL) {
				len = strlen((const char *) child->content);
				str = (char *) calloc(len+1, sizeof(char));
				str[0] = '\0';
				strcat(str, (const char *) child->content);
			} else {
				len = strlen((const char *) child->content);
				str = (char *)realloc(str, strlen(str)+len+1);
				strcat(str, (const char *) child->content);
			}
		}
	}

	lua_pushstring(L, str);

	free(str);

	return 1;
}
#else //MY_OWN_GET_TEXT
/**
 * Function expected parent node off all text and CDATA nodes you want
 * This function uses internal libxml2 function xmlNodeGetContent.
 * xmlNodeGetContent returns text from all text nodes, CDATA nodes and
 * recursively from all children element nodes.
 */
static int node_get_text(lua_State *L) {
	xmlNodePtr node = lua_touserdata(L, 1);

	if (node == NULL) return luaL_error(L, "get_text: Invalid parent node");
	if (node->type != XML_ELEMENT_NODE) return luaL_error(L, "get_text: Invalid parent node type (not element node)");

	xmlChar *str = xmlNodeGetContent(node);

	lua_pushstring(L, (char *)str);

	xmlFree(str);

	return 1;
}

#endif

static int node_parent(lua_State *L) {
	xmlNodePtr cur = lua_touserdata(L, 1);

	if (cur && cur->parent) {
		lua_pushlightuserdata(L, cur->parent);
		luaL_setmetatable(L, WRAP_XMLNODE);
		return 1;
	}

	return 0;
}

/*
 * Document handlers
 */

static int doc_get_root_element(lua_State *L) {
	xmlNodePtr cur = NULL;
	struct xmlwrap_object *xml2 = lua_touserdata(L, 1);

	cur = xmlDocGetRootElement(xml2->doc);
	if (cur) {
		lua_pushlightuserdata(L, cur);
		luaL_setmetatable(L, WRAP_XMLNODE);
	} else {
		lua_pushnil(L);
	}

	//don't do this in nuci
	//lua_stack_dump(L, __func__);

	return 1;
}

static int doc_node_list_get_string(lua_State *L) {
	xmlChar *v;
	xmlDocPtr doc = lua_touserdata(L, 1);
	xmlDocPtr cur = lua_touserdata(L, 2);

	v = xmlNodeListGetString(doc, cur->children, 1);
	if (v) {
		lua_pushfstring(L, "%s", v);
		xmlFree(v);
	} else {
		lua_pushnil(L);
	}

	return 1;
}

static int doc_gc(lua_State *L) {
	struct xmlwrap_object *xml2 = lua_touserdata(L, 1);
	fprintf(stderr, "GC XML document %p\n", (void *) xml2->doc);

	if (xml2->doc != NULL)
		xmlFreeDoc(xml2->doc);

	return 0;
}

static int doc_tostring(lua_State *L) {
	struct xmlwrap_object *xml2 = lua_touserdata(L, 1);

	lua_pushfstring(L, "(xml2:xmlDoc@%p:%p)", xml2, xml2->doc);

	return 1;
}

/*
 * Create new document and edit document handlers
 */
static int new_xml_doc(lua_State *L) {
	const char *name = lua_tostring(L, 1);
	const char *ns_href = lua_tostring(L, 2);
	xmlNsPtr ns = NULL;

	if (name == NULL) return luaL_error(L, "new_xml_doc needs name of root node.");
	/**
	 * http://www.acooke.org/cute/Usinglibxm0.html was very helpful with this issue
	 */
	xmlDocPtr doc = xmlNewDoc(BAD_CAST "1.0"); //create document
	xmlNodePtr root_node = xmlNewNode(NULL, BAD_CAST name); //create root node

	if (doc == NULL || root_node == NULL) return luaL_error(L, "New document allocation error.");

	if (ns_href != NULL) { //if NS is requested
		ns = xmlNewNs(root_node, BAD_CAST ns_href, NULL);
		if (ns == NULL) return luaL_error(L, "Namespace allocation error.");
		xmlSetNs(root_node, ns);
	}

	struct xmlwrap_object *xml2 = lua_newuserdata(L, sizeof(*xml2));
	luaL_setmetatable(L, WRAP_XMLDOC);

	xml2->doc = doc;
	xmlDocSetRootElement(xml2->doc, root_node);


	return 1;
}

static int node_add_child(lua_State *L) {
	xmlNodePtr node = lua_touserdata(L, 1);
	const char *name = lua_tostring(L, 2);
	const char *ns_href = lua_tostring(L, 3);
	xmlNsPtr ns = NULL;

	if (node == NULL) return luaL_error(L, "add_child: Invalid parent node");
	if (node->type != XML_ELEMENT_NODE) return luaL_error(L, "add_child: Invalid parent node type  (not element node)");
	if (name == NULL) return luaL_error(L, "I can't create node without its name");

	xmlNodePtr child;

	if (ns_href != NULL) { //add namespace requested
		ns = xmlSearchNsByHref(node->doc, node, BAD_CAST ns_href); //try to find ns
	}

	if (ns_href != NULL && ns == NULL) { //ns requested and not found
		child = xmlNewChild(node, ns, BAD_CAST name, NULL); //crete node w/o ns
		ns = xmlNewNs(child, BAD_CAST ns_href, NULL); //create namespace and define it in child
		if (ns == NULL) return luaL_error(L, "Namespace allocation error.");
		xmlSetNs(child, ns); //set new ns to child
	} else {
		child = xmlNewChild(node, ns, BAD_CAST name, NULL); //ns nor requested ir was found... use it
	}

	lua_pushlightuserdata(L, child);
	luaL_setmetatable(L, WRAP_XMLNODE);

	return 1;
}

/**
 * This function recursively delete this node and it's childs.
 * void return code is OK, because both function has void too
 */
static void internal_delete_node(xmlNodePtr node) {
	xmlUnlinkNode(node);
	xmlFreeNode(node);
}

/**
 * This function enables to delete some node itself
 */
static int node_delete_node(lua_State *L) {
	xmlNodePtr node = lua_touserdata(L, 1);

	if (node == NULL) return luaL_error(L, "delete_node: Invalid parent node");
	if (node->type != XML_ELEMENT_NODE) return luaL_error(L, "delete_node: Invalid parent node type (not element node)");

	internal_delete_node(node);

	return 0;
}

/**
 * New API expected new behavior of this function
 * Example: node:set_text("text");
 * 	- node is regular node, not the text one
 * 	- text will be set as new child of node
 * 	- if node has some text as it's child, it will be replaced
 *	- replacing text mean delete all text and CDATA nodes and crete new text one
 */
static int node_set_text(lua_State *L) {
	xmlNodePtr node = lua_touserdata(L, 1);
	const char *text = lua_tostring(L, 2);

	if (node == NULL) return luaL_error(L, "set_text: Invalid parent node");
	if (node->type != XML_ELEMENT_NODE) return luaL_error(L, "set_text: Invalid parent node type (not element node)");
	if (text == NULL) return luaL_error(L, "I can't create node without its name");

	//First, delete all CDATA and text nodes
	//It is not good idea to use for loop...
	xmlNodePtr child = node->children;
	xmlNodePtr to_del;
	while (child) {
		if (child->type == XML_TEXT_NODE || child->type == XML_CDATA_SECTION_NODE) {
			to_del = child;
			child = child->next;

			internal_delete_node(to_del);
		} else {
			child = child->next;
		}
	}

	//Second, create new text node
	xmlNodePtr text_node = xmlNewText(BAD_CAST text);
	xmlAddChild(node, text_node);

	return 0;
}

static int node_register_ns(lua_State *L) {
	xmlNodePtr node = lua_touserdata(L, 1);
	const char *href = lua_tostring(L, 2);
	const char *pref = lua_tostring(L, 3);
	xmlNsPtr ns = NULL;

	if (node == NULL) return luaL_error(L, "Invalid xml document");
	if (href == NULL) return luaL_error(L, "Specify namespace href");
	if (pref == NULL) return luaL_error(L, "Specify namespace prefix");

	ns = xmlSearchNsByHref(node->doc, node, BAD_CAST href);
	if (ns != NULL) { //namespace exists, but has not prefix defined
		if (ns->prefix == NULL) {
			ns->prefix = BAD_CAST strdup(pref); //hack prefix into structure
			return 0;
		}
	}

	ns = xmlNewNs(node, BAD_CAST href, BAD_CAST pref);
	if (ns == NULL) return luaL_error(L, "Namespace allocation error");

	return 0;
}

static int doc_strdump(lua_State *L) {
	struct xmlwrap_object *xml2 = lua_touserdata(L, 1);

	if (xml2 == NULL) return luaL_error(L, "Invalid xml document");

	xmlChar *str;
	int size;

	xmlDocDumpMemory(xml2->doc, &str, &size);

	if (str == NULL) {
		return luaL_error(L, "String Dump error");
	}

	lua_pushstring(L, (char *)str);

	free(str);

	return 1;
}

static const luaL_Reg xmlwrap_node[] = {
	{ "first_child", node_children_node },
	{ "name", node_name },
	{ "type", node_type },
	{ "next", node_next },
	{ "iterate", node_iterate },
	{ "attribute", node_get_attr },
	{ "set_attribute", node_set_attr },
	{ "rm_attribute", node_rm_attr },
	{ "text", node_get_text },
	{ "set_text", node_set_text },
	{ "parent", node_parent },
	{ "add_child", node_add_child },
	{ "register_ns", node_register_ns },
	{ "delete", node_delete_node },
	// { "__gc", node_gc }, # FIXME Anything to free here?
	{ "__tostring", node_tostring },
	{ NULL, NULL }
};

static const luaL_Reg xmlwrap_doc[] = {
	{ "root", doc_get_root_element },
	{ "NodeListGetString", doc_node_list_get_string },
	{ "strdump", doc_strdump },
	{ "__gc", doc_gc },
	{ "__tostring", doc_tostring },
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

int xmlwrap_init(lua_State *L) {
	// New table for the package
	lua_newtable(L);
	add_func(L, "read_file", mod_read_file);
	add_func(L, "read_memory", mod_read_memory);
	add_func(L, "new_xml_doc", new_xml_doc);

	// Push the package as xmlwrap (which pops it)
	lua_setglobal(L, "xmlwrap");

	/*
	 * Register metatables
	 */

	/* Register metatable for the xmlDoc objects */

	luaL_newmetatable(L, WRAP_XMLDOC); /* create metatable to handle xmlDoc objects */
	lua_pushvalue(L, -1);               /* push metatable */
	lua_setfield(L, -2, "__index");     /* metatable.__index = metatable */
	luaL_setfuncs(L, xmlwrap_doc, 0);   /* add xmlDoc methods to the new metatable */
	lua_pop(L, 1);                      /* pop new metatable */

	/* Register metatable for the xmlNode objects */

	luaL_newmetatable(L, WRAP_XMLNODE); /* create metatable to handle xmlNode objects */
	lua_pushvalue(L, -1);               /* push metatable */
	lua_setfield(L, -2, "__index");     /* metatable.__index = metatable */
	luaL_setfuncs(L, xmlwrap_node, 0);  /* add xmlNode methods to the new metatable */
	lua_pop(L, 1);

	return 1;
}
