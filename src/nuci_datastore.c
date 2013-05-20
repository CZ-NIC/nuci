#include "nuci_datastore.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libnetconf.h>
#include <libnetconf/datastore_custom_public.h>

#include <libxml/tree.h>
#include <libxml/xpath.h>


int nuci_ds_init(void *data) {
	(void) data; //I'm "using" it.

	//return succes
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

int nuci_ds_lock(void *data, NC_DATASTORE target, struct nc_err** error) {
	(void) data; //I'm "using" it.
	*error = NULL;

	//only running target for now
	if (target != NC_DATASTORE_RUNNING) {
		*error = nc_err_new(NC_ERR_OP_NOT_SUPPORTED);
		return EXIT_FAILURE;
	}

	//succes every time
	return EXIT_SUCCESS;
}

int nuci_ds_unlock(void *data, NC_DATASTORE target, struct nc_err** error) {
	(void) data; //I'm "using" it.
	*error = NULL;

	//only running target for now
	if (target != NC_DATASTORE_RUNNING) {
		*error = nc_err_new(NC_ERR_OP_NOT_SUPPORTED);
		return EXIT_FAILURE;
	}

	//succes every time
	return EXIT_SUCCESS;
}

static char* nuci_ds_getconfig(void *data, NC_DATASTORE target, struct nc_err** error) {
	(void) data; //I'm "using" it.
	*error = NULL;

	//only running target for now
	if (target != NC_DATASTORE_RUNNING) {
		*error = nc_err_new(NC_ERR_OP_NOT_SUPPORTED);
		return NULL;
	}

	return strdup("<this-is-myconfiguration-content/>");
}

int nuci_ds_copyconfig(void *data, NC_DATASTORE target, NC_DATASTORE source, char* config, struct nc_err** error) {
	(void) data; //I'm "using" it.
	(void) target; //I'm "using" it.
	(void) source; //I'm "using" it.v
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
	(void) defop; //I'm "using" it.
	(void) errop; ////I'm "using" it.
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

/*
 * In library is not used
const struct ncds_lockinfo* nuci_ds_get_lockinfo(void *data, NC_DATASTORE target) {
	(void) data; //I'm "using" it.
	(void) target; //I'm "using" it.

	//only running target for now


	return 0;
}
*/
