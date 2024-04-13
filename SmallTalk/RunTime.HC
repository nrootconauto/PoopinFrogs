$BK,0$
#exe {Cd(__DIR__);};;
#include "Parser.HC";
#include "RunTime.HH";
#include "Set.HC";
#include "FastLookup.HC";
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
//
// $BK,1$IMPORTANT,this is for th "super" keyword$BK,0$
//
class CFrogSuper:CFrogThing {
  U8 *destroy dft "FrogSuperDel";
  CFrogThing *from;
};
CTask *frog_mem_task=Fs;
CQue allocs_head;
QueInit(&allocs_head);

class CConstructorPair {
  U8 *dft;
  U8 *constructor;
  U8 *destroy;
};

U0 AddMethod(U8 *cls,U8 *name,U8 *fptr) {
//See GenerateMethodCall
  U8 *canon=MStrPrint("METHOD_%s.%s",cls,name);
//Replace(possibly dummy) method.
  if(FramePtr(canon))
    FramePtrSet(canon,fptr);
  else
    FramePtrAdd(canon,fptr);
  Free(canon);
  FastLookupAddValue(name,fptr,cls);
}
U0 AddClassMethod(U8 *cls,U8 *name,U8 *fptr) {
  name=MStrPrint(".%s",name);
  FastLookupAddValue(name,fptr,cls);
  Free(name);
}


extern U0 ThingDel(CFrogThing *thing,Bool recurse=TRUE);
extern F64 AsF64(CFrogThing *t);
extern U32 AsChar(CFrogThing *t);
extern CFrogThing *ToFrogNum(F64 n);

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



