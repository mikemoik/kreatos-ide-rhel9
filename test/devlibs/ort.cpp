// onnxruntime in its own translation unit: onnxruntime_c_api.h defines the
// macro NO_EXCEPTION, which breaks TAO's CORBA::exception_type enum
#include <onnxruntime_cxx_api.h>

#include <string>

std::string ort_version() {
  Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "kide");
  return Ort::GetVersionString();
}
