#include "interpreter.h"
#include "register.h"
#include "model.h"
#include "logging.h"
#include "xmlwrap/xmlwrap.h"

#include <libnetconf.h>
#include <uci.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <dirent.h>
#include <unistd.h>
#include <fcntl.h>

/**
 * Our own error handler for pcall calls.
 */
static int lua_handle_runtime_error(lua_State *L) {
	const char *errmsg = lua_tostring(L, -1);

	//Get stacktrace; in Lua: x = require("stacktraceplus").stacktrace;
	lua_getfield(L, LUA_GLOBALSINDEX, "require");
	lua_pushstring(L, "stacktraceplus");
	lua_pcall(L, 1, 1, 0); //call require
	lua_getfield(L, -1, "stacktrace");
	lua_pcall(L, 0, 1, 0); //call STP.stacktrace

	nlog(NLOG_ERROR, "%s", lua_tostring(L, -1));

	lua_pushstring(L, errmsg); //return

	return 1;
}

/**
 * This function prepares error function for lua_pcall on the stack
 * and returns its index for easier way to call it.
 */
static int prepare_errfunc(lua_State *lua) {
	lua_getfield(lua, LUA_GLOBALSINDEX, "handle_runtime_error");
	return lua_gettop(lua);
}

static int register_datastore_provider_lua(lua_State *lua) {
	int param_count = lua_gettop(lua);
	if (param_count != 1)
		luaL_error(lua, "register_datastore_provider expects 1 parameter - the data store, %d given", param_count);
	int errfunc_index = prepare_errfunc(lua);
	lua_getfield(lua, 1, "model_file");
	const char *model_file = lua_tostring(lua, -1);
	// Fill in some values into the provider
	char *path = model_path(model_file);
	lua_pushstring(lua, path);
	lua_setfield(lua, 1, "model_path");
	char *ns = extract_model_uri_file(path);
	lua_pushstring(lua, ns);
	lua_setfield(lua, 1, "model_ns");
	free(path);
	free(ns);
	// We fill the model by running the lua XML parser
	lua_getglobal(lua, "xmlwrap"); // The package
	lua_getfield(lua, -1, "read_file"); // The function to call
	lua_getfield(lua, 1, "model_path"); // The file name
	lua_pcall(lua, 1, 1, errfunc_index);
	lua_setfield(lua, 1, "model"); // Copy the result into the datastore
	// Get the datastore to the top (there's more rumble on top of it by now)
	lua_pushvalue(lua, 1);
	lua_datastore datastore = luaL_ref(lua, LUA_REGISTRYINDEX); // Copy the object to the registry
	register_datastore_provider(model_file, datastore);
	return 0; // No results
}

// Check the result is not -1, cause abort and error message if it is
static void check(int result, const char *operation) {
	if (result == -1) {
		die("Error during %s: %s", operation, strerror(errno));
	}
}

// Helper function to feed data to a pipe
static bool feed_data(const char *data, size_t *position, size_t len, int pipe) {
	if (*position == len) {
		check(close(pipe), "closing stdin");
		return false;
	} else {
		// Write a bit there.
		ssize_t written = write(pipe, data + *position, len - *position);
		if (written == -1 && (errno == EACCES || errno == EWOULDBLOCK || errno == EINTR))
			return true; // These are not errors, retry
		check(written, "Writing to stdin");
		*position += written;
		return true;
	}
}

// Set fd nonblocking
static void unblock(int fd) {
	int flags = fcntl(fd, F_GETFL, 0);
	check(flags, "Getting fd flags");
	check(fcntl(fd, F_SETFL, flags | O_NONBLOCK), "Setting fd non-blocking");
}

// Update set and maximum for the fd
static void update_set(int *max_fd, fd_set *set, int fd) {
	if (fd > *max_fd)
		*max_fd = fd;
	FD_SET(fd, set);
}

