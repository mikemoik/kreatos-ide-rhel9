#include "ort_model.h"

#include <onnxruntime_cxx_api.h>

namespace prodsim {

struct OrtModel::Impl {
  Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "prodsim"};
  Ort::SessionOptions options;
  Ort::Session session;
  std::string input_name;
  std::string output_name;

  explicit Impl(const std::string& path)
    : session(nullptr)
  {
    options.SetIntraOpNumThreads(1);
    session = Ort::Session(env, path.c_str(), options);
    Ort::AllocatorWithDefaultOptions alloc;
    input_name = session.GetInputNameAllocated(0, alloc).get();
    output_name = session.GetOutputNameAllocated(0, alloc).get();
  }
};

OrtModel::OrtModel(const std::string& path)
  : impl_(new Impl(path))
{
}

OrtModel::~OrtModel() = default;

std::vector<float> OrtModel::run(const std::vector<float>& input)
{
  Ort::MemoryInfo mem = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
  const int64_t shape[] = {int64_t(input.size())};
  Ort::Value tensor = Ort::Value::CreateTensor<float>(
    mem, const_cast<float*>(input.data()), input.size(), shape, 1);
  const char* in_names[] = {impl_->input_name.c_str()};
  const char* out_names[] = {impl_->output_name.c_str()};
  auto outputs = impl_->session.Run(Ort::RunOptions{nullptr}, in_names, &tensor, 1, out_names, 1);
  const float* data = outputs.front().GetTensorData<float>();
  return std::vector<float>(data, data + input.size());
}

std::string OrtModel::version()
{
  return Ort::GetVersionString();
}

} // namespace prodsim
