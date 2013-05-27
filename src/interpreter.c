#include "interpreter.h"
#include "register.h"
#include "../3rd_party/lxml2/lxml2.h"

#include <libnetconf.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <dirent.h>
#include <unistd.h>
#include <fcntl.h>

static int register_string(lua_State *lua, void (*function)(const char*), const char *name) {
	int param_count = lua_gettop(lua);
	if (param_count != 1)
		luaL_error(lua, "%s expects 1 parameter, %d given", name, param_count);
	const char *capability = lua_tostring(lua, 1);
	if (!capability)
		luaL_error(lua, "A non-string parameter passed to %s", name);
	function(capability);
	return 0; // No results from this function
}

static int register_capability_lua(lua_State *lua) {
	return register_string(lua, register_capability, "register_capability");
}

static int register_submodel_lua(lua_State *lua) {
	return register_string(lua, register_submodel, "register_submodel");
}

static int register_stat_generator_lua(lua_State *lua) {
	int param_count = lua_gettop(lua);
	if (param_count != 2)
		luaL_error(lua, "register_stat_generator expects 2 parameter, %d given", param_count);
	lua_callback callback = luaL_ref(lua, LUA_REGISTRYINDEX); // Copy the function to the registry
	register_stat_generator(lua_tostring(lua, 1), callback);
	return 0; // No results
}

static int register_datastore_provider_lua(lua_State *lua) {
	int param_count = lua_gettop(lua);
	if (param_count != 2)
		luaL_error(lua, "register_datastore_provider expects 2 parameter, %d given", param_count);
	lua_datastore datastore = luaL_ref(lua, LUA_REGISTRYINDEX); // Copy the object to the registry
	register_datastore_provider(lua_tostring(lua, 1), datastore);
	return 0; // No results
}

// Check the result is not -1, cause abort and error message if it is
static void check(int result, const char *operation) {
	if (result == -1) {
		fprintf(stderr, "Error during %s: %s", operation, strerror(errno));
		abort();
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

static void error(const char *format, ...) {
	// TODO: Unify logging
	va_list args;
	va_start(args, format);
	vfprintf(stderr, format, args);
	va_end(args);
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
	add_func(result, "register_capability", register_capability_lua);
	add_func(result, "register_submodel", register_submodel_lua);
	add_func(result, "register_stat_generator", register_stat_generator_lua);
	add_func(result, "register_datastore_provider", register_datastore_provider_lua);
	add_func(result, "run_command", run_command_lua);
	add_func(result, "xml_escape", xml_escape_lua);

	lxml2_init(result->state);

	return result;
}

bool interpreter_load_plugins(struct interpreter *interpreter, const char *path) {
	DIR *dir = opendir(path);
	if (!dir) {
		error("Can't read directory %s (%s)\n", path, strerror(errno));
		return false;
	}

	size_t path_len = strlen(path);
	struct dirent *ent;
	while ((ent = readdir(dir))) {
		// First, check if it ends with .lua
		const char *dot = rindex(ent->d_name, '.');
		// Either no file extention, or the extention is not lua nor luac
		if (!dot || (strcmp(dot, ".lua") != 0 && strcmp(dot, ".luac") != 0))
			continue;

		size_t complete_len = strlen(ent->d_name) + path_len + 2; // 1 for '\0', 1 for '/'
		char filename[complete_len];
		size_t print_len = snprintf(filename, complete_len, "%s/%s", path, ent->d_name);
		assert(print_len == complete_len - 1);
		if (luaL_dofile(interpreter->state, filename) != 0) {
			// The error is on the top of the string, at index -1
			error("Failure to load lua plugin %s: %s\n", ent->d_name, lua_tostring(interpreter->state, -1));
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

const char *interpreter_call_str(struct interpreter *interpreter, lua_callback callback) {
	lua_State *lua = interpreter->state;
	lua_checkstack(lua, LUA_MINSTACK); // Make sure it works even when called multiple times from C
	// Copy the function to the stack
	lua_rawgeti(lua, LUA_REGISTRYINDEX, callback);
	/*
	 * No parameters for the callback functions, none pushed. We want up to 2 results.
	 *
	 * In case an error is returned, there's just single value on stack, which is the
	 * error message. However, the follow-up error handler looks at the last value on
	 * stack for error, which works both for the case function returns error itself
	 * and for lua interpreter errors. So no need to check return value of lua_pcall.
	 */
	lua_pcall(lua, 0, 2, 0);
	if (!lua_isnil(lua, -1)) { // There's an error
		flag_error(interpreter, true, -1);
		return NULL;
	} else {
		flag_error(interpreter, false, 0);
		return lua_tostring(lua, -2); // The result.
	}
}

const char *interpreter_get_config(struct interpreter *interpreter, lua_datastore datastore) {
	lua_State *lua = interpreter->state;
	lua_checkstack(lua, LUA_MINSTACK); // Make sure it works even when called multiple times from C
	// Pick up the data store
	lua_rawgeti(lua, LUA_REGISTRYINDEX, datastore);
	lua_getfield(lua, -1, "get_config"); // The function
	lua_pushvalue(lua, -2); // The first parameter of a method is the object it is called on
	// Single parameter - the object.
	// Two results - the string and error. In case of success, the second is nil.
	if (lua_pcall(lua, 1, 2, 0) != 0) {
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
	lua_pcall(lua, 4, 1, 0);
	if (lua_isnil(lua, -1))
		flag_error(interpreter, false, 0);
	else
		flag_error(interpreter, true, -1);
}

void flag_error(struct interpreter *interpreter, bool error, int err_index) {
	interpreter->last_error = error;
	if (error) {
		lua_pushvalue(interpreter->state, err_index);
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
	{ "in use", NC_ERR_IN_USE },
	{ "invalid value", NC_ERR_INVALID_VALUE },
	{ "too big", NC_ERR_TOO_BIG },
	{ "missing attribute", NC_ERR_MISSING_ATTR },
	{ "bad attribute", NC_ERR_BAD_ATTR },
	{ "unknown attribute", NC_ERR_UNKNOWN_ATTR },
	{ "missing element", NC_ERR_MISSING_ELEM },
	{ "bad element", NC_ERR_BAD_ELEM },
	{ "unknown element", NC_ERR_UNKNOWN_ELEM },
	{ "unknown namespace", NC_ERR_UNKNOWN_NS },
	{ "access denied", NC_ERR_ACCESS_DENIED },
	{ "lock denied", NC_ERR_LOCK_DENIED },
	{ "resource denied", NC_ERR_RES_DENIED },
	{ "rollback failed", NC_ERR_ROLLBACK_FAILED },
	{ "data exists", NC_ERR_DATA_EXISTS },
	{ "data missing", NC_ERR_DATA_MISSING },
	{ "operation not supported", NC_ERR_OP_NOT_SUPPORTED },
	{ "operation failed", NC_ERR_OP_FAILED },
	{ "malformed message", NC_ERR_MALFORMED_MSG },
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
	{ "tag", NULL, NC_ERR_PARAM_TAG },
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
			const char *error = get_err_value(lua, eindex, "error", "empty");
			NC_ERR errtype_value = NC_ERR_EMPTY; // Fallback to no error
			for (const struct errtype_def *def = errtype_def; def->string; def ++)
				if (strcasecmp(def->string, error) == 0) {
					errtype_value = def->value;
					break;
				}
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
