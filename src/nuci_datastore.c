#include "nuci_datastore.h"
#include "configuration.h"
#include "logging.h"

#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <assert.h>

#include <libnetconf.h>
#include <libnetconf/datastore_custom.h>

#include <libxml/tree.h>
#include <libxml/xpath.h>

struct nuci_lock_info {
	bool holding_lock;
	int lockfile;
};

struct nuci_ds_data {
	struct nuci_lock_info *lock_info;
	bool lock_master;
	struct interpreter *interpreter;
	lua_datastore datastore;
};

struct nuci_lock_info *lock_info_create(void) {
	struct nuci_lock_info *info = calloc(1, sizeof(struct nuci_lock_info));

	info->holding_lock = false;

	//is important to have acces to lockfile before we start
	info->lockfile = open(NUCI_LOCKFILE, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH);
	if (info->lockfile == -1) {
		die("Couldn't create lock file %s: %s", NUCI_LOCKFILE, strerror(errno));
	}
	return info;
}

void lock_info_free(struct nuci_lock_info *info) {
	if (info->lockfile != -1) {
		close(info->lockfile);
	}

	free(info);
}

struct nuci_ds_data *nuci_ds_get_custom_data(struct nuci_lock_info *info, struct interpreter *interpreter, lua_datastore datastore, bool locking_enabled) {
	struct nuci_ds_data *data = calloc(1, sizeof *data);

	data->lock_info = info;
	data->lock_master = locking_enabled;
	data->interpreter = interpreter;
	data->datastore = datastore;

	return data;
}

/*
 * This is first functon in standard workflow with error detection and distribution.
 */
static int nuci_ds_init(void *data) {
	(void) data;
	// Empty for now.
	return 0;
}

static void nuci_ds_free(void *data) {
	free(data);
}

static int nuci_ds_was_changed(void *data) {
	(void) data; //I'm "using" it.

	//always was changed
	return 1;
}

static int nuci_ds_rollback(void *data) {
	(void) data; //I'm "using" it.

	//error every time
	return 1;
}

/**
 * Try to set lock
 *
 * Return TRUE - Lock managed to lock
 * Return FALSE - Lock is held by another instance
 */
static bool test_and_set_lock(struct nuci_lock_info *lock_info) {
	//data->lockfile consistency is garanted by nuci_ds_init()
	int lock = flock(lock_info->lockfile, LOCK_EX | LOCK_NB);
	if (lock == -1) {
		return false;
	}

	lock_info->holding_lock = true;

	return true;
}

/**
 * Release lock
 *
 * Return TRUE - lock was released
 * Return FALSE - lock was not released
 */
static bool release_lock(struct nuci_lock_info *lock_info) {
	//data->lockfile consistency is garanted by nuci_ds_init()
	int lock = flock(lock_info->lockfile, LOCK_UN);
	if (lock == -1) {
		return false;
	}

	lock_info->holding_lock = false;

	return true;
}

/**
 * Use this function for test datastore accessibility.
 *
 * If some procedure need change datastore it has to know datastore lock status.
 *
 * 1) I have lock -> proceed (return TRUE)
 * 2) I haven't lock, but datastore is not locked -> proceed (return TRUE)
 * 3) I haven't lock and datastore is locked -> stop any activity (return FALSE)
*/

static bool test_access_status(struct nuci_lock_info *lock_info) {
	if (lock_info->holding_lock) {
		return true;
	}

	if (test_and_set_lock(lock_info)) {
		release_lock(lock_info);
		return true;
	}

	return false;
}

static int nuci_ds_lock(void *data, NC_DATASTORE target, const char* session_id, struct nc_err** error) {
	(void) session_id;
	struct nuci_ds_data *d = data;
	*error = NULL;

	//I'm not the lock master
	if (d->lock_master == false) {
		return EXIT_SUCCESS;
	}

	//only running target for now
	if (target != NC_DATASTORE_RUNNING) {
		*error = nc_err_new(NC_ERR_OP_NOT_SUPPORTED);
		return EXIT_FAILURE;
	}

	//I currently have lock. No double-locking.
	if (d->lock_info->holding_lock) {
		*error = nc_err_new(NC_ERR_LOCK_DENIED);
		return EXIT_FAILURE;
	}

	//I haven't lock

	//data->lockfile consistency is garanted by nuci_ds_init()
	if (!test_and_set_lock(d->lock_info)) {
		*error = nc_err_new(NC_ERR_LOCK_DENIED);
		return EXIT_FAILURE;
	}

	/*
	 * It's not necessary to write anything to lock-file.
	 * Every instance know if has or has not lock. And this specific value is set only if file lock is confirmed by OS
	 */

	return EXIT_SUCCESS;
}

