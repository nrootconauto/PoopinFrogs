#exe {Cd(__DIR__);};;
#include "Parser.HC";
#include "RunTime.HH";
#include "Set.HC";
//MAlloc'ed variables are aligned  to 8 0b1000,so we set bit 0 for "Small Var"
#define FROG_SMALL_NUM 0b1
#define FROG_SMALL_NIL 0b11
#define FROG_SMALL_CHR 0b101
//Error value is stored in a special place,Use FrogExceptValue
#define FROG_SMALL_ERROR 0b111
//
// $BK,1$IMPORTANT$BK,0$ This is how class members are rperesented
//
//The upper 32bits are an offset from self
//
#define FROG_SMALL_MEMBER_PTR 0b111
//

#define FROG_FP_ERROR "?STError"

extern CFrogThing *FrogStrNew(U8 *s);

I64 class CFrogSmallMemberPtr {
  I32 type;
  I32 offset;
};
I64 class CFrogSmallFixedPoint {
  I16 type; //Bit 0 must be set
  I16 fraction;
  I32 integer;
};
I64 class CFrogSmallChr {
  I16 type; //Bit 0 must be set
  I16 pad;
  U32 ch;
};
CTask *frog_mem_task=Fs;
CQue allocs_head;
QueInit(&allocs_head);

class CConstructorPair {
  U8 *dft;
  U8 *constructor;
  U8 *destroy;
};


extern U0 ThingDel(CFrogThing *thing,Bool recurse=TRUE);
extern U32 AsChar(CFrogThing *t);
extern Bool ThingHasClass(CFrogThing *thing,U8 *name,I64 small_type=0);
extern CFrogThing *ConstructThing(U8 *name,...);
CFrogThing *FrogIncRefCnt(CFrogThing *t) {
  if(!(t&1)) t->ref_cnt++;
  return t;
}


#include "Universe";
U0 AddMethod(U8 *cls,U8 *name,U8 *fptr) {
//See GenerateMethodCall
  U8 *canon=MStrPrint("METHOD_%s.%s",cls,name);
//Replace(possibly dummy) method.
  if(FramePtr(canon))
    FramePtrSet(canon,fptr);
  else
    FramePtrAdd(canon,fptr);
  UniverseAddMethod(name,cls,fptr);
  Free(canon);
}
U0 AddClassMethod(U8 *cls,U8 *name,U8 *fptr) {
  UniverseAddClassMethod(name,cls,fptr);
}




#ifdef TARGET_X86
#ifdef __AIWNIOS__
#define USE_AIWNIOS_ASM 1
#endif
#endif

#ifdef USE_AIWNIOS_ASM
asm {
_AS_F64::
  MOV RAX,8[RSP]
  CMP AX,FROG_SMALL_NUM
  JE @@is_num
  CMP AX,FROG_SMALL_CHR
  JE @@is_chr
//Not a number type?
  XOR	EAX,EAX
  XORPD	XMM0,XMM0
  RET1 8
@@is_num:
//4th byte of first argument
  CVTSS2SD XMM0,U32 12[RSP]
  MOVQ RAX,XMM0
  RET1 8
@@is_chr:
  SHRRAX,32
  CVTSI2SD XMM0,RAX
  MOVQ RAX,XMM0
  RET1 8

_TO_FROG_NUM::
  CVTSD2SS XMM0,8[RSP]
  PUSH FROG_SMALL_NUM
  MOVSS U32 4[RSP],XMM0
  POP RAX
 MOVQ XMM0,RAX
  RET1 8
};
_extern _AS_F64 F64 AsF64(CFrogThing *t);
_extern _TO_FROG_NUM CFrogNum *FrogNumNew(F64);
#else
F64 AsF64(CFrogThing *t) {
  I64 i=t;
  switch (i&0xFFFF) {
  case FROG_SMALL_NUM:
    return i>>16/ToF64(I16_MAX);
  case FROG_SMALL_CHR:
    return i>>32;
  }
  return 0;
}
CFrogThing *FrogNumNew(F64 n) {
  n*=I16_MAX;
  I64 ipart=ToI64(n);
  n-=ipart;
  if (n>.5)
    ++ipart;
  else if(n<-.5)
    --ipart;
  return ipart<<16|FROG_SMALL_NUM;
}
#endif
I64 gc_lock=0,cpu_call_script_lock=0;
//
// Sometimes a cpu will need to stop doing stuff,because a other core may want the lock of a child object wanted by multiple cores
// A(Core0)->B(Core1 )->A(Core1 also wants it)
//
I64 cpu_halts=1<<mp_cnt-1,cpu_halts_lock=0;
//A core is "halted" when no one is running smalltalk code
I64 cpu_active_cnts[mp_cnt];
MemSetI64(cpu_active_cnts,0,mp_cnt);
CFrogThing *FrogThingLock(CFrogThing *f) {
  return f;
  if(f&1) return f;
  I64 other;
  if(Bt(&f->owner_cpu,Gs->num))
   goto nxt;
again:
  while(LBts(&f->thing_flags,THINGf_CALL_LOCK)) {
    while(LBts(&cpu_halts_lock,0))
      ;
    LBts(&cpu_halts,Gs->num);
    other=mp_cnt;
    while(--other>=0) {
      if(other!=Gs->num)
        if(Bt(&f->owner_cpu,other)) {
	  if(!Bt(&cpu_halts,other)) {
	    LBtr(&cpu_halts_lock,0);
	    goto again;
	  }
        }
    }
    LBtr(&cpu_halts_lock,0);
    break;
  }
  LBtr(&cpu_halts,Gs->num);
nxt:;
  cpu_active_cnts[Gs->num]++;
  f->lock_cnt++;
  LBts(&f->owner_cpu,Gs->num);
  return f;
}
U0 FrogThingUnlock(CFrogThing *f) {
  if(f&1) return;
  if(--cpu_active_cnts[Gs->num]==0)
    LBts(&cpu_halts,Gs->num);
  if(--f->lock_cnt==0) {
    LBtr(&f->thing_flags,THINGf_CALL_LOCK);
    f->owner_cpu=0;
  }
}
class CLocalsGeneric:CFrogFrame {
  U64 type,raw_mask;//raw_mask means bit is set if is a raw(F64) type in body[x]
  CLocalsGeneric *next;
  CLocalsGeneric *parent;
  U8 *return_flag;
  I32 item_cnt,ret_flag;
  CFrogThing *body[0];
};

U0 STFrameDel() {
  CLocalsGeneric *s=Fs->user_data;
  CHashGeneric *gen;
  Fs->user_data=s->next;
}

Bool IsSmalltalkMember2(CHashClass *cls) {
  CHashClass *fc=HashFind("CFrogThing",frog_mem_task->hash_table,HTT_CLASS);
  if(cls->type&HTT_FUN)
    return FALSE;
//Account for pointers to cls
  if(cls->ptr_stars_cnt)
    --cls;
  while(cls) {
    if(cls==fc){
      return TRUE;
    }
    cls=cls->base_class;
  }
  return FALSE;
}



U8 *FrogThingClassName(CFrogThing *thing) {
//Check for special "small" type
  U8 *name;
  CHashClass *cls;
  if(thing&1) {
    if(thing&0xffff==FROG_SMALL_NUM)
      name="CFrogNum";
    else if(thing&0xffff==FROG_SMALL_NIL)
      name="CFrogUndefined";
    else if(thing&0xffff==FROG_SMALL_CHR)
      name="CFrogChr";
    else
      name="CFrogUndefined";
  } else  {
    if(thing->thing_flags&THINGF_FRAME_TYPE) {
//Is a generic frame
      return "CFrogThing";
    }
    name=thing->class_name;
  }
  return name;
}
Bool ThingHasClass(CFrogThing *thing,U8 *name,I64 small_type=0) {
//Quick check for small Types
  if(small_type&&thing&1) {
    return thing&0xffff==small_type;
  }
  if(!(thing&1)) {
    if(thing->thing_flags&THINGF_FRAME_TYPE) {
      if(!StrCmp(name,"CFrogFrame"))
        return TRUE;
      return FALSE;
    }
//Skip hash table call
    if(!StrCmp(name,thing->class_name))
      return TRUE;
  }

  CHashClass *cls=HashFind(FrogThingClassName(thing),frog_mem_task->hash_table,HTT_CLASS);
  while(cls) {
    if(!StrCmp(cls->str,name))
      return TRUE;
    cls=cls->base_class;
  }
  return FALSE;
}
Bool ThingHasClass2(CFrogThing *thing,I64 universe,I64 small_type=0) {
//Quick check for small Types
  if(small_type&&thing&1) {
    return thing&0xffff==small_type;
  }
  if(thing&1) {
    return ThingHasClass(thing,I64SetGetAt(universe_values,universe));
  }
  return UniverseIsSubClassOf(thing->universe_class_idx,universe);
}

