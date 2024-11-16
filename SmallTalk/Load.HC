FramePtrAdd("OLD_DIR",DirCur);;
#exe {Cd(__DIR__);;};;
#ifndef ST_LOAD
#define ST_LOAD
#include "Studio.HC";
#include "Save.HC";
#endif
Cd(FramePtr("OLD_DIR"));
FramePtrDel("OLD_DIR");
