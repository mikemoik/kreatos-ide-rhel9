// prodsim-idlc backend: the minimal BE_GlobalData the copied TAO driver
// (drv_args.cpp, idlc_main.cpp) needs. Found before TAO's own be_global.h
// because this directory comes first on the include path.
#ifndef PRODSIM_IDLC_BE_GLOBAL_H
#define PRODSIM_IDLC_BE_GLOBAL_H

#include <string>

class BE_GlobalData {
public:
  // options the driver does not handle itself (-o <dir>)
  void parse_args(long& i, char** av);
  void destroy() {}

  std::string output_dir = ".";
};

#endif