Bool ThingIsError(CFrogThing *t) {
  return t&0xffFF==FROG_SMALL_ERROR;
}
I64 GetClassMeta(U8 *class_name,U8 *member,U8 *meta_name) {
  CHashClass *cls=HashFind(class_name,frog_mem_task->hash_table,HTT_CLASS);
  CMemberLst *mlst;
  CMemberLstMeta *meta;
  if(!cls) return NULL;
  if(mlst=MemberFind(member,cls)) {
     if(meta=MemberMetaFind(meta_name,mlst))
	return meta->user_data;
  }
  return NULL;
}
I64 GetClassMemberValI64(CFrogThing *t,U8 *member) {
  if(t&1) return 0; //Special "small type"
  CHashClass *cls=HashFind(t->class_name,frog_mem_task->hash_table,HTT_CLASS);
  CMemberLst *mlst;
  CMemberLstMeta *meta;
  if(!cls) return NULL;
  if(mlst=MemberFind(member,cls)) {
     switch(mlst->member_class->raw_type) {
       case RT_U8:
         return *(t(U8*)+mlst->offset);
       case RT_U16:
         return (t(U8*)+mlst->offset)(U16*)[0];
       case RT_U32:
         return (t(U8*)+mlst->offset)(U32*)[0];
       case RT_U64:
         return (t(U8*)+mlst->offset)(U64*)[0];
       case RT_I8:
         return *(t(I8*)+mlst->offset);
       case RT_I16:
         return (t(U8*)+mlst->offset)(I16*)[0];
       case RT_I32:
         return (t(U8*)+mlst->offset)(I32*)[0];
       case RT_I64:
         return (t(U8*)+mlst->offset)(I64*)[0];
       case RT_F64:
         return (t(U8*)+mlst->offset)(F64*)[0];
     }
  }
  return NULL;
}

U0 SetClassMemberValI64(CFrogThing *t,U8 *member,I64 val) {
  if(t&1) return 0; //Special "small type"
  CHashClass *cls=HashFind(FrogThingClassName(t),frog_mem_task->hash_table,HTT_CLASS);
  CMemberLst *mlst;
  CMemberLstMeta *meta;
  if(!cls) NULL;
  if(mlst=MemberFind(member,cls)) {
     switch(mlst->member_class->raw_type) {
       case RT_U8:
         *(t(U8*)+mlst->offset)=val;
	 break;
       case RT_U16:
         (t(U8*)+mlst->offset)(U16*)[0]=val;
	 break;
       case RT_U32:
         (t(U8*)+mlst->offset)(U32*)[0]=val;
	 break;
       case RT_U64:
         (t(U8*)+mlst->offset)(U64*)[0]=val;
	 break;
       case RT_I8:
         *(t(I8*)+mlst->offset)=val;
	 break;
       case RT_I16:
         (t(U8*)+mlst->offset)(I16*)[0]=val;
	 break;
       case RT_I32:
         (t(U8*)+mlst->offset)(I32*)[0]=val;
	 break;
       case RT_I64:
         (t(U8*)+mlst->offset)(I64*)[0]=val;
	 break;
       case RT_F64:
         (t(U8*)+mlst->offset)(F64*)[0]=val;
	 break;
     }
  }
  return;
}

U0 SetClassMemberVal(CFrogThing *t,U8 *member,I64 val) {
  if(t&1) return; //Special "small type"
  CHashClass *cls=HashFind(FrogThingClassName(t),frog_mem_task->hash_table,HTT_CLASS);
  CMemberLst *mlst;
  CMemberLstMeta *meta;
  CFrogThing dummy;
  F64 v2;
  MemSet(&dummy,0,sizeof CFrogThing);
  if(!cls) NULL;
  if(mlst=MemberFind(member,cls)) {
    if(mlst->member_class->ptr_stars_cnt==1) {
      StrCpy(dummy.class_name,mlst->member_class[-1].str);
      if(ThingHasClass(&dummy,"CFrogThing")) { 
        (t(U8*)+mlst->offset)(I64*)[0]=FrogIncRefCnt(val);
        return ;
      }
    }
    v2=AsF64(val);
    switch(mlst->member_class->raw_type) {
      case RT_U8:
        *(t(U8*)+mlst->offset)=v2;
        break;
      case RT_U16:
        (t(U8*)+mlst->offset)(U16*)[0]=v2;
        break;
      case RT_U32:
        (t(U8*)+mlst->offset)(U32*)[0]=v2;
        break;
      case RT_U64:
        (t(U8*)+mlst->offset)(U64*)[0]=v2;
        break;
      case RT_I8:
        *(t(I8*)+mlst->offset)=v2;
        break;
      case RT_I16:
        (t(U8*)+mlst->offset)(I16*)[0]=v2;
        break;
      case RT_I32:
        (t(U8*)+mlst->offset)(I32*)[0]=v2;
        break;
      case RT_I64:
        (t(U8*)+mlst->offset)(I64*)[0]=v2;
        break;
      case RT_F64:
        (t(U8*)+mlst->offset)(F64*)[0]=v2;
        break;
    }
  }
  return;
}

CFrogThing *GetClassMemberVal(CFrogThing *t,U8 *member) {
  if(t&1) return FROG_SMALL_NIL; //Special "small type"
  CHashClass *cls=HashFind(FrogThingClassName(t),frog_mem_task->hash_table,HTT_CLASS);
  CMemberLst *mlst;
  CMemberLstMeta *meta;
  CFrogThing dummy;
  F64 v;
  MemSet(&dummy,0,sizeof CFrogThing);
  if(mlst=MemberFind(member,cls)) {
     if(mlst->member_class->ptr_stars_cnt==1) {
       StrCpy(dummy.class_name,mlst->member_class[-1].str);
       if(ThingHasClass(&dummy,"CFrogThing")) { 
         return FrogIncRefCnt((t(U8*)+mlst->offset)(I64*)[0]);
       }
     }
     switch(mlst->member_class->raw_type) {
       case RT_U8:
         v=*(t(U8*)+mlst->offset);
	 break;
       case RT_U16:
         v=(t(U8*)+mlst->offset)(U16*)[0];
	 break;
       case RT_U32:
         v=(t(U8*)+mlst->offset)(U32*)[0];
	 break;
       case RT_U64:
         v=(t(U8*)+mlst->offset)(U64*)[0];
	 break;
       case RT_I8:
         v=*(t(I8*)+mlst->offset);
	 break;
       case RT_I16:
         v=(t(U8*)+mlst->offset)(I16*)[0];
	 break;
       case RT_I32:
         v=(t(U8*)+mlst->offset)(I32*)[0];
	 break;
       case RT_I64:
         v=(t(U8*)+mlst->offset)(I64*)[0];
	 break;
       case RT_F64:
         v=(t(U8*)+mlst->offset)(F64*)[0];
	 break;
     }
    return FrogNumNew(v);
  } 
  return FROG_SMALL_NIL;
}

U0 SetClassMemberValF64(CFrogThing *t,U8 *member,F64 val) {
  if(t&1) return 0; //Special "small type"
  CHashClass *cls=HashFind(t->class_name,frog_mem_task->hash_table,HTT_CLASS);
  CMemberLst *mlst;
  CMemberLstMeta *meta;
  if(!cls) NULL;
  if(mlst=MemberFind(member,cls)) {
     switch(mlst->member_class->raw_type) {
       case RT_U8:
         *(t(U8*)+mlst->offset)=val;
	 break;
       case RT_U16:
         (t(U8*)+mlst->offset)(U16*)[0]=val;
	 break;
       case RT_U32:
         (t(U8*)+mlst->offset)(U32*)[0]=val;
	 break;
       case RT_U64:
         (t(U8*)+mlst->offset)(U64*)[0]=val;
	 break;
       case RT_I8:
         *(t(I8*)+mlst->offset)=val;
	 break;
       case RT_I16:
         (t(U8*)+mlst->offset)(I16*)[0]=val;
	 break;
       case RT_I32:
         (t(U8*)+mlst->offset)(I32*)[0]=val;
	 break;
       case RT_I64:
         (t(U8*)+mlst->offset)(I64*)[0]=val;
	 break;
       case RT_F64:
         (t(U8*)+mlst->offset)(F64*)[0]=val;
	 break;
     }
  }
  return;
}


