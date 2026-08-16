#include "md4a/md4a.h"

#include <assert.h>
#include <string.h>

static void renders_github_markdown(void) {
  const char *markdown = "# Hello\n\n- [x] native\n\n~~old~~\n";
  md4a_result result = md4a_render(markdown, strlen(markdown), NULL);

  assert(result.status == MD4A_STATUS_OK);
  assert(strstr(result.html, "<h1>Hello</h1>") != NULL);
  assert(strstr(result.html, "type=\"checkbox\"") != NULL);
  assert(strstr(result.html, "<del>old</del>") != NULL);
  md4a_result_free(&result);
}

static void disables_raw_html_by_default(void) {
  const char *markdown = "before <script>alert(1)</script> after";
  md4a_result result = md4a_render(markdown, strlen(markdown), NULL);

  assert(result.status == MD4A_STATUS_OK);
  assert(strstr(result.html, "<script>") == NULL);
  md4a_result_free(&result);
}

static void can_enable_raw_html(void) {
  const char *markdown = "<span>trusted</span>";
  md4a_render_options options = {1};
  md4a_result result = md4a_render(markdown, strlen(markdown), &options);

  assert(result.status == MD4A_STATUS_OK);
  assert(strstr(result.html, "<span>trusted</span>") != NULL);
  md4a_result_free(&result);
}

static void renders_empty_input(void) {
  md4a_result result = md4a_render(NULL, 0, NULL);

  assert(result.status == MD4A_STATUS_OK);
  assert(result.html != NULL);
  assert(result.html_size == 0);
  assert(strcmp(result.html, "") == 0);
  md4a_result_free(&result);
}

static void rejects_invalid_input(void) {
  md4a_result result = md4a_render(NULL, 1, NULL);
  assert(result.status == MD4A_STATUS_INVALID_ARGUMENT);
  assert(result.html == NULL);
}

int main(void) {
  renders_github_markdown();
  disables_raw_html_by_default();
  can_enable_raw_html();
  renders_empty_input();
  rejects_invalid_input();
  return 0;
}
