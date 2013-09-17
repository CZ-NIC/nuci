#ifndef NUCI_MODEL_H
#define NUCI_MODEL_H

/*
 * Bunch of utility functions to handling the models for netconf.
 */

// Get the full path of a model specified by the file name. Return value allocated and ownership passed onto the caller.
char *model_path(const char *model_file);

/*
 * Take the model spec (yin) specs and extract the namespace uri of the model.
 * Pass the result onto the caller for free.
 */
char *extract_model_uri_string(const char *model);
char *extract_model_uri_file(const char *file);
// Similar, but extract the name
char *extract_model_name_file(const char *file);

#endif