F64 GetClassMemberValF64(CFrogThing *t,U8 *member) {
  if(t&1) return 0; //Special "small type"
  CHashClass *cls=HashFind(t->class_name,frog_mem_task->hash_table,HTT_CLASS);
  CMemberLst *mlst;
  CMemberLstMeta *meta;
  if(mlst=MemberFind(member,cls)) {
     switch(mlst->member_class->raw_type) {
       case RT_U8:
         return *(t(U8*)+mlst->offset);
       case RT_U16:
         return (t(U8*)+mlst->offset)(U16*)[0];
       case RT_U32:
         return (t(U8*)+mlst->offset)(U32*)[0];
       case RT_U64:
         return (t(U8*)+mlst->offset)(U64*)[0];
       case RT_I8:
         return *(t(I8*)+mlst->offset);
       case RT_I16:
         return (t(U8*)+mlst->offset)(I16*)[0];
       case RT_I32:
         return (t(U8*)+mlst->offset)(I32*)[0];
       case RT_I64:
         return (t(U8*)+mlst->offset)(I64*)[0];
       case RT_F64:
         return (t(U8*)+mlst->offset)(F64*)[0];
     }
  }
  return NULL;
}
extern CFrogThing *CallScript(U8 *name,CFrogThing *self,...);



CFrogThing *_ConstructThing(U8 *class_name,I64 argc,I64 *argv) {
  CTask *mem_task=frog_mem_task;
  I64 idx;
  CHashClass *cls=HashFind(class_name,frog_mem_task->hash_table,HTT_CLASS),*ocls=cls;
  CMemberLst *mlst;
  U8 *constructor;
  if(!cls) return NULL;
  CFrogThing *t=CAlloc(cls->size,mem_task);
  t->universe_class_idx=UniverseAddClass(class_name);
  QueInit(t);
  StrCpy(t->class_name,class_name);
  CHashFun *fun;
  U0 (*init)(CFrogThing*);
  for(cls=ocls;cls;cls=cls->base_class)
    for(mlst=cls->member_lst_and_root;mlst;mlst=mlst->next) {
      idx=GetClassMeta(class_name,mlst->str,"dft");
      if(idx)
        (t(U8*)+mlst->offset)(I64*)[0]=idx;
      else if(IsSmalltalkMember2(mlst->member_class)&&mlst->dim.total_cnt==1) {
	(t(U8*)+mlst->offset)(I64*)[0]=FROG_SMALL_NIL;
      }
    }
  cls=ocls;
  for(idx=0;idx<argc;idx+=2) {
    mlst=MemberFind(argv[idx],cls);
    if(mlst) {
      switch(mlst->member_class->raw_type) {
        case RT_U8:
	  *(t(U8*)+mlst->offset)=argv[idx+1];
	  break;
        case RT_U16:
	  (t(U8*)+mlst->offset)(U16*)[0]=argv[idx+1];
	  break;
        case RT_U32:
	  (t(U8*)+mlst->offset)(U32*)[0]=argv[idx+1];
	  break;
        case RT_U64:
	  (t(U8*)+mlst->offset)(U64*)[0]=argv[idx+1];
	  break;
        case RT_I8:
	  *(t(I8*)+mlst->offset)=argv[idx+1];
	  break;
        case RT_I16:
	  (t(U8*)+mlst->offset)(I16*)[0]=argv[idx+1];
	  break;
        case RT_I32:
	  (t(U8*)+mlst->offset)(I32*)[0]=argv[idx+1];
	  break;
        case RT_I64:
	  (t(U8*)+mlst->offset)(I64*)[0]=argv[idx+1];
	  break;
        case RT_F64:
	  (t(U8*)+mlst->offset)(F64*)[0]=argv(F64*)[idx+1];
	  break;
      }
    }
  }
  if(constructor=GetClassMemberValI64(t,"constructor")) {
    fun=HashFind(constructor,frog_mem_task->hash_table,HTT_FUN);
    if(fun) {
      init=fun->exe_addr;
      (*init)(t);
    }
  }
fin:
  t->ref_cnt=1;
  t->id=UniverseAddClass(class_name);
  QueIns(t,allocs_head.next);
  return t;
}
U8 *Str2FunPtr(U8 *str)  {
  if(!str) return NULL;
  CHashFun *fun=HashFind(str,Fs->hash_table,HTT_FUN);
  if(!fun) return NULL;
  return fun->exe_addr;

}
CFrogThing *ConstructThing(U8 *name,...) {
  CConstructorPair *p;
  CFrogThing *ret;
  CHashFun *fun;
  U0 (*init)(CFrogThing*);

  if(!argc) {
    if(ret=UniverseConstructThingS(name)) {
      QueIns(ret,allocs_head.last);
      return ret;
    }
    ret=_ConstructThing(name,argc,argv);
    if(!ret) return FROG_SMALL_NIL;
    UniverseAddConstructorPair(name,
      ret,
      Str2FunPtr(GetClassMemberValI64(ret,"constructor")),
      Str2FunPtr(GetClassMemberValI64(ret,"destroy"))
    );
    QueRem(ret); //Remove from GC
    return ConstructThing(name);
  } else
    ret=_ConstructThing(name,argc,argv);
  if(!ret) ret=FROG_SMALL_NIL;
  return ret;
}

CFrogThing *FrogChrNew(U64 ch) {
  return (ch<<32)|FROG_SMALL_CHR;
}
U0 FrogArrayInit(CFrogArray *a) {
  a->items=I64SetNew(frog_mem_task);
} 
U0 FrogStrInit(CFrogStr *a) {
  a->items=U8SetNew(frog_mem_task);
} 
CFrogArray *FrogArrayNew() {
  CFrogArray *ret=ConstructThing("CFrogArray");
  return ret;
}

CFrogThing *FrogStrNew(U8 *s) {
  CFrogStr *str=ConstructThing("CFrogStr");
  CU8Set *items=str->items;
  for(;*s;s++) {
    U8SetAdd(items,*s);
  }
  return str;
}

CFrogThing *CallPtr(U8 *fun_ptr,U8 *must_have,CFrogThing *self,...) {
  if(self==FROG_SMALL_NIL) return FROG_SMALL_NIL;
  if(must_have) {
    if(!ThingHasClass(self,must_have)) {
     return FROG_SMALL_NIL;
    }
  }
  CFrogThing *ret=CallVaArgs(fun_ptr,argc,argv,self);
  if(!ret)
    ret=FROG_SMALL_NIL;
  return ret;
}
CFrogThing *CallPtr2(U8 *fun_ptr,I64 universe_class,CFrogThing *self,...) {
  if(self==FROG_SMALL_NIL) return FROG_SMALL_NIL;
  if(!ThingHasClass2(self,universe_class)) {
    return FROG_SMALL_NIL;
  }
  CFrogThing *ret=CallVaArgs(fun_ptr,argc,argv,self);
  if(!ret)
    ret=FROG_SMALL_NIL;
  return ret;
}