static bool read_data(char **buffer, size_t *allocated, size_t *received, int fd) {
	if (*allocated == *received)
		*buffer = realloc(*buffer, *allocated *= 2);
	ssize_t result = read(fd, *buffer + *received, *allocated - *received);
	if (result == 0) {
		check(close(fd), "closing pipe");
		return false;
	}
	if (result == -1 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR))
		return true; // Retry. These are not really errors.
	check(result, "reading data");
	*received += result;
	return true;
}

/*
 * Run an external command.
 *
 * First argument is a string to put to the commands stdin. May be
 * nil or empty string.
 *
 * The rest of parameters are the command and its parameters. The first one is taken
 * as the command.
 *
 * Returns (ecode, stdout, stderr). First is number, the other too are strings.
 */
static int run_command_lua(lua_State *lua) {
	int param_count = lua_gettop(lua);
	if (param_count < 2)
		luaL_error(lua, "run_command expects at least 2 parameters, %d given", param_count);

	// Extract the stdin and command
	size_t input_len = 0;
	const char *input = "";
	if (!lua_isnil(lua, 1))
		input = lua_tolstring(lua, 1, &input_len);
	const char *command = lua_tostring(lua, 2);

	// Extract the argv. Param 2 belongs there too.
	char *argv[param_count]; // One less for stdin, one more for NULL
	for (int i = 0; i < param_count - 1; i ++) // Lua insists on ints, even if size_t is theoretically more correct
		argv[i] = strdup(lua_tostring(lua, i + 2));
	argv[param_count - 1] = NULL;

	// Prepare the pipes
	int in_pipes[2], out_pipes[2], err_pipes[2];
	check(pipe(in_pipes), "creating stdin pipe");
	check(pipe(out_pipes), "creating stdout pipe");
	check(pipe(err_pipes), "creating stderr pipe");

	// Start the sub process
	pid_t pid = fork();
	check(pid, "forking run_command");
	if (pid == 0) {
		/*
		 * The child. So, here we close the parental ends of the pipes, and
		 * install the other ends to stdin, stdout and stderr.
		 */
		check(close(in_pipes[1]), "closing parent stdin");
		check(close(out_pipes[0]), "closing parent stdout");
		check(close(err_pipes[0]), "closing parent stderr");
		check(dup2(in_pipes[0], 0), "duping stdin");
		check(dup2(out_pipes[1], 1), "duping stdout");
		check(dup2(err_pipes[1], 2), "duping stderr");
		// The originals are not needed
		check(close(in_pipes[0]), "closing original stdin");
		check(close(out_pipes[1]), "closing original stdout");
		check(close(err_pipes[1]), "closing original stderr");
		// Run the command
		check(execvp(command, argv), "exec");
		// We'll never get here. Either exec fails, then check kills us, or we exec.
	}
	// OK, we are in the parent now. Close the child ends of pipes.
	check(close(in_pipes[0]), "closing child stdin");
	check(close(out_pipes[1]), "closing child stdout");
	check(close(err_pipes[1]), "closing child stderr");
	// Set the rest non-blocking
	unblock(in_pipes[1]);
	unblock(out_pipes[0]);
	unblock(err_pipes[0]);
	// Try to write a bit of stdin, to initialize if we should ask for writability
	size_t input_position = 0;
	bool want_write = feed_data(input, &input_position, input_len, in_pipes[1]);
	bool output_unclosed = true, err_unclosed = true;
	const size_t base_size = 1024;
	char *output_data = malloc(base_size), *err_data = malloc(base_size);
	size_t output_allocated = base_size, err_allocated = base_size,
	       output_read = 0, err_read = 0;
	while (output_unclosed || err_unclosed || want_write) {
		fd_set read_set, write_set;
		FD_ZERO(&read_set);
		FD_ZERO(&write_set);
		int max = 0;
		if (want_write)
			update_set(&max, &write_set, in_pipes[1]);
		if (output_unclosed)
			update_set(&max, &read_set, out_pipes[0]);
		if (err_unclosed)
			update_set(&max, &read_set, err_pipes[0]);
		int sresult = select(max + 1, &read_set, &write_set, NULL, NULL);
		if (sresult == -1 && errno == EINTR)
			continue; // Retry
		check(sresult, "selecting operation");
		if (FD_ISSET(in_pipes[1], &write_set))
			want_write = feed_data(input, &input_position, input_len, in_pipes[1]);
		if (FD_ISSET(out_pipes[0], &read_set))
			output_unclosed = read_data(&output_data, &output_allocated, &output_read, out_pipes[0]);
		if (FD_ISSET(err_pipes[0], &read_set))
			err_unclosed = read_data(&err_data, &err_allocated, &err_read, err_pipes[0]);
	}
	// All three descriptors are closed now.
	// Get the exit status of the call.
	int status;
	check(waitpid(pid, &status, 0), "waiting for sub-process");
	// Output the data.
	lua_pushnumber(lua, status);
	lua_pushlstring(lua, output_data, output_read);
	lua_pushlstring(lua, err_data, err_read);
	free(output_data);
	free(err_data);
	return 3;
}