//Reduces the CFrogSuper class to the actual value
U8 *FrogUnSuper(CFrogSuper *s) {
  if(!s) return FROG_SMALL_NIL;
  if(s&1) return s;
  if(!StrCmp("CFrogSuper",s->class_name)) {
    return s->from;
  }
  return s;
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
    name=thing->class_name;
    if(!StrCmp(name,"CFrogSuper")) {
      name=FrogThingClassName(thing(CFrogSuper*)->from);
      cls=HashFind(name,frog_mem_task->hash_table,HTT_CLASS);
      if(cls) {
	if(cls=cls->base_class) {
	  return cls->str;
	}
      }
    }
  }
  return name;
}
Bool ThingHasClass(CFrogThing *thing,U8 *name,I64 small_type=0) {
//Quick check for small Types
  if(small_type&&thing&1) {
    return thing&0xffff==small_type;
  }
  if(!(thing&1))
    if(thing->thing_flags&THINGF_FRAME_TYPE) {
      if(!StrCmp(name,"CFrogFrame"))
        return TRUE;
      return FALSE;
    }
  CHashClass *cls=HashFind(FrogThingClassName(thing),frog_mem_task->hash_table,HTT_CLASS);
  while(cls) {
    if(!StrCmp(cls->str,name))
      return TRUE;
    cls=cls->base_class;
  }
  return FALSE;
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
  t=FrogUnSuper(t);
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
  t=FrogUnSuper(t);
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

U0 SetClassMemberValF64(CFrogThing *t,U8 *member,F64 val) {
  t=FrogUnSuper(t);
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
  t=FrogUnSuper(t);
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
//CFrogSuper is a special value
//Routines that call CFrogSuper reduce down to CFrogSuper->self,so skip this as ->self isnt assigned yet
  if(!StrCmp(t->class_name,"CFrogSuper")) {
   goto fin;
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
  QueIns(t,allocs_head.next);
  return t;
}
CFrogThing *ConstructThing(U8 *name,...) {
  CConstructorPair *p;
  CFrogThing *ret;
  CHashFun *fun;
  U0 (*init)(CFrogThing*);
  if(!StrCmp(name,"CFrogSuper"))
    return _ConstructThing(name,argc,argv);
  if(!argc)
    if(p=FastLookupByStr(".dft",name)) {
      ret=MAllocIdent(p->dft);
      ret->ref_cnt=1;
      QueIns(ret,allocs_head.next);
      if(p->constructor) {
        fun=HashFind(p->constructor,frog_mem_task->hash_table,HTT_FUN);
        if(fun) {
          init=fun->exe_addr;
	  (*init)(ret);
	}
      }
      return ret;
    }
  ret=_ConstructThing(name,argc,argv);
  if(!argc&&ret) {
    p=MAlloc(sizeof(CConstructorPair),frog_mem_task);
    p->dft=ret;
    QueRem(ret);//This is a template for new creation
    p->constructor=GetClassMemberValI64(ret,"constructor");
    p->destroy=GetClassMemberValI64(ret,"destroy");
    FastLookupAddValue(".dft",p,name);
    //Make a new one from the template
    ret=ConstructThing(name);
  }
  if(!ret) ret=FROG_SMALL_NIL;
  return ret;
}

CFrogSymbol *FrogSymbol(U8 *name) {
  CFrogSymbol *sym;
  name=MStrPrint("SYM#%s",name);
  if(sym=FramePtr(name,frog_mem_task)) {
  } else {
    sym=ConstructThing("CFrogSymbol");
    FramePtrAdd(name,sym,frog_mem_task);
    sym->value=FROG_SMALL_NIL;
  }
  Free(name);
  return sym;
}

CFrogThing *FrogNumNew(F64 val) {
  return ToFrogNum(val);
}
CFrogThing *FrogChrNew(U64 ch) {
  return (ch<<32)|FROG_SMALL_CHR;
}
U0 FrogArrayInit(CFrogArray *a) {
  a->items=I64SetNew(frog_mem_task);
} 
CFrogArray *FrogArrayNew() {
  CFrogArray *ret=ConstructThing("CFrogArray");
  return ret;
}

CFrogThing *FrogStrNew(U8 *s) {
  CFrogStr *str=ConstructThing("CFrogStr");
  CI64Set *items;
  items=str->items;
  for(;*s;s++) {
    I64SetAdd(items,FrogChrNew(*s));
  }
  return str;
}

CFrogThing *CallScriptFast(U8 *key1,U8 *key2,CFrogThing *self,...) {
  U8 *cn=FrogThingClassName(self);
  CFrogThing *(*fun_ptr)(CFrogThing *,...);
  CFrogThing *ret=NULL;
  CFastLookupKey *k;
  CHashClass *cls=HashFind(cn,frog_mem_task->hash_table,HTT_CLASS);
  if(ThingHasClass(self,"CFrogClass")) {
    cls=HashFind(self(CFrogClass*)->name,frog_mem_task->hash_table,HTT_CLASS);
    while(!ret&&cls) {
       if(fun_ptr=FastLookupGet(key2,cls->str)) {
        ret=CallVaArgs(fun_ptr,argc,argv,self);
	break;
      }
      cls=cls->base_class;
    }
    goto fin;
  }
  while(!ret&&cls) {
    if(fun_ptr=FastLookupGet(key1,cls->str)) {
      ret=CallVaArgs(fun_ptr,argc,argv,self);
      break;
    }
    cls=cls->base_class;
  }
fin:
  //ThingDel(self);
  if(!ret)
    ret=FROG_SMALL_NIL;
  return ret;
}

CFrogThing *CallPtr(U8 *fun_ptr,U8 *must_have,CFrogThing *self,...) {
  if(must_have) {
   if(!ThingHasClass(self,must_have)) {
     //ThingDel(self);
     return FROG_SMALL_NIL;
   }
  }
  CFrogThing *ret=CallVaArgs(fun_ptr,argc,argv,self);
  //ThingDel(self);
  if(!ret)
    ret=FROG_SMALL_NIL;
  return ret;
}


CFrogThing *CallScript(U8 *name,CFrogThing *self,...) {
  U8 *cn=FrogThingClassName(self);
  U8 *full=NULL;
  CFrogThing *(*fun_ptr)(CFrogThing *,...);
  CFrogThing *ret=NULL;
  CFastLookupKey *k;
  CHashClass *cls=HashFind(cn,frog_mem_task->hash_table,HTT_CLASS);
  full=MStrPrint(".%s",name);
  k=FastLookupKeyNew(full);
  if(ThingHasClass(self,"CFrogClass")) {
    cls=HashFind(self(CFrogClass*)->name,frog_mem_task->hash_table,HTT_CLASS);
    while(!ret&&cls) {
      if(fun_ptr=FastLookupGet(k,cls->str)) {
        ret=CallVaArgs(fun_ptr,argc,argv,self);
        //ThingDel(self);
	break;
      }
      cls=cls->base_class;
    }
    goto fin;
  }
  Free(k);
  k=FastLookupKeyNew(name);
  while(!ret&&cls) {
    if(fun_ptr=FastLookupGet(k,cls->str)) {
      ret=CallVaArgs(fun_ptr,argc,argv,self);
      //ThingDel(self);
      break;
    }
    cls=cls->base_class;
  }
fin:
  Free(k);
  Free(full);
  if(!ret)
    ret=FROG_SMALL_NIL;
  return ret;
}
class CLocalsGeneric:CFrogFrame {
  U64 type;
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
  if(s->type=='Block'||s->type=='Method')
    ThingDel(s);
}
CFrogThing *FrogIncRefCnt(CFrogThing *t) {
  if(!(t&1)) t->ref_cnt++;
  return t;
}

CFrogClass *FrogClassNew(U8 *name) {
  CFrogClass *ret;
  if(HashFind(name,frog_mem_task->hash_table,HTT_CLASS)) {
    ret=ConstructThing("CFrogClass");
    StrCpy(ret->name,name);
  } else
    ret=FROG_SMALL_NIL;
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

CFrogThing *STGetVar(U8 *self,U8 *name) {
  CLocalsGeneric *var=Fs->user_data;
  CHashGeneric *g;
  CFrogThing *f;
  CHashClass *cls;
  CMemberLst *lst;
  if(!var) return FROG_SMALL_NIL;
  self=FrogUnSuper(self);
  if(g=HashFind(name,frog_mem_task->hash_table,HTT_CLASS)) {
      return FrogClassNew(name);
  }
"UNDEF:%s\n",name;
  return FROG_SMALL_NIL;
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
  self=FrogUnSuper(self);
  throw('UndefVar');
}


CFrogNum *FrogThingIsKindOf(CFrogThing *obj,CFrogClass *cls) {
  return FrogNumNew(ThingHasClass(obj,cls->name));
}
CFrogClass *FrogThingClass(CFrogThing *obj) {
  return FrogClassNew(FrogThingClassName(obj));
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
CFrogThing *FrogArrayAtPut(CFrogArray *self,I64 n,CFrogThing *t) {
  I64 *at;
  if(0<=n<self->items->cnt) {
    at=&self->items->body[n];
    ThingDel(*at);
    *at=FrogIncRefCnt(t);
  } else if(n==self->items->cnt) {
    I64SetAdd(self->items,FrogIncRefCnt(t));
  }
  return FROG_SMALL_NIL;
}
CFrogThing *FrogArrayRemAt(CFrogArray *self,I64 n) {
  I64 idx;
  I64 *flat=self->items->body;
  if(0<=n<self->items->cnt) {
    ThingDel(flat[idx]);
    for(idx=n;idx<self->items->cnt-1;idx++) {
      flat[idx]=flat[idx+1];
    }
    self->items->cnt--;
  }
  return FROG_SMALL_NIL;
}
CFrogThing *FrogArrayRemove(CFrogArray *self,CFrogThing *t) {
  I64 idx,ptr=0;
  I64 *flat=self->items->body;
  CFrogThing *ret;
  for(idx=0;idx<self->items->cnt;idx++) {
    ret=CallScript("=",flat[idx],FrogIncRefCnt(t));
    if(ThingIsError(ret)) {
      return ret;
    }if(AsF64(ret)) {
      //Skip
      ThingDel(flat[idx]);
    } else
      flat[ptr++]=flat[idx];
    ThingDel(ret);
  }
  self->items->cnt=ptr;
  return FROG_SMALL_NIL;
}
U0 FrogArrayDel(CFrogArray *self) {
  I64 idx;
  I64 *flat=self->items->body;
  for(idx=0;idx<self->items->cnt;idx++) {
    ThingDel(flat[idx]);
  }
  I64SetDel(self->items);
  Free(self);
}
//Example
//
//  ConstructBuiltin("FrogNumNew(AsF64(a)+AsF64(self))","CFrogNum","+","CFrogNum","a");
//
U0 ConstructBuiltin(U8 *code,U8 *type,U8 *name,...) { 
  I64 idx;
  static I64 cnt=0;
  U8 uniq[STR_LEN],*class_name;
  I64 small_type_code;
  StrPrint(uniq,"%s@Prim%d",type,cnt++);
  StreamPrint("CFrogThing *%s(%s *self,...) {\n",uniq,type);
  StreamPrint("CFrogThing *ret=NULL;\n");
  StreamPrint("self=FrogUnSuper(self);");
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
  for(idx=0;idx<argc;idx+=2) {
    StreamPrint("ThingDel(%s);\n",argv[idx+1]);
  }
  StreamPrint("return ret;\n");
  StreamPrint("};\n");
  StreamPrint("AddMethod(\"%Q\",\"%Q\",&%s);\n",type,name,uniq);
};
#exe {
//Object
  ConstructBuiltin("FrogThingIsKindOf(self,thing)","CFrogThing","isKindOf:","CFrogClass","thing");
  ConstructBuiltin("FrogThingClass(self)","CFrogThing","class");
  ConstructBuiltin("FrogThingIsNil(self)","CFrogThing","isNil");
  ConstructBuiltin("FrogNumNew(self==a)","CFrogThing","=","CFrogThing","a");
  ConstructBuiltin("FrogNumNew(self!=a)","CFrogThing","~=","CFrogThing","a");
//Set
  ConstructBuiltin("FrogArrayRemove(self,thing)","CFrogArray","remove:","CFrogThing","thing");
  ConstructBuiltin("FROG_SMALL_NIL;I64SetAdd(self->items,FrogIncRefCnt(thing));","CFrogArray","add:","CFrogThing","thing");
  ConstructBuiltin("FrogArrayAtPut(self,AsF64(idx),thing)","CFrogArray","at:put:","CFrogNum","idx","CFrogThing","thing");
  ConstructBuiltin("FrogArrayAt(self,AsF64(idx))","CFrogArray","at:","CFrogNum","idx");
  ConstructBuiltin("FrogArrayRemAt(self,AsF64(thing))","CFrogArray","removeAt:","CFrogNum","thing");
  ConstructBuiltin("FrogNumNew(self->items->cnt)","CFrogArray","size");
//Arithmetic
  ConstructBuiltin("FrogNumNew(AsF64(self)<AsF64(a))","CFrogNum","<","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)>AsF64(a))","CFrogNum",">","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)<=AsF64(a))","CFrogNum","<=","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)>=AsF64(a))","CFrogNum",">=","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)==AsF64(a))","CFrogNum","=","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)!=AsF64(a))","CFrogNum","~=","CFrogNum","a");

  ConstructBuiltin("FrogNumNew(AsF64(self)+AsF64(a))","CFrogNum","+","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)-AsF64(a))","CFrogNum","-","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)*AsF64(a))","CFrogNum","*","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)/AsF64(a))","CFrogNum","basicDiv:","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(AsF64(self)%AsF64(a))","CFrogNum","basicRem:","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(ToI64(AsF64(self))/ToI64(AsF64(a)))","CFrogNum","basicIntDiv:","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(-AsF64(self))","CFrogNum","negated");
  ConstructBuiltin("FrogNumNew(AsF64(self)`AsF64(a))","CFrogNum","raisedTo:","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(Floor(AsF64(self)))","CFrogNum","floor");
  ConstructBuiltin("FrogNumNew(Round(AsF64(self)))","CFrogNum","round");
  ConstructBuiltin("FrogNumNew(Ceil(AsF64(self)))","CFrogNum","ceil");
  ConstructBuiltin("FrogNumNew(Log10(AsF64(self)))","CFrogNum","log");
  ConstructBuiltin("FrogNumNew(Sin(AsF64(self)))","CFrogNum","sin");
  ConstructBuiltin("FrogNumNew(Cos(AsF64(self)))","CFrogNum","cos");
  ConstructBuiltin("FrogNumNew(Tan(AsF64(self)))","CFrogNum","tan");
  ConstructBuiltin("FrogNumNew(ASin(AsF64(self)))","CFrogNum","arcsin");
  ConstructBuiltin("FrogNumNew(ACos(AsF64(self)))","CFrogNum","arccos");
  ConstructBuiltin("FrogNumNew(ATan(AsF64(self)))","CFrogNum","arctan");
  ConstructBuiltin("FrogNumNew(Sqrt(AsF64(self)))","CFrogNum","sqrt");
//Bits
  ConstructBuiltin("FrogNumNew(~ToI64(AsF64(self)))","CFrogNum","bitInvert");
  ConstructBuiltin("FrogNumNew(ToI64(AsF64(self))&ToI64(AsF64(a)))","CFrogNum","&","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(ToI64(AsF64(self))|ToI64(AsF64(a)))","CFrogNum","|","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(ToI64(AsF64(self))^ToI64(AsF64(a)))","CFrogNum","^","CFrogNum","a");
  ConstructBuiltin("FrogNumNew(ToI64(AsF64(self))&(1<<ToI64(AsF64(a))))","CFrogNum","bitAt:","CFrogNum","a");
//Conversion
  ConstructBuiltin("FrogNumNew(ToI64(AsF64(self)))","CFrogNum","asInteger");
  ConstructBuiltin("FrogChrNew(AsF64(self))","CFrogNum","asCharactor");
  ConstructBuiltin("FrogNumNew(AsChar(self))","CFrogChr","asciiValue");
};
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
  Fs->user_data=cur;
fin:
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
  ThingDel(do_block);
  ThingDel(err_class);
  return ret;
}
AddMethod("CFrogBlock","on:do:",&FrogBlockOnDo);


CFrogThing *FrogIfTrue(CFrogNum *self,...) {
  CFrogBlock *cond=argv[0];
  CFrogThing *ret;
  if(!ThingHasClass(self,"CFrogNum",FROG_SMALL_NUM)||!ThingHasClass(cond,"CFrogBlock")) {
    ThingDel(cond);
    return FROG_SMALL_NIL;
  }
  self=FrogUnSuper(self);
  cond=FrogUnSuper(cond);
  if(ThingIsError(self)) {
    ret=FROG_SMALL_ERROR;
  } else if(AsF64(self)!=0.) {
    ret=FrogBlockValue(cond);
  } else
    ret=FROG_SMALL_NIL;
  ThingDel(cond);
  return ret;
}
AddMethod("CFrogNum","ifTrue:",&FrogIfTrue);

CFrogThing *FrogIfFalse(CFrogNum *self,...) {
  CFrogBlock *cond=argv[0];
  CFrogThing *ret;
  if(!ThingHasClass(self,"CFrogNum",FROG_SMALL_NUM)||!ThingHasClass(cond,"CFrogBlock")) {
    ThingDel(cond);
    return FROG_SMALL_NIL;
  }
  self=FrogUnSuper(self);
  cond=FrogUnSuper(cond);
  if(ThingIsError(self)) {
    ret=FROG_SMALL_ERROR;
  } else if(AsF64(self)==0.) {
    ret=FrogBlockValue(cond);
  } else
    ret=FROG_SMALL_NIL;
  ThingDel(cond);
  return ret;
}
AddMethod("CFrogNum","ifFalse:",&FrogIfFalse);

CFrogThing *FrogIfTrueIfFalse(CFrogNum *self,...) {
  CFrogBlock *cond=argv[0];
  CFrogBlock *cond2=argv[1];
  CFrogThing *ret;
  self=FrogUnSuper(self);
  cond=FrogUnSuper(cond);
  cond2=FrogUnSuper(cond2);
  if(!ThingHasClass(self,"CFrogNum",FROG_SMALL_NUM)||!ThingHasClass(cond,"CFrogBlock")
        ||!ThingHasClass(cond2,"CFrogBlock")) {
    ThingDel(cond);
    ThingDel(cond2);
    return FROG_SMALL_NIL;
  }
  if(ThingIsError(self)) {
    ret=FROG_SMALL_ERROR;
  } else if(AsF64(self)) {
    ret=FrogBlockValue(cond);
  } else 
    ret=FrogBlockValue(cond2);
  ThingDel(cond);
  ThingDel(cond2);
  return ret;
}
AddMethod("CFrogNum","ifTrue:ifFalse:",&FrogIfTrueIfFalse);

CFrogThing *FrogThingShow(CFrogStr *self,...) {
  I64 attempt;
  I64 idx,ch;
  CFrogStr *msg;
  CI64Set *items;
  self=FrogUnSuper(self);
  for(attempt=0;attempt!=2;attempt++) {
    if(ThingHasClass(self,"CFrogError",FROG_SMALL_ERROR)) {
      "Error:";
      msg=FrogSymbol("error_msg")(CFrogSymbol*)->value;
      if(ThingHasClass(msg,"CFrogStr")) {
        idx=0;
        items=msg(CFrogStr*)->items;
        "'";
        for(idx=0;idx<items->cnt;idx++)
	  "%c",AsChar(items->body[idx]);
        "'";
      }
      "\n";
      ThingDel(msg);
      break;
    } else if(ThingHasClass(self,"CFrogNum",FROG_SMALL_NUM)) {
      "%n\n",AsF64(self);
      break;
    } else if(ThingHasClass(self,"CFrogChr")) {
      "%c\n",AsChar(self);
      break;
    } else if(ThingHasClass(self,"CFrogStr")) {
      idx=0;
      items=self(CFrogStr*)->items;
      "'";
      for(idx=0;idx<self->items->cnt;idx++)
        "%c",AsChar(items->body[idx]);
      "'\n";
      break;
    } else  {
      if(!(self&1))
        "<%s>\n",self->class_name;
      else
        "???\n";
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
    ThingDel(block);
    return FROG_SMALL_NIL;
  }
  self=FrogUnSuper(self);
  block=FrogUnSuper(block);
  cnt=AsF64(self);
  while(--cnt>=0) {
    ret=FrogBlockValue(block);
    if(ThingIsError(ret))
      break;
    ThingDel(ret);
    ret=FROG_SMALL_NIL;
    if(*return_flag)
      break;
  }
  ThingDel(block);
  return ret;
}
AddMethod("CFrogNum","timesRepeat:",&FrogNumTimesRepeat);


CFrogThing *FrogWhileTrue(CFrogBlock *self,...) {
  CFrogBlock *pass=argv[0],*ret=FROG_SMALL_NIL;
  CFrogNum *cond;
  if(!ThingHasClass(self,"CFrogBlock")||!ThingHasClass(pass,"CFrogBlock")) {
    ThingDel(pass);
    return FROG_SMALL_NIL;
  }
  self=FrogUnSuper(self);
  cond=FrogUnSuper(cond);
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
	 ThingDel(cond);
         goto on_true;
       }
     } else {
       ThingDel(cond);
       break;
     }
     ThingDel(cond);
     break;
on_true:
     ret=FrogBlockValue(pass);
     if(ThingIsError(ret))
        break;
     if(*return_flag)
        break;
     ThingDel(ret);
     ret=FROG_SMALL_NIL;
  }
  ThingDel(pass);
  return ret;
}
AddMethod("CFrogBlock","whileTrue:",&FrogWhileTrue);