CFrogThing *CallScript(U8 *name,CFrogThing *self,...) {
  U8* fptr,id;
  CFrogThing *ret=NULL;
  if(ThingHasClass(self,"CFrogClass")) {
    fptr=UniverseGetClassMethodForClassByIdx(NameToUniverseNumber(self(CFrogClass*)->name),self->id);   
    if(fptr)  {
      ret=CallVaArgs(fptr,argc,argv,self);
    }
    goto fin;
  }
  if(!(self&1)) {
    fptr=UniverseGetMethodForClassByIdx(NameToUniverseNumber(name),self->id);   
    if(fptr) 
      ret=CallVaArgs(fptr,argc,argv,self);
    goto fin;
  } else {
    id=UniverseAddClass(FrogThingClassName(self));
    fptr=UniverseGetMethodForClassByIdx(NameToUniverseNumber(name),id);
    if(fptr) 
      ret=CallVaArgs(fptr,argc,argv,self);
    goto fin;
  }
fin:
  if(!ret)
    ret=FROG_SMALL_NIL;
  return ret;
}
CFrogThing *CallScriptUniverse(I64 who,CFrogThing *self,...) {
  U8* fptr;
  I64 id;
  CFrogThing *ret=NULL;
  if(ThingHasClass(self,"CFrogClass")) {
    id=NameToUniverseNumber(self(CFrogClass*)->name);
    fptr=UniverseGetClassMethodForClassByIdx(who,id);   
    if(fptr) {
      ret=CallVaArgs(fptr,argc,argv,self);
    }
    goto fin;
  }
  if(!(self&1)) {
    fptr=UniverseGetMethodForClassByIdx(who,self->id);   
    if(fptr) 
      ret=CallVaArgs(fptr,argc,argv,self);
    goto fin;
  } else {
    id=UniverseAddClass(FrogThingClassName(self));
    fptr=UniverseGetMethodForClassByIdx(who,id);
    if(fptr) 
      ret=CallVaArgs(fptr,argc,argv,self);
    goto fin;
  }
fin:
  if(!ret)
    ret=FROG_SMALL_NIL;
  return ret;
}

CFrogClass *FrogClassNew(I64 cls_idx) {
  CFrogClass *ret;
  ret=ConstructThing("CFrogClass");
  ret->class_id=cls_idx;
  U8 *name;
  if(name=I64SetGetAt(universe_values,cls_idx))
    StrCpy(ret->name,name);
  return ret;
}
Bool IsSmalltalkMember(CHashClass *cls) {
  I64 t;
  if(!cls->ptr_stars_cnt) {
    t=cls->raw_type;
    if(t==RT_F64)
      return TRUE;
    if(RT_I8<=t<=RT_U64)
      return TRUE;
  }
  CHashClass *fc=HashFind("CFrogThing",frog_mem_task->hash_table,HTT_CLASS);
  if(cls->type&HTT_FUN)
    return FALSE;
//Account for pointers to cls
  if(cls->ptr_stars_cnt)
    --cls;
  while(cls) {
    if(cls==fc){
      return TRUE;
    }
    cls=cls->base_class;
  }
  return FALSE;
}

//Returns FROG_SMALL_NIL if successful,else FROG_SMALL_ERR
CFrogThing *STSetVar(U8 *self,U8 *name,CFrogThing *val) {
  CLocalsGeneric *var=Fs->user_data;
  I64 ud,t;
  CHashGeneric *g;
  CFrogSymbol *sym;
  CMemberLst *lst;
  CHashClass *cls;
  CFrogThing **member;
  if(!var) throw('UndefVar');
  throw('UndefVar');
}


CFrogNum *FrogThingIsKindOf(CFrogThing *obj,CFrogClass *cls) {
  return FrogNumNew(ThingHasClass(obj,cls->name));
}
CFrogClass *FrogThingClass(CFrogThing *obj) {
  if(obj&1) {
//TODOoptimize
    return FrogClassNew(UniverseAddClass(FrogThingClassName(obj)));
  }
  return FrogClassNew(obj->id);
}
CFrogClass *FrogThingIsNil(CFrogThing *obj) {
  return FrogNumNew(ThingHasClass(obj,"CFrogUndefined",FROG_SMALL_NIL));
}

U0 FramePtrAdd2(CHashTable *tab,U8 *nm,I64 value) {
  CHashGeneric *gen=CAlloc(sizeof(CHashGeneric),frog_mem_task);
  gen->str=StrNew(nm,frog_mem_task);
  gen->type=HTT_FRAME_PTR;
  gen->user_data0=value;
  HashAdd(gen,tab);
}

CLocalsGeneric *STNewReplFrame(I64 *return_flag) {
  static CLocalsGeneric frs;
  CLocalsGeneric *fr=&frs,*fr2;
  CAST *name,*head;
  fr->thing_flags|=THINGF_FRAME_TYPE;
  fr2=Fs->user_data;
  fr->type='Repl';
  fr->next=Fs->user_data;
  Fs->user_data=fr;
  fr->return_flag=return_flag;
  return fr;
}

CFrogThing *FrogBlockNew(U8 *fptr,CLocalsGeneric *frame,CFrogThing *self) {
  CFrogBlock *ret=ConstructThing("CFrogBlock");
  I64 idx;
  ret->frame=frame;
  ret->fun_ptr=fptr;
  FrogIncRefCnt(frame);
  ret->self=self;
  return ret;
}
CFrogThing *FrogArrayAt(CFrogArray *self,I64 n) {
  if(0<=n<self->items->cnt) {
   return FrogIncRefCnt(self->items->body[n]);
  }
  return FROG_SMALL_NIL;
}

 CFrogThing *FrogStrAt(CFrogStr *self,I64 n) {
  if(0<=n<self->items->cnt) {
   return FrogChrNew(self->items->body[n]);
  }
  return FROG_SMALL_NIL;
}


CFrogThing *FrogArrayAtPut(CFrogArray *self,I64 n,CFrogThing *t) {
  I64 *at;
  if(0<=n<self->items->cnt) {
    at=&self->items->body[n];
    *at=FrogIncRefCnt(t);
  } else if(n==self->items->cnt) {
    I64SetAdd(self->items,FrogIncRefCnt(t));
  }
  return FROG_SMALL_NIL;
}
CFrogThing *FrogStrAtPut(CFrogStr *self,I64 n,CFrogChr *t) {
  U8 *at;
  if(0<=n<self->items->cnt) {
    at=&self->items->body[n];
    *at=AsChar(t);
  } else if(n==self->items->cnt) {
    U8SetAdd(self->items,AsChar(t));
  }
  return FROG_SMALL_NIL;
}
CFrogThing *FrogArrayRemAt(CFrogArray *self,I64 n) {
  I64 idx;
  I64 *flat=self->items->body;
  if(0<=n<self->items->cnt) {
    for(idx=n;idx<self->items->cnt-1;idx++) {
      flat[idx]=flat[idx+1];
    }
    self->items->cnt--;
  }
  return FROG_SMALL_NIL;
}
CFrogThing *FrogStrRemAt(CFrogArray *self,I64 n) {
  I64 idx;
  U8 *flat=self->items->body;
  if(0<=n<self->items->cnt) {
    for(idx=n;idx<self->items->cnt-1;idx++) {
      flat[idx]=flat[idx+1];
    }
    self->items->cnt--;
  }
  return FROG_SMALL_NIL;
}
CFrogThing *FrogArrayRemove(CFrogArray *self, CFrogThing *t) {
  I64 idx,ptr=0;
  I64 *flat=self->items->body;
  CFrogThing *ret;
  for(idx=0;idx<self->items->cnt;idx++) {
    ret=CallScript("=",flat[idx],FrogIncRefCnt(t));
    if(ThingIsError(ret)) {
      return ret;
    }if(AsF64(ret)) {
      //Skip
    } else
      flat[ptr++]=flat[idx];
  }
  self->items->cnt=ptr;
  return FROG_SMALL_NIL;
}

CFrogThing *FrogArrayEqual(CFrogArray *self, CFrogArray *t) {
  I64 idx,ptr=0;
  I64 *flat=self->items->body;
  I64 *flat2=t->items->body;
  CFrogThing *ret;
  if(self->items->cnt!=t->items->cnt)
    return FrogNumNew(0);
  for(idx=0;idx<self->items->cnt;idx++) {
    ret=CallScript("=",flat[idx],flat2[idx]);
    if(AsF64(ret)) {
      //Skip
    } else
      return FrogNumNew(0.);
  }
  return FrogNumNew(1);
}
CFrogThing *FrogArrayNotEqual(CFrogArray *self, CFrogArray *t) {
  I64 idx,ptr=0;
  I64 *flat=self->items->body;
  I64 *flat2=t->items->body;
  if(self->items->cnt!=t->items->cnt)
    return FrogNumNew(1);
  CFrogThing *ret;
  for(idx=0;idx<self->items->cnt;idx++) {
    ret=CallScript("=",flat[idx],flat2[idx]);
    if(AsF64(ret)) {
      //Skip
    } else
      return FrogNumNew(1);
  }
  return FrogNumNew(0);
}

