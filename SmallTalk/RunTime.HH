class CFrogThing:CQue {
#define THINGF_TO_DELETE 1
#define THINGF_FRAME_TYPE 2
  I32 thing_flags,pad;
  I32 id,ref_cnt;
  U8 class_name[STR_LEN];
};
class CFrogFrame {
  CQue *pad,*pad;
  I32 thing_flags,pad;
  I32 id,ref_cnt;
}
class CFrogNum:CFrogThing {
  F64 num;
};
class CFrogUndefined:CFrogThing {
};
class CFrogClass:CFrogThing {
  U8 name[STR_LEN];
};
class CFrogChr:CFrogThing {
  U64 ch;
};
class CFrogBlock:CFrogThing {
  CFrogThing *self;
  U8 *frame;
  U8 (*fun_ptr)(CFrogThing *self,U8 *,...);//CSTFrame
};
#ifndef CI64Set 
extern class CI64Set;
#endif
class CFrogArray:CFrogThing {
  CI64Set *items;
  U8 *constructor dft "FrogArrayInit";
  U8 *destroy dft "FrogArrayDel";
};
class CFrogStr:CFrogArray {
};
class CFrogSymbol:CFrogThing {
  U8 name[STR_LEN];
  CFrogThing *value;
};
class CFrogError:CFrogThing {
};
class CFrogBlobFile:CFrogThing {
  CFrogStr *filename;
};
class CFrogBin:CFrogThing {
  U8 *data;
  U8 *destroy dft "FrogBinDel";
};