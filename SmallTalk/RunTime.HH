class CFrogThing:CQue {
#define THINGF_TO_DELETE 1
#define THINGF_FRAME_TYPE 2
#define THINGF_GC_LOCK 4
#define THINGF_CALL_LOCK 8
#define THINGF_GC_ROOT 0x10
#define THINGf_TO_DELETE 0
#define THINGf_GC_LOCK 2
#define THINGf_CALL_LOCK 3
#define THINGf_GC_ROOT 4
  I32 thing_flags,shadow_ref_cnt;
  I32 id,ref_cnt;
  CCPU *owner_cpu;
  I32 lock_cnt,universe_class_idx;
  U8 class_name[32];
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
  I64 class_id;
};
class CFrogChr:CFrogThing {
  U64 ch;
};
class CFrogBlock:CFrogThing {
  CFrogThing *self;
  CFrogThing *frame;
  U8 (*fun_ptr)(CFrogThing *self,U8 *,...);//CSTFrame
};
#ifndef CI64Set 
extern class CI64Set;
#endif
#ifndef CU8Set 
extern class CU8Set;
#endif
class CFrogArray:CFrogThing {
  CI64Set *items;
  U8 *constructor dft "FrogArrayInit";
  U8 *destroy dft "FrogArrayDel";
};

class CFrogStr:CFrogThing {
  CU8Set *items;
  U8 *constructor dft "FrogStrInit";
  U8 *destroy dft "FrogStrDel";
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

class CFrogTime:CFrogThing {
  CFrogNum *ts;
};