U0 FrogArrayDel(CFrogArray *self) {
  I64SetDel(self->items);
  Free(self);
}
U0 FrogStrDel(CFrogArray *self) {
  U8SetDel(self->items);
  Free(self);
}
//Example
//
//  ConstructBuiltin("FrogNumNew(AsF64(a)+AsF64(self))","CFrogNum","CFrogNum","+","CFrogNum","a");
//
U0 ConstructBuiltin(U8 *code,U8 *type,U8 *return_type,U8 *name,...) { 
  if(argc&1) {//Odd
    "%s\n",name;
    throw('Builtin');
  }
  I64 idx;
  static I64 cnt=0;
  U8 uniq[STR_LEN],*class_name,*rt;
  I64 small_type_code;
  StrPrint(uniq,"%s@Prim%d",type,cnt++);
  StreamPrint("CFrogThing *%s(%s *self,...) {\n",uniq,type);
  StreamPrint("CFrogThing *ret=NULL;\n");
  StreamPrint("I64 failed=FALSE;\n");
  for(idx=0;idx<argc;idx+=2) {
    StreamPrint("%s* %s=argv[%d];\n",argv[idx],argv[idx+1],idx/2);
  }
  for(idx=0;idx!=argc;idx+=2) {
    class_name=argv[idx];
    if(!StrCmp(class_name,"CFrogNum"))
      small_type_code=FROG_SMALL_NUM;
    else if(!StrCmp(class_name,"CFrogUndefined"))
      small_type_code=FROG_SMALL_NIL;
    else if(!StrCmp(class_name,"CFrogChr"))
      small_type_code=FROG_SMALL_CHR;
    else
      small_type_code=0;
    StreamPrint("if(!ThingHasClass(%s,\"%Q\",%d)) {failed=TRUE;}\n",argv[idx+1],argv[idx],small_type_code);
  }
  StreamPrint("if(failed) {ret=FROG_SMALL_NIL;goto retlab;}\n");
  StreamPrint("ret=%s;\n",code);
  StreamPrint("retlab:\n");
  StreamPrint("return ret;\n");
  StreamPrint("};\n");
  StreamPrint("AddMethod(\"%Q\",\"%Q\",&%s);\n",type,name,uniq);
  rt=MStrPrint("RET_TYPE_%s.%s",type,name);
  if(return_type)
    FramePtrAdd(rt,StrNew(return_type));
  Free(rt);
};
CFrogThing *FrogChrIsAlNum(CFrogChr *self,...) {
  return FrogNumNew(Bt(char_bmp_alpha_numeric,AsChar(self)));
}
CFrogThing *FrogChrIsWhitespace(CFrogChr *self,...) {
  return FrogNumNew(Bt(char_bmp_white_space,AsChar(self)));
}
CFrogThing *FrogChrIsNumber(CFrogChr *self,...) {
  return FrogNumNew(Bt(char_bmp_dec_numeric,AsChar(self)));
}
CFrogThing *FrogChrIsDisplayable(CFrogChr *self,...) {
  return FrogNumNew(Bt(char_bmp_displayable,AsChar(self)));
}
CFrogThing *FrogChrUppercase(CFrogChr *self,...) {
  return FrogChrNew(ToUpper(AsChar(self)));
}

CFrogNum *FrogStrEqual(CFrogStr *self,...) {
  CFrogStr *other=argv[0];
  if(!ThingHasClass(other,"CFrogStr")) return FrogNumNew(0);
  if(self->items->cnt!=other->items->cnt) return FrogNumNew(0);
  if(!StrCmp(self->items->body,other->items->body)) return FrogNumNew(1);
  return FrogNumNew(0);
}
CFrogNum *FrogStrNotEqual(CFrogStr *self,...) {
  CFrogStr *other=argv[0];
  if(!ThingHasClass(other,"CFrogStr")) return FrogNumNew(1);
  if(self->items->cnt!=other->items->cnt) return FrogNumNew(1);
  if(!StrCmp(self->items->body,other->items->body)) return FrogNumNew(0);
  return FrogNumNew(1);
}

CFrogStr *FrogStrCopy(CFrogStr *self,...) {
  CFrogStr *s=ConstructThing("CFrogStr");
  Free(s->items->body);
  s->items->body=MAllocIdent(self->items->body,s->items->mem_task);
  s->items->cnt=self->items->cnt;
  return s;
}


