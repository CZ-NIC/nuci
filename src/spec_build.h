#ifndef SPEC_BUILD_H
#define SPEC_BUILD_H

// Utilities to build spec yin files from chunks

/*
 * Builds the spec file.
 *
 * It takes the base_name.head, then it includes all the chunks
 * and then it appends the base_name.tail.
 *
 * The chunks is NULL-terminated list of paths (relative to the
 * PLUGIN_DIR).
 *
 * Newly allocated path name is returned. Freeing the string and
 * removing the file is up to the caller.
 */
char *spec_build(const char *base_name, const char *base_path, const char *const chunks[]);

#endif
