#include "model.h"

#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>

#define LUA_PLUGIN_PATH PLUGIN_PATH "/lua_plugins"

char *model_path(const char *model_file) {
	size_t len = strlen(LUA_PLUGIN_PATH) + strlen(model_file) + 2; // For the '/' and for '\0'
	char *filename = malloc(len);
	size_t print_len = snprintf(filename, len, "%s/%s", LUA_PLUGIN_PATH, model_file);
	assert(print_len == len - 1);
	return filename;
}