CFrogStr *FrogStrCopy(CFrogStr *self,...) {
  CFrogStr *s=ConstructThing("CFrogStr");
  Free(s->items->body);
  s->items->body=MAllocIdent(self->items->body,s->items->mem_task);
  s->items->cnt=self->items->cnt;
  return s;
}
CFrogArray *FrogArrayCopy(CFrogStr *self,...) {
  I64 cnt;
  CFrogArray *s=ConstructThing("CFrogArray"),**body;
  Free(s->items->body);
  s->items->body=MAllocIdent(self->items->body,s->items->mem_task);
  cnt=self->items->cnt;
  s->items->cnt=cnt;
  body=s->items->body;
  while(--cnt>=0)
    body[cnt]=FrogIncRefCnt(body[cnt]);
  return s;
}
CFrogThing *FrogThingCopy(CFrogThing *t) {
  if(t&1) return t;
  CFrogThing *ret,dummy;
  MemSet(&dummy,0,sizeof CFrogThing);
  CMemberLst *mlst;
  CHashClass *cls=HashFind(t->class_name,frog_mem_task->hash_table,HTT_CLASS);
  if(!cls) return FROG_SMALL_NIL;
  ret=ConstructThing(t->class_name);
  while(cls) {
    for(mlst=cls->member_lst_and_root;mlst;mlst=mlst->next) {
      if(mlst->member_class->ptr_stars_cnt==1) {
        StrCpy(dummy.class_name,mlst->member_class[-1].str);
	if(ThingHasClass(&dummy,"CFrogThing")) {
	  (ret(U8*)+mlst->offset)(CFrogThing**)[0]=FrogIncRefCnt((t(U8*)+mlst->offset)(CFrogThing**)[0]);
	}
      }
    }
    cls=cls->base_class;
  } 
  return ret;
}
#exe {
//Char
  ConstructBuiltin("FrogChrIsAlNum(self)","CFrogChr","CFrogNum","isAlphaNumeric");
  ConstructBuiltin("FrogChrIsWhitespace(self)","CFrogChr","CFrogNum","isWhitespace");
  ConstructBuiltin("FrogChrIsDisplayable(self)","CFrogChr","CFrogNum","isDisplayable");
  ConstructBuiltin("FrogChrIsNumber(self)","CFrogChr","CFrogNum","isNumber");
  ConstructBuiltin("FrogChrUppercase(self)","CFrogChr","CFrogChr","uppercase");
}
#exe {
//Object
  ConstructBuiltin("FrogThingClass(self)","CFrogThing","CFrogClass","class");
  ConstructBuiltin("FrogThingIsNil(self)","CFrogThing","CFrogNum","isNil");
  ConstructBuiltin("FrogNumNew(self==a)","CFrogThing","CFrogNum","=","CFrogThing","a");
  ConstructBuiltin("FrogNumNew(self!=a)","CFrogThing","CFrogNum","~=","CFrogThing","a");
}
#exe {
//Set
  ConstructBuiltin("FrogArrayRemove(self,thing)","CFrogArray",NULL,"remove:","CFrogThing","thing");
  ConstructBuiltin("FROG_SMALL_NIL;I64SetAdd(self->items,FrogIncRefCnt(thing));","CFrogArray",NULL,"add:","CFrogThing","thing");
  ConstructBuiltin("FrogArrayAtPut(self,AsF64(idx),thing)","CFrogArray",NULL,"at:put:","CFrogNum","idx","CFrogThing","thing");
  ConstructBuiltin("FrogArrayAt(self,AsF64(idx))","CFrogArray","CFrogThing","at:","CFrogNum","idx");
  ConstructBuiltin("FrogArrayRemAt(self,AsF64(thing))","CFrogArray",NULL,"removeAt:","CFrogNum","thing");
  ConstructBuiltin("FrogNumNew(self->items->cnt)","CFrogArray","CFrogNum","size");
  ConstructBuiltin("FrogArrayCopy(self)","CFrogArray","CFrogArray","copy");
  ConstructBuiltin("FrogArrayEqual(self,other)","CFrogArray","CFrogNum","=","CFrogArray","other");
  ConstructBuiltin("FrogArrayNotEqual(self,other)","CFrogArray","CFrogNum","~=","CFrogArray","other");
}
#exe {
//String
  ConstructBuiltin("FrogArrayRemove(self,thing)","CFrogStr",NULL,"remove:","CFrogThing","thing");
  ConstructBuiltin("FROG_SMALL_NIL;U8SetAdd(self->items,AsChar(thing));","CFrogStr",NULL,"add:","CFrogChr","thing");
  ConstructBuiltin("FrogStrAtPut(self,AsF64(idx),thing)","CFrogStr",NULL,"at:put:","CFrogNum","idx","CFrogChr","thing");
  ConstructBuiltin("FrogStrAt(self,AsF64(idx))","CFrogStr","CFrogChr","at:","CFrogNum","idx");
  ConstructBuiltin("FrogStrRemAt(self,AsF64(thing))","CFrogStr",NULL,"removeAt:","CFrogNum","thing");
  ConstructBuiltin("FrogNumNew(self->items->cnt)","CFrogStr","CFrogNum","size");
  ConstructBuiltin("FrogStrCopy(self)","CFrogStr","CFrogStr","copy");
  ConstructBuiltin("FrogStrNotEqual(self,other)","CFrogStr","CFrogNum","~=","CFrogStr","other");
  ConstructBuiltin("FrogStrEqual(self,other)","CFrogStr","CFrogNum","=","CFrogStr","other");
}
#exe {
//Arithmetic
  ConstructBuiltin("FrogNumNew(AsF64(self)<AsF64(a))","CFrogNum","CFrogNum","<","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)>AsF64(a))","CFrogNum","CFrogNum",">","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)<=AsF64(a))","CFrogNum","CFrogNum","<=","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)>=AsF64(a))","CFrogNum","CFrogNum",">=","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)==AsF64(a))","CFrogNum","CFrogNum","=","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)!=AsF64(a))","CFrogNum","CFrogNum","~=","CFrogNum","a");

  ConstructBuiltin("FrogNumNew(AsF64(self)+AsF64(a))","CFrogNum","CFrogNum","+","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)-AsF64(a))","CFrogNum","CFrogNum","-","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)*AsF64(a))","CFrogNum","CFrogNum","*","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)/AsF64(a))","CFrogNum","CFrogNum","basicDiv:","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)/AsF64(a))","CFrogNum","CFrogNum","/","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)%AsF64(a))","CFrogNum","CFrogNum","basicRem:","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(ToI64(AsF64(self))/ToI64(AsF64(a)))","CFrogNum","CFrogNum","basicIntDiv:","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(-AsF64(self))","CFrogNum","CFrogNum","negated");
  ConstructBuiltin("FrogNumNew(AsF64(self)`AsF64(a))","CFrogNum","CFrogNum","raisedTo:","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(Floor(AsF64(self)))","CFrogNum","CFrogNum","floor");
  ConstructBuiltin("FrogNumNew(Round(AsF64(self)))","CFrogNum","CFrogNum","round");
  ConstructBuiltin("FrogNumNew(Ceil(AsF64(self)))","CFrogNum","CFrogNum","ceil");
  ConstructBuiltin("FrogNumNew(Log10(AsF64(self)))","CFrogNum","CFrogNum","log");
  ConstructBuiltin("FrogNumNew(Sin(AsF64(self)))","CFrogNum","CFrogNum","sin");
  ConstructBuiltin("FrogNumNew(Cos(AsF64(self)))","CFrogNum","CFrogNum","cos");
  ConstructBuiltin("FrogNumNew(Tan(AsF64(self)))","CFrogNum","CFrogNum","tan");
  ConstructBuiltin("FrogNumNew(ASin(AsF64(self)))","CFrogNum","CFrogNum","arcsin");
  ConstructBuiltin("FrogNumNew(ACos(AsF64(self)))","CFrogNum","CFrogNum","arccos");
  ConstructBuiltin("FrogNumNew(ATan(AsF64(self)))","CFrogNum","CFrogNum","arctan");
  ConstructBuiltin("FrogNumNew(Sqrt(AsF64(self)))","CFrogNum","CFrogNum","sqrt");
}
#exe {
//Bits
  ConstructBuiltin("FrogNumNew(~ToI64(AsF64(self)))","CFrogNum","CFrogNum","bitInvert");
  ConstructBuiltin("FrogNumNew(ToI64(AsF64(self))&ToI64(AsF64(a)))","CFrogNum","CFrogNum","&","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(ToI64(AsF64(self))|ToI64(AsF64(a)))","CFrogNum","CFrogNum","|","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(ToI64(AsF64(self))^ToI64(AsF64(a)))","CFrogNum","CFrogNum","^","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(ToI64(AsF64(self))&(1<<ToI64(AsF64(a))))","CFrogNum","CFrogNum","bitAt:","CFrogNum","a");
}
#exe {
//Conversion
  ConstructBuiltin("FrogNumNew(ToI64(AsF64(self)))","CFrogNum","CFrogNum","asInteger");
  ConstructBuiltin("FrogChrNew(AsF64(self))","CFrogNum","CFrogChr","asCharactor");
  ConstructBuiltin("FrogNumNew(AsChar(self))","CFrogChr","CFrogNum","asciiValue");
};;
Bool ValidateFrame(CLocalsGeneric *g) {
  CLocalsGeneric *cur=Fs->user_data;
  while(cur) {
    if(g==cur) return TRUE;
    cur=cur->next;
  }
  return FALSE;  
}
CFrogThing *_FrogBlockValue(CFrogBlock *self,I64 argc,I64 *argv) {
  CFrogThing *ret;
  I64 return_flag;
  CLocalsGeneric *old_frame=Fs->user_data,*cur=self->frame,*cur2,dummy;
  if(ChkOnStk(cur)) {
//Make sure cur is a valid frame,otherwise use a dummy;
    cur2=old_frame;
    while(cur2) {
      if(cur2==cur)
	goto fin;
      cur2=cur2->next;
    }
    MemSet(&dummy,0,sizeof CLocalsGeneric);
    dummy.type='Block';
    dummy.return_flag=&dummy.ret_flag;
    cur=&dummy;
  }
fin:
  Fs->user_data=cur;
  ret=CallVaArgs(self->fun_ptr,argc,argv,self->self,cur);
  if(*cur->return_flag) {
//Propigate the return upwards
    cur2=old_frame;
    while(cur->parent!=cur2) {
      if(!cur2) break; //???
      if(cur2->return_flag)
        *cur2->return_flag=TRUE;
      cur2=cur2->next;
    }
  }
exit:
  Fs->user_data=old_frame;
  return ret;
}
CFrogThing *FrogBlockValue(CFrogBlock *s,...) {
  return _FrogBlockValue(s,argc,argv);
}

#exe {
  StreamPrint("AddMethod(\"CFrogBlock\",\"value\",&FrogBlockValue);\n");
  //args are delegated to block's code
  I64 i,j;
  for (i=1;i<=5;++i) {
    StreamPrint("AddMethod(\"CFrogBlock\",\"");
    for (j=0;j<i;++j)
      StreamPrint("value:");
    StreamPrint("\",&FrogBlockValue);\n");
  }
}

//Exception handler
CFrogThing *FrogBlockOnDo(CFrogBlock *self,...) {
  CFrogThing *ret=FrogBlockValue(self);
  CFrogBlock *do_block=argv[1];
  CFrogClass *err_class=argv[0];
  CFrogError *e;
  if(ThingIsError(ret)&&ThingHasClass(err_class,"CFrogClass")) {
     e=FramePtr(FROG_FP_ERROR);
     if(!e) throw('STIntern');
     if(ThingHasClass(e,err_class->name)) {
       ret=FrogBlockValue(do_block,ret);
     }
  }
  return ret;
}
AddMethod("CFrogBlock","on:do:",&FrogBlockOnDo);


CFrogThing *FrogIfTrue(CFrogNum *self,...) {
  CFrogBlock *cond=argv[0];
  CFrogThing *ret;
  if(!ThingHasClass(self,"CFrogNum",FROG_SMALL_NUM)||!ThingHasClass(cond,"CFrogBlock")) {
    return FROG_SMALL_NIL;
  }
  if(ThingIsError(self)) {
    ret=FROG_SMALL_ERROR;
  } else if(AsF64(self)!=0.) {
    ret=FrogBlockValue(cond);
  } else
    ret=FROG_SMALL_NIL;
  return ret;
}
AddMethod("CFrogNum","ifTrue:",&FrogIfTrue);

