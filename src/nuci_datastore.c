#include "nuci_datastore.h"
#include "configuration.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/file.h>

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
	struct interpreter *interpreter;
	lua_datastore datastore;
};

struct nuci_lock_info *lock_info_create(void) {
	struct nuci_lock_info *info = calloc(1, sizeof(struct nuci_lock_info));

	info->holding_lock = false;

	//is important to have acces to lockfile before we start
	info->lockfile = open(NUCI_LOCKFILE, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH);
	if (info->lockfile == -1) {
		fprintf(stderr, "Couldn't create lock file %s: %s", NUCI_LOCKFILE, strerror(errno));
		abort();
	}
	return info;
}

void lock_info_free(struct nuci_lock_info *info) {
	if (info->lockfile != -1) {
		close(info->lockfile);
	}

	free(info);
}

struct nuci_ds_data *nuci_ds_get_custom_data(struct nuci_lock_info *info, struct interpreter *interpreter, lua_datastore datastore) {
	struct nuci_ds_data *data = calloc(1, sizeof *data);

	data->lock_info = info;
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

static bool test_and_set_lock(void *data) {
	struct nuci_ds_data *d = data;

	//data->lockfile consistency is garanted by nuci_ds_init()
	int lockinfo = flock(d->lock_info->lockfile, LOCK_EX | LOCK_NB);
	if (lockinfo == -1) {
		return false;
	}

	d->lock_info->holding_lock = true;

	return true;
}

static bool release_lock(void *data) {
	struct nuci_ds_data *d = data;

	//data->lockfile consistency is garanted by nuci_ds_init()
	int lockinfo = flock(d->lock_info->lockfile, LOCK_UN);
	if (lockinfo == -1) {
		return false;
	}

	d->lock_info->holding_lock = false;

	return true;
}

static int nuci_ds_lock(void *data, NC_DATASTORE target, struct nc_err** error) {
	struct nuci_ds_data *d = data;
	*error = NULL;

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
	if (!test_and_set_lock(data)) {
		*error = nc_err_new(NC_ERR_LOCK_DENIED);
		return EXIT_FAILURE;
	}

	/*
	 * It's not necessary to write anything to lock-file.
	 * Every instance know if has or has not lock. And this specific value is set only if file lock is confirmed by OS
	 */

	return EXIT_SUCCESS;
}

static int nuci_ds_unlock(void *data, NC_DATASTORE target, struct nc_err** error) {
	struct nuci_ds_data *d = data;
	*error = NULL;

	//only running target for now
	if (target != NC_DATASTORE_RUNNING) {
		*error = nc_err_new(NC_ERR_OP_NOT_SUPPORTED);
		return EXIT_FAILURE;
	}

	//I have lock -> release it.
	if (d->lock_info->holding_lock) { //if a have lock
		if (!release_lock(data)) { //release it
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
	const char *errstr = NULL;
	const char *result = interpreter_get_config(d->interpreter, d->datastore, &errstr);

	if (errstr) {
		// Failed :-(
		*error = nc_err_new(NC_ERR_OP_FAILED);
		nc_err_set(*error, NC_ERR_PARAM_TYPE, "application");
		nc_err_set(*error, NC_ERR_PARAM_SEVERITY, "error");
		nc_err_set(*error, NC_ERR_PARAM_MSG, errstr);
		return NULL;
	}

	return strdup(result);
}

static int nuci_ds_copyconfig(void *data, NC_DATASTORE target, NC_DATASTORE source, char* config, struct nc_err** error) {
	(void) data; //I'm "using" it.
	(void) target; //I'm "using" it.
	(void) source; //I'm "using" it.
	(void) config; //I'm "using" it.
	*error = NULL;

	//failed every time
	return EXIT_FAILURE;
}

static int nuci_ds_deleteconfig(void *data, NC_DATASTORE target, struct nc_err** error) {
	(void) data; //I'm "using" it.
	(void) target; //I'm "using" it.
	*error = NULL;

	//failed every time
	return EXIT_FAILURE;
}


//Documentation for parameters defop and errop: http://libnetconf.googlecode.com/git/doc/doxygen/html/d3/d7a/netconf_8h.html#a5852fd110198481afb37cc8dcf0bf454
static int nuci_ds_editconfig(void *data, NC_DATASTORE target, const char * config, NC_EDIT_DEFOP_TYPE defop, NC_EDIT_ERROPT_TYPE errop, struct nc_err** error) {
	(void) data; //I'm "using" it.
	(void) errop; //I'm "using" it.
	(void) defop; //I'm "using" it.
	*error = NULL;

	//only running source for now
	if (target != NC_DATASTORE_RUNNING) {
		*error = nc_err_new(NC_ERR_OP_NOT_SUPPORTED);
		return EXIT_FAILURE;
	}

	fprintf(stderr, "Config content:\n%s\n", config);

	return EXIT_SUCCESS;
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
