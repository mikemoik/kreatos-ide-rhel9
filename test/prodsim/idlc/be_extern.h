// prodsim-idlc backend entry points, called by the copied TAO driver
#ifndef PRODSIM_IDLC_BE_EXTERN_H
#define PRODSIM_IDLC_BE_EXTERN_H

#include "be_global.h"

#include <ace/config-all.h> // ACE_TCHAR; prod hit "not found" here (fix #2)

extern BE_GlobalData* be_global;

extern int BE_init(int&, ACE_TCHAR*[]);
extern void BE_post_init(char*[], long);
extern void BE_version();
extern void BE_produce();
extern void BE_abort();
extern void BE_cleanup();

#endif
