#ifndef MD4A_H
#define MD4A_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum md4a_status {
  MD4A_STATUS_OK = 0,
  MD4A_STATUS_INVALID_ARGUMENT = 1,
  MD4A_STATUS_INPUT_TOO_LARGE = 2,
  MD4A_STATUS_OUT_OF_MEMORY = 3,
  MD4A_STATUS_RENDER_FAILED = 4
} md4a_status;

typedef struct md4a_render_options {
  int allow_raw_html;
} md4a_render_options;

typedef struct md4a_result {
  md4a_status status;
  char *html;
  size_t html_size;
  const char *error;
} md4a_result;

md4a_result md4a_render(const char *markdown, size_t size,
                        const md4a_render_options *options);
void md4a_result_free(md4a_result *result);
const char *md4a_version(void);

#ifdef __cplusplus
}
#endif

#endif
