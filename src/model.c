#include "model.h"

#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>

#include <libxml/parser.h>
#include <libxml/tree.h>

#define LUA_PLUGIN_PATH PLUGIN_PATH "/lua_plugins"

char *model_path(const char *model_file) {
	size_t len = strlen(LUA_PLUGIN_PATH) + strlen(model_file) + 2; // For the '/' and for '\0'
	char *filename = malloc(len);
	size_t print_len = snprintf(filename, len, "%s/%s", LUA_PLUGIN_PATH, model_file);
	assert(print_len == len - 1);
	return filename;
}

/*
 * Take the model spec (yin) specs and extract the namespace uri of the model.
 * Pass the result onto the caller for free.
 */
static char *extract_model_uri(xmlDoc *doc) {
	assert(doc); // By now, someone should have validated the model before us.
	xmlNode *node = xmlDocGetRootElement(doc);
	assert(node);
	char *model_uri = NULL;
	for (xmlNode *current = node->children; current; current = current->next) {
		if (xmlStrcmp(current->name, (const xmlChar *) "namespace") == 0 && xmlStrcmp(current->ns->href, (const xmlChar *) "urn:ietf:params:xml:ns:yang:yin:1") == 0) {
			xmlChar *uri = xmlGetNoNsProp(current, (const xmlChar *) "uri");
			// Get a proper string, not some xml* beast.
			model_uri = strdup((const char *) uri);
			xmlFree(uri);
			break;
		}
	}
	xmlFreeDoc(doc);
	return model_uri;
}

/*
 * Take the model spec (yin) and extract the name of the model.
 * Pass the ownership to the caller.
 */
static char *extract_model_name(xmlDoc *doc) {
	assert(doc);
	xmlNode *node = xmlDocGetRootElement(doc);
	assert(node);
	xmlChar *name = xmlGetNoNsProp(node, (const xmlChar *) "name");
	char *result = strdup((const char *) name);
	xmlFree(name);
	return result;
}

char *extract_model_uri_string(const char *model) {
	return extract_model_uri(xmlReadMemory(model, strlen(model), "model.xml", NULL, 0));
}

char *extract_model_uri_file(const char *file) {
	return extract_model_uri(xmlParseFile(file));
}

char *extract_model_name_file(const char *file) {
	return extract_model_name(xmlParseFile(file));
}
