#include "md4a/md4a.h"

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "md4c-html.h"
#include "md4c.h"

typedef struct output_buffer {
  char *data;
  size_t size;
  size_t capacity;
  int failed;
} output_buffer;

static void append_output(const MD_CHAR *text, MD_SIZE size, void *userdata) {
  output_buffer *buffer = userdata;
  size_t required;
  size_t capacity;
  char *resized;

  if (buffer->failed || size == 0) {
    return;
  }
  if ((size_t)size > SIZE_MAX - buffer->size - 1) {
    buffer->failed = 1;
    return;
  }

  required = buffer->size + (size_t)size + 1;
  if (required > buffer->capacity) {
    capacity = buffer->capacity == 0 ? 256 : buffer->capacity;
    while (capacity < required) {
      if (capacity > SIZE_MAX / 2) {
        capacity = required;
        break;
      }
      capacity *= 2;
    }
    resized = realloc(buffer->data, capacity);
    if (resized == NULL) {
      buffer->failed = 1;
      return;
    }
    buffer->data = resized;
    buffer->capacity = capacity;
  }

  memcpy(buffer->data + buffer->size, text, size);
  buffer->size += size;
  buffer->data[buffer->size] = '\0';
}

static md4a_result error_result(md4a_status status, const char *error) {
  md4a_result result = {status, NULL, 0, error};
  return result;
}

md4a_result md4a_render(const char *markdown, size_t size,
                        const md4a_render_options *options) {
  output_buffer buffer = {0};
  unsigned parser_flags = MD_DIALECT_GITHUB;
  int render_status;
  md4a_result result;

  if (markdown == NULL && size != 0) {
    return error_result(MD4A_STATUS_INVALID_ARGUMENT,
                        "markdown is null but size is non-zero");
  }
  if (size > UINT_MAX) {
    return error_result(MD4A_STATUS_INPUT_TOO_LARGE,
                        "markdown exceeds md4c input limit");
  }
  if (options == NULL || !options->allow_raw_html) {
    parser_flags |= MD_FLAG_NOHTML;
  }

  render_status = md_html(markdown == NULL ? "" : markdown, (MD_SIZE)size,
                          append_output, &buffer, parser_flags,
                          MD_HTML_FLAG_SKIP_UTF8_BOM);
  if (buffer.failed) {
    free(buffer.data);
    return error_result(MD4A_STATUS_OUT_OF_MEMORY,
                        "could not allocate rendered HTML");
  }
  if (render_status != 0) {
    free(buffer.data);
    return error_result(MD4A_STATUS_RENDER_FAILED, "md4c render failed");
  }
  if (buffer.data == NULL) {
    buffer.data = malloc(1);
    if (buffer.data == NULL) {
      return error_result(MD4A_STATUS_OUT_OF_MEMORY,
                          "could not allocate empty result");
    }
    buffer.data[0] = '\0';
  }

  result.status = MD4A_STATUS_OK;
  result.html = buffer.data;
  result.html_size = buffer.size;
  result.error = NULL;
  return result;
}

void md4a_result_free(md4a_result *result) {
  if (result == NULL) {
    return;
  }
  free(result->html);
  result->status = MD4A_STATUS_OK;
  result->html = NULL;
  result->html_size = 0;
  result->error = NULL;
}

const char *md4a_version(void) { return "0.1.0"; }