static void entity(char *buffer, size_t *pos, const char *name) {
	buffer[(*pos) ++] = '&';
	for (const char *c = name; *c; c ++)
		buffer[(*pos) ++] = *c;
	buffer[(*pos) ++] = ';';
}

static int xml_escape_lua(lua_State *lua) {
	int param_count = lua_gettop(lua);
	if (param_count != 1)
		luaL_error(lua, "xml_escape expects 1 parameter, %d given", param_count);
	const char *input = lua_tostring(lua, 1);
	if (!input)
		luaL_error(lua, "Not a string passed to xml_escape");
	size_t in_len = strlen(input);
	// The entity has &<code>;, <code> is max 4 chars.
	size_t out_len = 6 * in_len;
	char *output = malloc(out_len + 1);
	size_t out_pos = 0;
	for (const char *c = input; *c; c ++) {
		switch (*c) {
			case '"':
				entity(output, &out_pos, "quot");
				break;
			case '&':
				entity(output, &out_pos, "amp");
				break;
			case '\'':
				entity(output, &out_pos, "apos");
				break;
			case '<':
				entity(output, &out_pos, "lt");
				break;
			case '>':
				entity(output, &out_pos, "gt");
				break;
			default:
				output[out_pos ++] = *c;
		}
	}
	assert(out_pos <= out_len);
	output[out_pos] = '\0';
	lua_pushstring(lua, output);
	free(output);
	return 1;
}

static int uci_list_configs_lua(lua_State *lua) {
	struct uci_context *ctx = uci_alloc_context();
	if (!ctx)
		return luaL_error(lua, "Can't create UCI context");
	if (getenv("NUCI_TEST_CONFIG_DIR"))
		if (uci_set_confdir(ctx, getenv("NUCI_TEST_CONFIG_DIR")) != UCI_OK)
			return luaL_error(lua, "Can't set config dir to %s", getenv("NUCI_TEST_CONFIG_DIR"));
	char **configs = NULL;
	if ((uci_list_configs(ctx, &configs) != UCI_OK) || !configs) {
		uci_free_context(ctx);
		return luaL_error(lua, "Can't load configs");
	}
	int idx = 1;
	lua_newtable(lua);
	int tindex = lua_gettop(lua);
	for (char **config = configs; *config; config ++) {
		lua_pushnumber(lua, idx ++);
		lua_pushstring(lua, *config);
		lua_settable(lua, tindex);
		// Don't free here. Uci allocates the whole thing in one block of memory.
	}
	free(configs);
	uci_free_context(ctx);
	return 1;
}

static int file_executable_lua(lua_State *lua) {
	// Extract params
	int param_count = lua_gettop(lua);
	if (param_count != 1)
		luaL_error(lua, "stat expects 1 parameter, %d given", param_count);
	const char *path = lua_tostring(lua, -1);
	struct stat buffer;
	// Run stat
	int result = stat(path, &buffer);
	if (result == -1) {
		if (errno == ENOENT)
			return 0;
		else
			return luaL_error(lua, strerror(errno));
	}
	lua_pushboolean(lua, S_ISREG(buffer.st_mode) && (buffer.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)));
	return 1;
}

