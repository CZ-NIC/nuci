#ifndef NUCI_DATASTORE_H
#define NUCI_DATASTORE_H

#include <libnetconf.h>
#include <libxml/tree.h>
#include <libxml/xpath.h>

#include <libnetconf/datastore_custom_public.h>

struct ncds_custom_funcs *nuci_ds_fill_callbacks(void);

#endif // NUCI_DATASTORE_H
