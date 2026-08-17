#ifndef MD4A_DEFAULT_HANDLER_H
#define MD4A_DEFAULT_HANDLER_H

#include <glib.h>

#define MD4A_DESKTOP_ID "app.md4a.Md4a.desktop"

G_BEGIN_DECLS

/* xdg-mime query output may include a trailing newline. */
gboolean md4a_handler_output_matches(const char *output);

G_END_DECLS

#endif