CFrogThing *FrogWhileFalse(CFrogBlock *self,...) {
  CFrogBlock *pass=argv[0];
  CFrogNum *cond,*ret=FROG_SMALL_NIL;
  if(!ThingHasClass(self,"CFrogBlock")||!ThingHasClass(pass,"CFrogBlock")) {
    ThingDel(pass);
    return FROG_SMALL_NIL;
  }
  self=FrogUnSuper(self);
  cond=FrogUnSuper(cond);
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
        ThingDel(cond);
        break;
      }
    } else {
//Not anumber
      ret=FROG_SMALL_NIL;
      ThingDel(cond);
      break;
    }
    ThingDel(cond);
    ret=FrogBlockValue(pass);
    if(ThingIsError(ret))
        break;
    if(*return_flag)
      break;
    ThingDel(ret);
    ret=FROG_SMALL_NIL;
  }
  ThingDel(pass);
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
  if(--thing->ref_cnt==0) {
  if(thing->ref_cnt<0) throw('asdas');
    if(thing->thing_flags&THINGF_FRAME_TYPE) {
      g=thing;
      if(g->type=='Repl')
        return;
      QueRem(thing);
      if(recurse) {
        idx=g->item_cnt;
        while(--idx>=0) {
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
      Free(thing);
      return;
    }
    QueRem(thing);
    if(cpair=FastLookupByStr(".dft",thing->class_name)) {
      if(cpair->destroy) {
        fun=HashFind(cpair->destroy,frog_mem_task->hash_table,HTT_FUN);
        if(fun) {
          destroy=fun->exe_addr;
	  (*destroy)(thing);
	}
      } else {
normal:
        if(recurse) {
	  cls=HashFind(thing->class_name,frog_mem_task->hash_table,HTT_CLASS);
	  MemSet(&dummy,0,sizeof CFrogThing);
	  while(cls) {
	    mlst=cls->member_lst_and_root;
	    while(mlst) {
	      if(mlst->member_class->ptr_stars_cnt==1) {
	        StrCpy(dummy.class_name,mlst->member_class[-1].str);
	        if(ThingHasClass(&dummy,"CFrogThing")) {
		  idx=mlst->dim.total_cnt;
		  f=thing(U8*)+mlst->offset;
		  while(--idx>=0)
		    ThingDel(f[idx]);
	        }
	      }
	        mlst=mlst->next;
	    }
	      cls=cls->base_class;
	  }
        }
        Free(thing);
      }
    } else
      goto normal;
  }
}

CFrogUndefined *FrogNil() {
  return FROG_SMALL_NIL;
}

U0 FrogGarbageCollectThing(CFrogThing *root,Bool debug=FALSE) {
  if(!root||root&1) return; //bit 0 is set for special "small" values
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
      FrogGarbageCollectThing(g->body[idx],debug); 
    }
    FrogGarbageCollectThing(root(CLocalsGeneric*)->parent,debug);
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
U0 FrogGarbageCollect(CFrogThing *root=FROG_SMALL_NIL) {
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
//
//$BK,1$THESE REMOVE SUB ITEMS FROM THE CFrogBlock "destroy" MEMBER,$BK,0$
//$BK,1$THE SUB ITEMS NEED TO  BE FREED FROM THE GC,$BK,0$
//
      if(ThingHasClass(cur,"CFrogArray"))
        cur(CFrogArray*)->destroy=NULL;
      if(ThingHasClass(cur,"CFrogBlock")) 
        cur(CFrogBlock*)->destroy=NULL;

      cur->ref_cnt=1;
      ThingDel(cur,FALSE);
    } else {
      cur->ref_cnt=cur->shadow_ref_cnt;
      LBtr(&cur->thing_flags,THINGf_GC_LOCK);
    }
  }
}