static int nuci_ds_unlock(void *data, NC_DATASTORE target, const char* session_id, struct nc_err** error) {
	(void) session_id;
	struct nuci_ds_data *d = data;
	*error = NULL;

	//I'm not the lock master
	if (d->lock_master == false) {
		return EXIT_SUCCESS;
	}

	//only running target for now
	if (target != NC_DATASTORE_RUNNING) {
		*error = nc_err_new(NC_ERR_OP_NOT_SUPPORTED);
		return EXIT_FAILURE;
	}

	//I have lock -> release it.
	if (d->lock_info->holding_lock) { //if a have lock
		if (!release_lock(d->lock_info)) { //release it
			*error = nc_err_new(NC_ERR_OP_FAILED);
			return EXIT_FAILURE;
		}

		return EXIT_SUCCESS;
	}

	//I haven't lock
	//It doesn't matter if datastore is locket or unlocked
	*error = nc_err_new(NC_ERR_LOCK_DENIED);

	return EXIT_FAILURE;
}

static char* nuci_ds_getconfig(void *data, NC_DATASTORE target, struct nc_err** error) {
	struct nuci_ds_data *d = data;
	*error = NULL;

	//only running target for now
	if (target != NC_DATASTORE_RUNNING) {
		*error = nc_err_new(NC_ERR_OP_NOT_SUPPORTED);
		return NULL;
	}

	// Call out to lua
	const char *result = interpreter_get(d->interpreter, d->datastore, "get_config");

	*error = nc_err_create_from_lua(d->interpreter, *error);
	if (result)
		return strdup(result);
	else
		return NULL;
}

static int nuci_ds_copyconfig(void *data, NC_DATASTORE target, NC_DATASTORE source, char* config, struct nc_err** error) {
	(void) data; //I'm "using" it.
	(void) target; //I'm "using" it.
	(void) source; //I'm "using" it.
	(void) config; //I'm "using" it.

	*error = nc_err_new(NC_ERR_OP_NOT_SUPPORTED);
	return EXIT_FAILURE;
}

static int nuci_ds_deleteconfig(void *data, NC_DATASTORE target, struct nc_err** error) {
	(void) data; //I'm "using" it.
	(void) target; //I'm "using" it.

	*error = nc_err_new(NC_ERR_OP_NOT_SUPPORTED);
	return EXIT_FAILURE;
}

//Documentation for parameters defop and errop: http://libnetconf.googlecode.com/git/doc/doxygen/html/d3/d7a/netconf_8h.html#a5852fd110198481afb37cc8dcf0bf454
static int nuci_ds_editconfig(void *data, const nc_rpc* rpc, NC_DATASTORE target, const char *config, NC_EDIT_DEFOP_TYPE defop, NC_EDIT_ERROPT_TYPE errop, struct nc_err** error) {
	(void) rpc;
	struct nuci_ds_data *d = data;

	//only running source for now
	if (target != NC_DATASTORE_RUNNING) {
		*error = nc_err_new(NC_ERR_OP_NOT_SUPPORTED);
		return EXIT_FAILURE;
	}

	if (!test_access_status(d->lock_info)) {
		*error = nc_err_new(NC_ERR_IN_USE);
		return EXIT_FAILURE;
	}

	const char *op = NULL, *err = NULL;
	switch (defop) {
		case NC_EDIT_DEFOP_NOTSET:
			op = "notset";
			break;
		case NC_EDIT_DEFOP_MERGE:
			op = "merge";
			break;
		case NC_EDIT_DEFOP_REPLACE:
			op = "replace";
			break;
		case NC_EDIT_DEFOP_NONE:
			op = "none";
			break;
		default:
			assert(0);
	}

	switch (errop) {
		case NC_EDIT_ERROPT_NOTSET:
			err = "notset";
			break;
		case NC_EDIT_ERROPT_STOP:
			err = "stop";
			break;
		case NC_EDIT_ERROPT_CONT:
			err = "cont";
			break;
		case NC_EDIT_ERROPT_ROLLBACK:
			err = "rollback";
			break;
		default:
			assert(0);
	}

	interpreter_set_config(d->interpreter, d->datastore, config, op, err);

	return (*error = nc_err_create_from_lua(d->interpreter, *error)) ? EXIT_FAILURE : EXIT_SUCCESS;
}

const struct ncds_custom_funcs *ds_funcs = &(struct ncds_custom_funcs) {
	.init = nuci_ds_init,
	.free = nuci_ds_free,
	.was_changed = nuci_ds_was_changed,
	.rollback = nuci_ds_rollback,
	.lock = nuci_ds_lock,
	.unlock = nuci_ds_unlock,
	.getconfig = nuci_ds_getconfig,
	.copyconfig = nuci_ds_copyconfig,
	.deleteconfig = nuci_ds_deleteconfig,
	.editconfig = nuci_ds_editconfig
};