struct interpreter {
	lua_State *state;
	bool last_error; // Was there error?
};

static void add_func(struct interpreter *interpreter, const char *name, lua_CFunction function) {
	lua_pushcfunction(interpreter->state, function);
	lua_setglobal(interpreter->state, name);
}

struct interpreter *interpreter_create(void) {
	struct interpreter *result = malloc(sizeof *result);
	*result = (struct interpreter) {
		.state = luaL_newstate()
	};
	luaL_openlibs(result->state);
	add_func(result, "register_datastore_provider", register_datastore_provider_lua);
	add_func(result, "run_command", run_command_lua);
	add_func(result, "xml_escape", xml_escape_lua);
	add_func(result, "uci_list_configs", uci_list_configs_lua);
	add_func(result, "handle_runtime_error", lua_handle_runtime_error);
	add_func(result, "file_executable", file_executable_lua);

	xmlwrap_init(result->state);

	// Set the package.path so our own libraries are found. Prepend to the list.
	lua_getglobal(result->state, "package");
	lua_getfield(result->state, -1, "path");
	const char *old_path = lua_tostring(result->state, -1);
#ifdef LUA_COMPILE
	const char *path = PLUGIN_PATH "/lua_lib/?.luac";
#else
	const char *path = PLUGIN_PATH "/lua_lib/?.lua";
#endif
	size_t p_len = strlen(path) + 2 + strlen(old_path ? old_path : ""); // One for ;, one for \n
	char path_data[p_len];
	if (old_path) {
		size_t len = sprintf(path_data, "%s;%s", path, old_path);
		assert(len + 1 == p_len);
		path = path_data;
	}
	lua_pop(result->state, 1); // Remove the old value
	lua_pushstring(result->state, path); // Put the new one in
	lua_setfield(result->state, -2, "path"); // Replace the old value
	lua_pop(result->state, 1); // Remove the package table
	return result;
}

bool interpreter_load_plugins(struct interpreter *interpreter, const char *path) {
	DIR *dir = opendir(path);
	if (!dir) {
		nlog(NLOG_ERROR, "Can't read directory %s (%s)", path, strerror(errno));
		return false;
	}

	size_t path_len = strlen(path);
	struct dirent *ent;
	while ((ent = readdir(dir))) {
		// First, check if it ends with .lua
		const char *dot = rindex(ent->d_name, '.');
		// Either no file extention, or the extention is not lua nor luac
#ifdef LUA_COMPILE
		const char *ext = ".luac";
#else
		const char *ext = ".lua";
#endif
		if (!dot || strcmp(dot, ext) != 0)
			continue;

		size_t complete_len = strlen(ent->d_name) + path_len + 2; // 1 for '\0', 1 for '/'
		char filename[complete_len];
		size_t print_len = snprintf(filename, complete_len, "%s/%s", path, ent->d_name);
		assert(print_len == complete_len - 1);
		if (luaL_dofile(interpreter->state, filename) != 0) {
			// The error is on the top of the string, at index -1
			nlog(NLOG_ERROR, "Failure to load lua plugin %s: %s", ent->d_name, lua_tostring(interpreter->state, -1));
			return false;
		}
	}

	closedir(dir);
	return true;
}

void interpreter_destroy(struct interpreter *interpreter) {
	lua_close(interpreter->state);
	free(interpreter);
}

