// onnxruntime behind a plain interface: onnxruntime_c_api.h defines the macro
// NO_EXCEPTION, which breaks TAO's CORBA::exception_type enum, so no
// translation unit includes both (see the kide README, C/C++ libraries).
#ifndef PRODSIM_ORT_MODEL_H
#define PRODSIM_ORT_MODEL_H

#include <memory>
#include <string>
#include <vector>

namespace prodsim {

class OrtModel {
public:
  explicit OrtModel(const std::string& path);
  ~OrtModel();
  // one output per input value (the model is element-wise)
  std::vector<float> run(const std::vector<float>& input);
  static std::string version();

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

} // namespace prodsim

#endif