F64 AsF64(CFrogThing *t) {
  CFrogSmallFixedPoint mfp=t;
  F64 ret;
  if(mfp&0xffff==FROG_SMALL_NUM) {
     return (mfp>>16)/ToF64(I16_MAX);
  }
//Number-ish used for internal operations
  if(mfp&0xffff==FROG_SMALL_CHR) {
     return mfp>>32;
  }
  if(ThingHasClass(t,"CFrogNum")) { //Phat ass number
    return t(CFrogNum*)->num;
  }
  return 0;
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
  CFrogThing *t=FROG_SMALL_NIL;
  CHashClass *tmph;
  if(ThingHasClass(cls,"CFrogClass")) {
    tmph=HashFind(cls->name,frog_mem_task->hash_table,HTT_CLASS);
    while(tmph) {
      if(!StrCmp(tmph->str,"CFrogError")) {
	if(t=FramePtr(FROG_FP_ERROR)) {
	  ThingDel(t);
	  FramePtrDel(FROG_FP_ERROR);
        }
	FramePtrAdd(FROG_FP_ERROR,ConstructThing(cls->name));
        t=FROG_SMALL_ERROR;
	goto fin;
      }
      tmph=tmph->base_class;
    }
    t=ConstructThing(cls->name);
  }
fin:
  return t;
}
AddClassMethod("CFrogThing","basicNew",&FrogThingNew);