const char *interpreter_get(struct interpreter *interpreter, lua_datastore datastore, const char *method) {
	lua_State *lua = interpreter->state;
	lua_checkstack(lua, LUA_MINSTACK); // Make sure it works even when called multiple times from C
	//First of all: prepare error function on the stack
	int errfunc_index = prepare_errfunc(lua);
	// Pick up the data store
	lua_rawgeti(lua, LUA_REGISTRYINDEX, datastore);
	lua_getfield(lua, -1, method); // The function
	lua_pushvalue(lua, -2); // The first parameter of a method is the object it is called on
	// Single parameter - the object.
	// Two results - the string and error. In case of success, the second is nil.
	if (lua_pcall(lua, 1, 2, errfunc_index) != 0) {
		flag_error(interpreter, true, -1);
		return NULL;
	}
	// Convert the error only if there's one.
	if (!lua_isnil(lua, -1)) {
		flag_error(interpreter, true, -1);
		return NULL;
	}
	flag_error(interpreter, false, 0);
	if (lua_isnil(lua, -2))
		return NULL;
	else
		return lua_tostring(lua, -2);
}

void interpreter_set_config(struct interpreter *interpreter, lua_datastore datastore, const char *config, const char *default_op, const char *error_opt) {
	lua_State *lua = interpreter->state;
	lua_checkstack(lua, LUA_MINSTACK); // Make sure it works even when called multiple times from C
	int errfunc_index = prepare_errfunc(lua);
	// Pick up the data store
	lua_rawgeti(lua, LUA_REGISTRYINDEX, datastore);
	lua_getfield(lua, -1, "set_config"); // The function
	lua_pushvalue(lua, -2); // The datastore is the first parameter
	lua_pushstring(lua, config);
	lua_pushstring(lua, default_op);
	lua_pushstring(lua, error_opt);
	// Four parameters - the object, the config and the operations.
	// One result - the error. In case pcall fails, it sets the last parameter,
	// which is the same as what the lua function should do. No need to
	// distinguish.
	lua_pcall(lua, 4, 1, errfunc_index);
	bool error = !lua_isnil(lua, -1);
	flag_error(interpreter, error, - error);
}

void flag_error(struct interpreter *interpreter, bool error, int err_index) {
	interpreter->last_error = error;
	if (error) {
		lua_pushvalue(interpreter->state, err_index);
	}
}

char *interpreter_process_user_rpc(struct interpreter *interpreter, lua_datastore ds, char *procedure, char *data) {
	lua_State *lua = interpreter->state;
	lua_checkstack(lua, LUA_MINSTACK);

	int errfunc_index = prepare_errfunc(lua);
	lua_rawgeti(lua, LUA_REGISTRYINDEX, ds);
	lua_getfield(lua, -1, "user_rpc");
	lua_pushvalue(lua, -2);
	lua_pushstring(lua, procedure);
	lua_pushstring(lua, data);

	/**
	 * 1st return parameter is string with reply
	 * 2nd return parameter is error (nil - OK; string - errmsg
	 */
	int status = lua_pcall(lua, 3, 2, errfunc_index);

	if (status != 0) { //Runtime error and error message is on the top of stack
		flag_error(interpreter, true, -1); //only one result, i.e. on the top
		return NULL;
	} else if (status == 0 && !lua_isnil(lua, -1)) {
		flag_error(interpreter, true, -1);
		return NULL;
	} else { //all is OK an I have result
		return strdup(lua_tostring(lua, -2));
	}
}

static const char *get_err_value(lua_State *lua, int eindex, const char *name, const char *def) {
	lua_getfield(lua, eindex, name);
	const char *result = lua_tostring(lua, -1);
	if (!result)
		result = def;
	return result;
}

struct errtype_def {
	const char *string;
	NC_ERR value;
};

