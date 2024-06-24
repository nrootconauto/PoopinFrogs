FramePtrAdd("OLD_DIR",DirCur);
 Cd(__DIR__);;
#include "Compiler.HC";
#include "Save.HC";
"%s\n",FramePtr("OLD_DIR");
Cd(FramePtr("OLD_DIR"));
FramePtrDel("OLD_DIR");
