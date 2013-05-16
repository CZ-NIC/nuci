#include "spec_build.h"

#include <stdlib.h>
#include <assert.h>
#include <unistd.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>

const size_t chunk_size = 4096;

static void check_error(int error, const char *text, const char *filename) {
	if (error == -1) {
		fprintf(stderr, "Error when %s '%s': %s\n", text, filename, strerror(errno));
		abort();
	}
}

static void copy_content(const char *in_filename, const char *out_filename, int out_file) {
	int in_file = open(in_filename, O_RDONLY);
	check_error(in_file, "opening file", in_filename);

	uint8_t data[chunk_size];
	ssize_t read_data;
	while ((read_data = read(in_file, data, chunk_size)) > 0) {
		ssize_t written = 0, result;
		while ((result = write(out_file, data + written, read_data - written)) > 0 && (written += result) < read_data);
		check_error(written, "writing to file", out_filename);
	}
	check_error(read_data, "reading from file", in_filename);
	check_error(close(in_file), "closing file", in_filename);
}

static void copy_content_base(const char *base_name, const char *suffix, const char *target_file, int file) {
	size_t len = strlen(base_name);
	char filename[len + 6]; // 1 for '.', 4 for 'head' or 'tail', 1 for '\0'
	assert(strlen(suffix) == 4);
	size_t filename_len = snprintf(filename, len + 6, "%s.%s", base_name, suffix);
	assert(filename_len == len + 5);

	copy_content(filename, target_file, file);
}

char *spec_build(const char *base_name, const char *base_path, const char *const chunks[]) {
	char result[] = "/tmp/spec.yin.XXXXXX";
	int file = mkstemp(result);
	assert(file != -1);
	copy_content_base(base_name, "head", result, file);
	for (const char *const *chunk = chunks; *chunk; chunk ++) {
		// TODO Mark where the thing comes from
		size_t len = strlen(base_path) + strlen(*chunk) + 2; // For the '/' and for '\0'
		char filename[len];
		size_t print_len = snprintf(filename, len, "%s/%s", base_path, *chunk);
		assert(print_len == len - 1);
		copy_content(filename, result, file);
	}
	copy_content_base(base_name, "tail", result, file);
	check_error(close(file), "closing file", result);
	return strdup(result);
}
