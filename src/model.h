#ifndef NUCI_MODEL_H
#define NUCI_MODEL_H

/*
 * Bunch of utility functions to handling the models for netconf.
 */

// Get the full path of a model specified by the file name. Return value allocated and ownership passed onto the caller.
char *model_path(const char *model_file);

#endif