static const struct errtype_def errtype_def[] = {
	{ "empty", NC_ERR_EMPTY },
	{ "in-use", NC_ERR_IN_USE },
	{ "invalid-value", NC_ERR_INVALID_VALUE },
	{ "too-big", NC_ERR_TOO_BIG },
	{ "missing-attribute", NC_ERR_MISSING_ATTR },
	{ "bad-attribute", NC_ERR_BAD_ATTR },
	{ "unknown-attribute", NC_ERR_UNKNOWN_ATTR },
	{ "missing-element", NC_ERR_MISSING_ELEM },
	{ "bad-element", NC_ERR_BAD_ELEM },
	{ "unknown-element", NC_ERR_UNKNOWN_ELEM },
	{ "unknown-namespace", NC_ERR_UNKNOWN_NS },
	{ "access-denied", NC_ERR_ACCESS_DENIED },
	{ "lock-denied", NC_ERR_LOCK_DENIED },
	{ "resource-denied", NC_ERR_RES_DENIED },
	{ "rollback-failed", NC_ERR_ROLLBACK_FAILED },
	{ "data-exists", NC_ERR_DATA_EXISTS },
	{ "data-missing", NC_ERR_DATA_MISSING },
	{ "operation-not-supported", NC_ERR_OP_NOT_SUPPORTED },
	{ "operation-failed", NC_ERR_OP_FAILED },
	{ "malformed-message", NC_ERR_MALFORMED_MSG },
	{ NULL, NC_ERR_OP_FAILED }
};

struct errfield {
	const char *name;
	const char *def;
	NC_ERR_PARAM param;
};

static const struct errfield errfields[] = {
	{ "msg", "Unspecified error", NC_ERR_PARAM_MSG },
	{ "type", "application", NC_ERR_PARAM_TYPE },
	{ "severity", "error", NC_ERR_PARAM_SEVERITY },
	{ "app_tag", NULL, NC_ERR_PARAM_APPTAG },
	{ "path", NULL, NC_ERR_PARAM_PATH },
	{ "info_badattr", NULL, NC_ERR_PARAM_INFO_BADATTR },
	{ "info_badelem", NULL, NC_ERR_PARAM_INFO_BADELEM },
	{ "info_badns", NULL, NC_ERR_PARAM_INFO_BADNS },
	{ "info_sid", NULL, NC_ERR_PARAM_INFO_SID },
	{ .name = NULL }
};

struct nc_err *nc_err_create_from_lua(struct interpreter *interpreter) {
	if (interpreter->last_error) {
		lua_State *lua = interpreter->state;
		if (lua_isstring(lua, -1)) {
			// The easy interface for errors - just error string
			struct nc_err *error = nc_err_new(NC_ERR_OP_FAILED);
			nc_err_set(error, NC_ERR_PARAM_TYPE, "application");
			nc_err_set(error, NC_ERR_PARAM_SEVERITY, "error");
			nc_err_set(error, NC_ERR_PARAM_MSG, lua_tostring(interpreter->state, -1));
			return error;
		} else {
			lua_checkstack(lua, 20);
			if (!lua_istable(lua, -1)) {
				lua_pushstring(lua, "Error definition must be either string or table");
				return nc_err_create_from_lua(interpreter);
			}
			int eindex = lua_gettop(lua);
			const char *error = get_err_value(lua, eindex, "tag", "empty");
			NC_ERR errtype_value = NC_ERR_EMPTY; // Fallback to no error
			bool found = false;
			for (const struct errtype_def *def = errtype_def; def->string; def ++)
				if (strcasecmp(def->string, error) == 0) {
					errtype_value = def->value;
					found = true;
					break;
				}
			assert(found);
			struct nc_err *result = nc_err_new(errtype_value);
			for (const struct errfield *field = errfields; field->name; field ++) {
				const char *value = get_err_value(lua, eindex, field->name, field->def);
				if (value)
					nc_err_set(result, field->param, value);
			}
			// Drop the extra values added now
			lua_pop(lua, lua_gettop(lua) - eindex);
			return result;
		}
	} else {
		return NULL;
	}
}

void interpreter_commit(struct interpreter *interpreter, bool success) {
	lua_State *lua = interpreter->state;
	lua_getfield(lua, LUA_GLOBALSINDEX, "commit_execute");
	lua_pushboolean(lua, success);
	lua_call(lua, 1, 1);
	if (!lua_isnil(lua, -1)) {
		const char *error = lua_tostring(lua, -1);
		die("Error during commit/rollback: %s", error);
	}
}
