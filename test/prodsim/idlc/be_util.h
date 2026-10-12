// prodsim-idlc backend helpers, called by the copied TAO driver
#ifndef PRODSIM_IDLC_BE_UTIL_H
#define PRODSIM_IDLC_BE_UTIL_H

class AST_Generator;

namespace be_util {
void prep_be_arg(char* arg);
void arg_post_proc();
void usage();
AST_Generator* generator_init();
}

#endif