CFrogNum *FrogHasClass(CFrogClass *self,...) {
  CFrogClass *c=argv[0];
  CFrogNum *ret=FROG_SMALL_NIL;
  if(ThingHasClass(c,"CFrogClass")) {
    ret=FrogNumNew(ThingHasClass(self,c->name));
  }
  ThingDel(c);
  return ret;
}
AddMethod("CFrogThing","hasClass:",&FrogHasClass);


CFrogStr *FrogClassName(CFrogClass *cls,...) {
  return FrogStrNew(cls->name);
}
//This is a class method
AddClassMethod("CFrogThing","name",&FrogClassName);



CFrogThing *FrogSymbolValueGet(U8 *name) {
  return FrogIncRefCnt(FrogSymbol(name)->value);
}
U0 FrogSymbolValueSet(U8 *name,CFrogThing *v) {
  CFrogSymbol *sym=FrogSymbol(name);
  ThingDel(sym->value);
  sym->value=v;
}
CFrogSuper *FrogSuper(CFrogThing *from) {
  CFrogSuper *s=ConstructThing("CFrogSuper");
  s->from=FrogIncRefCnt(from);
  return s;
}
U0 FrogSuperDel(CFrogSuper *s) {
  ThingDel(s->from);
  Free(s);
}
CFrogThing *ToFrogNum(F64 n) {
  n*=I16_MAX;
  I64 ipart=ToI64(n);
  if(n-ipart>.5)
    return ((ipart+1)<<16)|FROG_SMALL_NUM;
  return (ipart<<16)|FROG_SMALL_NUM;
}
U8 *AsString(CFrogThing *t) {
  I64 idx;
  U8 *ret=NULL;
  CFrogThing *as_str;
  CI64Set *items;
  if(ThingHasClass(t,"CFrogBin")) {
    return MAllocIdent(t(CFrogBin*)->data);
  } else if(ThingHasClass(t,"CFrogStr")) {
      idx=0;
      items=t(CFrogStr*)->items;
      ret=CAlloc(items->cnt+1);
      for(idx=0;idx<items->cnt;idx++) {
        ret[idx]=AsChar(items->body[idx]);
      }
  } else {
    as_str=CallScript("printString",t);
    if(ThingHasClass(as_str,"CFrogStr")) {
      ret=AsString(as_str);
      ThingDel(as_str);
    } else
      ret=StrNew("");
  }
  return ret;
}

#include "../BlobFile.HC";
CFrogThing *FrogBlobFileOpen(CFrogBlobFile *f,...) {
  CFrogStr *name=argv[0];
  ThingDel(f->filename);
  f->filename=CallScript("copy",name);
  ThingDel(name);
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
  ThingDel(lump);
  Free(lump_name);
  Free(blob_name);
  return ret;
} 
AddMethod("CFrogBlobFile","readLump:",&FrogBlobFileReadLump);

CFrogThing *FrogTimeNow(CFrogThing *ul,...) {
  CFrogTime *t=ConstructThing("CFrogTime");
  t->ts=FrogNumNew(tS);
  return t;
}
AddClassMethod("CFrogTime","now",&FrogTimeNow);


U0 FrogBinDel(CFrogBin *bin) {
  Free(bin->data);
  Free(bin);
}
U0 FrogBlockDel(CFrogBlock *b) {
  ThingDel(b->frame);
}

Fs->user_data=0;
