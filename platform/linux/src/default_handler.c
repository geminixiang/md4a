#include "default_handler.h"

#include <string.h>

gboolean md4a_handler_output_matches(const char *output) {
  char *normalized;
  gboolean matches;

  if (output == NULL) {
    return FALSE;
  }

  normalized = g_strdup(output);
  g_strstrip(normalized);
  matches = strcmp(normalized, MD4A_DESKTOP_ID) == 0;
  g_free(normalized);
  return matches;
}
