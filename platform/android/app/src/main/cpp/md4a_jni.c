#include <jni.h>
#include <stdint.h>
#include <stdlib.h>

#include "md4a/md4a.h"

JNIEXPORT jbyteArray JNICALL
Java_app_md4a_NativeRenderer_renderUtf8(JNIEnv *env, jobject receiver,
                                         jbyteArray markdown) {
  jbyte *input;
  jsize input_size;
  md4a_result result;
  jbyteArray output;
  (void)receiver;

  if (markdown == NULL) {
    return NULL;
  }

  input_size = (*env)->GetArrayLength(env, markdown);
  input = (*env)->GetByteArrayElements(env, markdown, NULL);
  if (input == NULL) {
    return NULL;
  }
  result = md4a_render((const char *)input, (size_t)input_size, NULL);
  (*env)->ReleaseByteArrayElements(env, markdown, input, JNI_ABORT);

  if (result.status != MD4A_STATUS_OK) {
    jclass exception_class = (*env)->FindClass(env, "java/lang/IllegalStateException");
    const char *message = result.error == NULL ? "Markdown render failed" : result.error;
    if (exception_class != NULL) {
      (*env)->ThrowNew(env, exception_class, message);
    }
    md4a_result_free(&result);
    return NULL;
  }

  if (result.html_size > INT32_MAX) {
    jclass exception_class = (*env)->FindClass(env, "java/lang/IllegalStateException");
    if (exception_class != NULL) {
      (*env)->ThrowNew(env, exception_class, "Rendered document is too large");
    }
    md4a_result_free(&result);
    return NULL;
  }

  output = (*env)->NewByteArray(env, (jsize)result.html_size);
  if (output != NULL && result.html_size != 0) {
    (*env)->SetByteArrayRegion(env, output, 0, (jsize)result.html_size,
                              (const jbyte *)result.html);
  }
  md4a_result_free(&result);
  return output;
}
