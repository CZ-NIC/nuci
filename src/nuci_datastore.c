#include "nuci_datastore.h"
#include "configuration.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/file.h>

#include <libnetconf.h>
#include <libnetconf/datastore_custom.h>

#include <libxml/tree.h>
#include <libxml/xpath.h>

struct nuci_ds_data {
	bool holding_lock;
	int lockfile;
};

void * nuci_ds_get_custom_data() {
	struct nuci_ds_data *data = calloc(1, sizeof(struct nuci_ds_data));

	if (data == NULL) {
		return NULL; //error will be catched somewhere else
	}

	return (void *)data;
}

/*
 * This is first functon in standard workflow with error detection and distribution.
 */
int nuci_ds_init(void *data) {
	if (data == NULL) {
		return 1;
	}

	struct nuci_ds_data *d = data;

	d->holding_lock = false;

	//is important to have acces to lockfile before we start
	d->lockfile = open(NUCI_LOCKFILE, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH);
	if (d->lockfile == -1) {
		return 1;
	}

	return 0;
}

static void nuci_ds_free(void *data) {
	free(data);
}

int nuci_ds_was_changed(void *data) {
	(void) data; //I'm "using" it.

	//always was changed
	return 1;
}

int nuci_ds_rollback(void *data) {
	(void) data; //I'm "using" it.

	//error every time
	return 1;
}

static bool test_and_set_lock(void *data) {
	struct nuci_ds_data *d = data;

	//data->lockfile consistency is garanted by nuci_ds_init()
	int lockinfo = flock(d->lockfile, LOCK_EX | LOCK_NB);
	if (lockinfo == -1) {
		return false;
	}

	d->holding_lock = true;

	return true;
}

static bool release_lock(void *data) {
	struct nuci_ds_data *d = data;

	//data->lockfile consistency is garanted by nuci_ds_init()
	int lockinfo = flock(d->lockfile, LOCK_UN);
	if (lockinfo == -1) {
		return false;
	}

	d->holding_lock = false;

	return true;
}

int nuci_ds_lock(void *data, NC_DATASTORE target, struct nc_err** error) {
	struct nuci_ds_data *d = data;
	*error = NULL;

	//only running target for now
	if (target != NC_DATASTORE_RUNNING) {
		*error = nc_err_new(NC_ERR_OP_NOT_SUPPORTED);
		return EXIT_FAILURE;
	}

	//I currently have lock. No double-locking.
	if (d->holding_lock) {
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

int nuci_ds_unlock(void *data, NC_DATASTORE target, struct nc_err** error) {
	struct nuci_ds_data *d = data;
	*error = NULL;

	//only running target for now
	if (target != NC_DATASTORE_RUNNING) {
		*error = nc_err_new(NC_ERR_OP_NOT_SUPPORTED);
		return EXIT_FAILURE;
	}

	//I have lock -> release it.
	if (d->holding_lock) { //if a have lock
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

	(void) d; //only fot this moment

	return strdup("<this-is-myconfiguration-content/>");
}

int nuci_ds_copyconfig(void *data, NC_DATASTORE target, NC_DATASTORE source, char* config, struct nc_err** error) {
	(void) data; //I'm "using" it.
	(void) target; //I'm "using" it.
	(void) source; //I'm "using" it.
	(void) config; //I'm "using" it.
	*error = NULL;

	//failed every time
	return EXIT_FAILURE;
}

int nuci_ds_deleteconfig(void *data, NC_DATASTORE target, struct nc_err** error) {
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
	//.get_lockinfo = nuci_ds_get_lockinfo, //In library is not used
	.lock = nuci_ds_lock,
	.unlock = nuci_ds_unlock,
	.getconfig = nuci_ds_getconfig,
	.copyconfig = nuci_ds_copyconfig,
	.deleteconfig = nuci_ds_deleteconfig,
	.editconfig = nuci_ds_editconfig
};