CFrogThing *FrogIfFalse(CFrogNum *self,...) {
  CFrogBlock *cond=argv[0];
  CFrogThing *ret;
  if(!ThingHasClass(self,"CFrogNum",FROG_SMALL_NUM)||!ThingHasClass(cond,"CFrogBlock")) {
    return FROG_SMALL_NIL;
  }
  if(ThingIsError(self)) {
    ret=FROG_SMALL_ERROR;
  } else if(AsF64(self)==0.) {
    ret=FrogBlockValue(cond);
  } else
    ret=FROG_SMALL_NIL;
  return ret;
}
AddMethod("CFrogNum","ifFalse:",&FrogIfFalse);

CFrogThing *FrogIfTrueIfFalse(CFrogNum *self,...) {
  CFrogBlock *cond=argv[0];
  CFrogBlock *cond2=argv[1];
  CFrogThing *ret;
  if(!ThingHasClass(self,"CFrogNum",FROG_SMALL_NUM)||!ThingHasClass(cond,"CFrogBlock")
        ||!ThingHasClass(cond2,"CFrogBlock")) {
    return FROG_SMALL_NIL;
  }
  if(ThingIsError(self)) {
    ret=FROG_SMALL_ERROR;
  } else if(AsF64(self)) {
    ret=FrogBlockValue(cond);
  } else 
    ret=FrogBlockValue(cond2);
  return ret;
}
AddMethod("CFrogNum","ifTrue:ifFalse:",&FrogIfTrueIfFalse);

CFrogThing *FrogThingShow(CFrogStr *self,...) {
  I64 attempt;
  I64 idx,ch;
  static I64 err_msg=NameToUniverseNumber("error_msg");
  CFrogStr *msg;
  CI64Set *items;
  CU8Set *items_str;
  for(attempt=0;attempt!=2;attempt++) {
    if(ThingHasClass(self,"CFrogError",FROG_SMALL_ERROR)) {
      "Error:";
      msg=FrogSymbol0(err_msg)(CFrogSymbol*)->value;
      FrogThingShow(msg);
      break;
    } else if(ThingHasClass(self,"CFrogNum",FROG_SMALL_NUM)) {
      DbgPrint("%n\n",AsF64(self));
      break;
    } else if(ThingHasClass(self,"CFrogChr")) {
      DbgPrint("%c\n",AsChar(self));
      break;
    } else if(ThingHasClass(self,"CFrogStr")) {
      idx=0;
      items_str=self(CFrogStr*)->items;
      DbgPrint("'");
      for(idx=0;idx<items_str->cnt;idx++)
        DbgPrint("%c",items_str->body[idx]);
      DbgPrint("'\n");
      break;
    } else  {
      if(!(self&1))
        DbgPrint("<%s.%x>\n",self->class_name,self);
      else
        DbgPrint("???\n");
      break;
    }
  }
  return FROG_SMALL_NIL;
}
AddMethod("CFrogThing","show",&FrogThingShow);


CFrogThing *FrogNumTimesRepeat(CFrogNum *self,...) {
  CFrogBlock *block=argv[0],*ret=FROG_SMALL_NIL;
  I64 cnt;
  Bool *return_flag=block->frame(CLocalsGeneric *)->return_flag;
  if(!ThingHasClass(self,"CFrogNum")||!ThingHasClass(block,"CFrogBlock")) {
    return FROG_SMALL_NIL;
  }
  cnt=AsF64(self);
  while(--cnt>=0) {
    ret=FrogBlockValue(block);
    if(ThingIsError(ret))
      break;
    ret=FROG_SMALL_NIL;
    if(*return_flag)
      break;
  }
  return ret;
}
AddMethod("CFrogNum","timesRepeat:",&FrogNumTimesRepeat);


CFrogThing *FrogWhileTrue(CFrogBlock *self,...) {
  CFrogBlock *pass=argv[0],*ret=FROG_SMALL_NIL;
  CFrogNum *cond;
  if(!ThingHasClass(self,"CFrogBlock")||!ThingHasClass(pass,"CFrogBlock")) {
    return FROG_SMALL_NIL;
  }
  Bool *return_flag=self->frame(CLocalsGeneric *)->return_flag;
  while(TRUE) {
     cond=FrogBlockValue(self);
     if(ThingIsError(cond)) {
       ret=cond;
       break;
     }
     if(*return_flag) {
	ret=cond;
        break;
     }
     if(ThingHasClass(cond,"CFrogNum",FROG_SMALL_NUM)) {
       if(AsF64(cond)) {
         goto on_true;
       }
     } else {
       break;
     }
     break;
on_true:
     ret=FrogBlockValue(pass);
     if(ThingIsError(ret))
        break;
     if(*return_flag)
        break;
     ret=FROG_SMALL_NIL;
  }
  return ret;
}
AddMethod("CFrogBlock","whileTrue:",&FrogWhileTrue);


CFrogThing *FrogWhileFalse(CFrogBlock *self,...) {
  CFrogBlock *pass=argv[0];
  CFrogNum *cond,*ret=FROG_SMALL_NIL;
  if(!ThingHasClass(self,"CFrogBlock")||!ThingHasClass(pass,"CFrogBlock")) {
    return FROG_SMALL_NIL;
  }
  Bool *return_flag=self->frame(CLocalsGeneric *)->return_flag;
  while(TRUE) {
    cond=FrogBlockValue(self);
    if(ThingIsError(cond)) {
      ret=cond;
      break;
    }
     if(*return_flag) {
       ret=cond;
       break;
     }
    if(ThingHasClass(cond,"CFrogNum",FROG_SMALL_NUM)) {
      if(AsF64(cond)==0.) {
        break;
      }
    } else {
//Not anumber
      ret=FROG_SMALL_NIL;
      break;
    }
    ret=FrogBlockValue(pass);
    if(ThingIsError(ret))
        break;
    if(*return_flag)
      break;
    ret=FROG_SMALL_NIL;
  }
  return ret;
}
AddMethod("CFrogBlock","whileFalse:",&FrogWhileFalse);

extern U0 FrogGarbageCollect(CFrogThing *root);
U0 ThingDel(CFrogThing *thing,Bool recurse=TRUE) {
  U8 *del;
  I64 idx;
  CLocalsGeneric *g,*parent;
  CFrogThing **f,dummy;
//This has the destroy in it
  CConstructorPair *cpair;
  CMemberLst *mlst;
  CHashClass *cls;
  CHashFun *fun;
  U0 (*destroy)(CFrogThing*);
  if(!thing||thing&1) return; //bit 0 is set for special "SMALL" type
  FrogThingLock(thing);
  if(--thing->ref_cnt<=0) {
  if(thing->ref_cnt<0) {throw('asdas'); }
    if(thing->thing_flags&THINGF_FRAME_TYPE) {
      g=thing;
      if(g->type=='Repl') {
        FrogThingUnlock(thing);
        return;
      }
      QueRem(thing);
      if(recurse) {
        idx=g->item_cnt;
        while(--idx>=0) {
	  if(!(g->raw_mask&(1<<idx)))
	    ThingDel(g->body[idx]);
        }
        if(g->type=='Block') {
	  parent=g->parent;
	  if(parent!=g) //Important check
	    if(parent->type=='Block'||parent->type=='Method') {
	      ThingDel(parent);
	    }
        }
      }
      FrogThingUnlock(thing);
      Free(thing);
      return;
    }
    QueRem(thing);
    UniverseDestroyThing(thing);
  }
}
CFrogUndefined *FrogNil() {
  return FROG_SMALL_NIL;
}

