#include <glib.h>

#include "default_handler.h"

static void output_match(void) {
  g_assert_true(md4a_handler_output_matches(MD4A_DESKTOP_ID));
  g_assert_true(
      md4a_handler_output_matches("app.md4a.Md4a.desktop\n"));
  g_assert_true(
      md4a_handler_output_matches("  app.md4a.Md4a.desktop  \n"));
  g_assert_false(md4a_handler_output_matches(NULL));
  g_assert_false(md4a_handler_output_matches("org.example.Editor.desktop\n"));
  g_assert_false(md4a_handler_output_matches("app.md4a.Md4a.desktop.extra"));
}

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, NULL);
  g_test_add_func("/linux/default-handler/output-match", output_match);
  return g_test_run();
}
