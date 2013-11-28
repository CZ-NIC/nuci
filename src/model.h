/*
 * Copyright 2013, CZ.NIC
 *
 * This file is part of NUCI configuration server.
 *
 * NUCI is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 * NUCI is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with NUCI.  If not, see <http://www.gnu.org/licenses/>.
 */

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