U0 FrogGarbageCollectThing(CFrogThing *root,Bool debug=FALSE) {
  if(!root||root&1) return; //bit 0 is set for special "small" values
  if(ChkOnStk(root)) return;
  static I64 depth=0;
  I64 idx;
  CLocalsGeneric *g,*p;
  CFrogThing **body,dummy;
  MemSet(&dummy,0,sizeof(CFrogThing));
  CHashClass *cls,*cls2;
  CMemberLst *mlst;
  root->shadow_ref_cnt++;
  if(debug) "$$ID,2$$%s,%x\n",root->class_name,root;
  if(LBts(&root->thing_flags,THINGf_GC_LOCK))
    goto fin;
  LBtr(&root->thing_flags,THINGf_TO_DELETE);
  if(ThingHasClass(root,"CFrogFrame")) {
    g=root;
    idx=g->item_cnt;
    while(--idx>=0) {
      if(!(g->raw_mask&(1<<idx)))
        FrogGarbageCollectThing(g->body[idx],debug); 
    }
    if(g->type=='Block')
      FrogGarbageCollectThing(g->parent,debug);
  } else if(ThingHasClass(root,"CFrogArray")) {
    body=root(CFrogArray*)->items->body;
    idx=root(CFrogArray*)->items->cnt;
    while(--idx>=0) {
      FrogGarbageCollectThing(body[idx],debug);
    }
  } else {
    cls=HashFind(FrogThingClassName(root),frog_mem_task->hash_table,HTT_CLASS);
    while(cls) {
      for(mlst=cls->member_lst_and_root;mlst;mlst=mlst->next) {
	cls2=mlst->member_class-mlst->member_class->ptr_stars_cnt;
        StrCpy(dummy.class_name,cls2->str);
        if(ThingHasClass(&dummy,"CFrogThing")) {
//TODO scan for pointers of pointers
	  if(mlst->member_class->ptr_stars_cnt==1) {
	    body=root(U8*)+mlst->offset;
	    idx=mlst->dim.total_cnt;
	    while(--idx>=0) {
	      FrogGarbageCollectThing(body[idx],debug);
	    }
          }
	} 
      }
      cls=cls->base_class;
    }
  }
fin:
  if(debug) "$$ID,-2$$\n";
}
U0 FrogDisableScripts() {
  LBts(&gc_lock,0);  
  I64 c=mp_cnt;
  while(--c>=0) {
    while(LBts(&cpu_call_script_lock,c)) {
      Sleep(1);
    }
  }
}
U0 FrogEnableScripts() {
  I64 c=mp_cnt;
  while(--c>=0)
    LBtr(&cpu_call_script_lock,c);
  LBtr(&gc_lock,0);
}
U0 FrogNullifySymbols() {
  CFrogSymbol *head=&allocs_head,*cur;
  FrogDisableScripts;
  for(cur=head->next;cur!=head;cur=cur->next) {
    if(ThingHasClass(cur,"CFrogSymbol")) {
      cur->value=FROG_SMALL_NIL;
    }
  }
  FrogEnableScripts;
}
//Run this on core 0,it will wait for cores to be done
U0 FrogGarbageCollect(CFrogThing *root=FROG_SMALL_NIL) {
  FrogDisableScripts;
  CFrogThing *head=&allocs_head,*cur,*next;
  for(cur=head->next;cur!=head;cur=cur->next) {
    if(!ThingHasClass(cur,"CFrogSymbol")) {
      LBts(&cur->thing_flags,THINGf_TO_DELETE);
      cur->shadow_ref_cnt=0;
      cur->ref_cnt=I64_MAX;
      
    }
  } 
  for(cur=head->next;cur!=head;cur=cur->next) {
    if(ThingHasClass(cur,"CFrogSymbol")) {
      FrogGarbageCollectThing(cur(CFrogSymbol*)->value);
    }
  }
  FrogGarbageCollectThing(root);
  for(cur=head->next;cur!=head;cur=next) {
    next=cur->next;
    if(ThingHasClass(cur,"CFrogSymbol")) {
    } else if(Bt(&cur->thing_flags,THINGf_TO_DELETE)) {
      cur->ref_cnt=1;
      ThingDel(cur,FALSE);
    } else {
      cur->ref_cnt=cur->shadow_ref_cnt;
      LBtr(&cur->thing_flags,THINGf_GC_LOCK);
    }
  }
  FrogEnableScripts;
}
U32 AsChar(CFrogThing *t) {
//CFrogSmallChr
  U64 sc=t;
  if(sc&0xffff==FROG_SMALL_CHR) {
     return sc>>32;
  }
  if(ThingHasClass(t,"CFrogChr")) { //Phat charactor?
    return t(CFrogChr*)->ch;
  }
  return 0;
}

//This is temporary,exepct changes
CFrogThing *FrogThingNew(CFrogClass *cls,...) {
  CHashClass *tmph;
  I64 cls_id=#exe{StreamPrint("%d",UniverseAddClass("CFrogClass"));};
  if(cls->id!=cls_id) return FROG_SMALL_NIL;
  U8 *name=I64SetGetAt(universe_values,cls->class_id);
  return ConstructThing(name);
}
AddClassMethod("CFrogThing","basicNew",&FrogThingNew);

CFrogNum *FrogHasClass(CFrogClass *self,...) {
  I64 id;
  if(self&1) {
    id=UniverseAddClass(FrogThingClassName(self));
  } else 
    id=self->id;
  CFrogClass *c=argv[0];
  if(c&1) return FROG_SMALL_NIL;
  I64 cls_id=#exe{StreamPrint("%d",UniverseAddClass("CFrogClass"));};
  if(c->id!=cls_id) return FROG_SMALL_NIL;
  return FrogNumNew(UniverseIsSubClassOf(id,c->class_id));
}
AddMethod("CFrogThing","hasClass:",&FrogHasClass);


CFrogStr *FrogClassName(CFrogClass *cls,...) {
  return FrogStrNew(cls->name);
}
//This is a class method
AddClassMethod("CFrogThing","name",&FrogClassName);

U8 *AsString(CFrogThing *t) {
  I64 idx;
  U8 *ret=NULL;
  CFrogThing *as_str;
  CU8Set *items;
  CU8Set *items_str;
  if(ThingHasClass(t,"CFrogBin")) {
    return MAllocIdent(t(CFrogBin*)->data);
  } else if(ThingHasClass(t,"CFrogStr")) {
      idx=0;
      items_str=t(CFrogStr*)->items;
      ret=CAlloc(items_str->cnt+1);
      for(idx=0;idx<items_str->cnt;idx++) {
        ret[idx]=items_str->body[idx];
      }
  } else {
    as_str=CallScript("printString",t);
    if(ThingHasClass(as_str,"CFrogStr")) {
      ret=AsString(as_str);
    } else
      ret=StrNew("");
  }
  return ret;
}

#include "../BlobFile.HC";
CFrogThing *FrogBlobFileOpen(CFrogBlobFile *f,...) {
  CFrogStr *name=argv[0];
  f->filename=CallScript("copy",name);
  return FROG_SMALL_NIL;
}
AddMethod("CFrogBlobFile","open:",&FrogBlobFileOpen);
CFrogThing *FrogBlobFileReadLump(CFrogBlobFile *f,...) {
  CFrogStr *lump=argv[0];
  U8 *blob_name=AsString(f->filename),*lump_name=AsString(lump);
  U8 *data;
  CFrogBin *ret=FROG_SMALL_NIL;
  if(blob_name&&lump_name) {
    if(data=BlobFileGetLump(blob_name,lump_name)) {
      ret=ConstructThing("CFrogBin");
      ret->data=data;
    } 
  }
  Free(lump_name);
  Free(blob_name);
  return ret;
} 
AddMethod("CFrogBlobFile","readLump:",&FrogBlobFileReadLump);

F64 frog_time_offset=-tS;
CFrogThing *FrogTimeNow(CFrogThing *ul,...) {
  CFrogTime *t=ConstructThing("CFrogTime");
  t->ts=FrogNumNew(tS+frog_time_offset);
  return t;
}
AddClassMethod("CFrogTime","now",&FrogTimeNow);
CFrogThing *FrogSetTime(CFrogThing *ul,...) {
  F64 t=AsF64(argv[0]);
  frog_time_offset=t-tS;
  return FROG_SMALL_NIL;
}
AddClassMethod("CFrogTime","setTime:",&FrogSetTime);

U0 FrogBinDel(CFrogBin *bin) {
  Free(bin->data);
  Free(bin);
}
Fs->user_data=0;
CFrogThing *FrogArrayDo(CFrogArray *self,...) {
  CFrogBlock *t=argv[0];
  I64 *clone=MAllocIdent(self->items->body);
  CLocalsGeneric *g=Fs->user_data;
  I64 cnt=self->items->cnt,idx;
  CFrogThing *ret=FROG_SMALL_NIL;
  for(idx=0;idx!=cnt;idx++) {
    ret=FrogBlockValue(t,clone[idx]);
    if(g->return_flag[0]||g->ret_flag) break;
  }
  Free(clone);
  return ret;
}
AddMethod("CFrogArray","do:",&FrogArrayDo);
