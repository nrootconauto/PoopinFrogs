#include "Set";
class CUniverseInitPair {
  U8 *blob;
  U8 (*init)(U8*);
  U8 (*destroy)(U8*);
};
CTask *universe_task=Fs;
CI64Set *universe_values=I64SetNew; //I64
CI64Set *universe_init_pairs=I64SetNew; //I64
CI64Set *universe_methods=I64SetNew; //CI64Set(set of method indexes)
CI64Set *universe_class_methods=I64SetNew; //CI64Set(set of method indexes)
I64 universe_cnt=1;
CI64Set *universe_class_matrix=I64SetNew;
U0 I64SetSetMinSize(CI64Set *s,I64 sz) {
  if(s->cnt<sz) {
    I64 *old=s->body;
    s->body=CAlloc((sz+16)*8,universe_task);
    s->cap=sz+16;
    MemCpy(s->body,old,8*s->cnt);
    Free(old);
    s->cnt=sz;
  }
}
U0 I64SetInsAt(CI64Set *s,I64 idx,I64 v) {
  I64SetSetMinSize(s,idx+1);
  s->body[idx]=v;
}
U8 *I64SetGetAt(CI64Set *s,I64 idx) {
  if(s->cnt<=idx) return NULL;
  return s->body[idx];
}
I64 NameToUniverseNumber(U8 *name) {
  I64 r;
  U8 buf[STR_LEN];
  StrPrint(buf,"U.%s",name);
  if(r=FramePtr(buf,universe_task)) {
    return r;
  }
  r=universe_cnt++;
  FramePtrAdd(buf,r);
  I64SetInsAt(universe_values,r,NULL);
  return r;
}
I64 UniverseAddClass(U8 *name) {
  I64 idx=NameToUniverseNumber(name);
  if(!universe_values->body[idx]) {
    I64SetInsAt(universe_methods,idx,I64SetNew);
    I64SetInsAt(universe_class_methods,idx,I64SetNew);
    universe_values->body[idx]=StrNew(name);
  }
  return idx;
}
U0 UniverseAddMethod(U8 *name,U8 *cls,U8 *method_ptr) {
  I64 idx=NameToUniverseNumber(name);
//Will not add repeats
  I64 cls_idx=UniverseAddClass(cls);
  I64SetInsAt(universe_methods->body[cls_idx],idx,method_ptr);
}
U0 UniverseAddClassMethod(U8 *name,U8 *cls,U8 *method_ptr) {
  I64 idx=NameToUniverseNumber(name);
//Will not add repeats
  I64 cls_idx=UniverseAddClass(cls);
  I64SetInsAt(universe_class_methods->body[cls_idx],idx,method_ptr);
}
U8 *UniverseGetMethodForClassByIdx(I64 idx,I64 cls_idx) {
 I64 orig=cls_idx;
loop:;
  CI64Set *set=I64SetGetAt(universe_methods,cls_idx);
  CHashClass *cls=I64SetGetAt(universe_values,cls_idx);
  if(!cls) return NULL;
  if(!set) {return NULL;}
  U8 *ret=I64SetGetAt(set,idx);
  if(ret) {
    if(set=I64SetGetAt(universe_class_methods,orig))
      I64SetInsAt(set,idx,ret);
    return ret;
  }
  if(cls) {
    cls=HashFind(cls,universe_task->hash_table,HTT_CLASS);
    if(cls->base_class) {
      cls_idx=NameToUniverseNumber(cls->base_class->str);
      goto loop;
    }
  }
  return NULL;
}
U8 *UniverseGetClassMethodForClassByIdx(I64 idx,I64 cls_idx) {
  I64 orig=cls_idx;
loop:;
  CI64Set *set=I64SetGetAt(universe_class_methods,cls_idx);
  CHashClass *cls=I64SetGetAt(universe_values,cls_idx);
  if(!cls) return NULL;
  if(!set) return NULL;
  U8 *ret=I64SetGetAt(set,idx);
  if(ret) {
    if(set=I64SetGetAt(universe_class_methods,orig))
      I64SetInsAt(set,idx,ret);
    return ret;
  }
  if(cls) {
    if(cls=HashFind(cls,universe_task->hash_table,HTT_CLASS))
      if(cls->base_class) {
        cls_idx=NameToUniverseNumber(cls->base_class->str);
        goto loop;
      }
  }
  return NULL;
}
Bool UniverseIsSubClassOf(I64 a,I64 b) {
  CI64Set *vec=I64SetGetAt(universe_class_matrix,a);
  I64 answer;
//empty values are filled  with 0,so be sure to use -1 for failure,and 1 for pass
  if(vec) {
    answer=I64SetGetAt(vec,b);
    if(answer) {
      return answer==1;
    }
  }
  U8 *aa=I64SetGetAt(universe_values,a);
  U8 *bb=I64SetGetAt(universe_values,b);
  if(!aa||!bb) return FALSE;
  CFrogThing dummy;
  MemSet(&dummy,0,sizeof CFrogThing);
  StrCpy(dummy.class_name,aa);
  Bool has=ThingHasClass(&dummy,bb);
  if(!vec) 
    I64SetInsAt(universe_class_matrix,a,vec=I64SetNew);
  if(has)
    answer=1;
  else
    answer=-1;
  I64SetInsAt(vec,b,answer);
  return has;
}
U0 UniverseAddConstructorPair(U8 *name,U8 *blob,U8 *init,U8 *destroy) {
  I64 idx=NameToUniverseNumber(name);
  CUniverseInitPair *p=CAlloc(sizeof(CUniverseInitPair),universe_task);
  p->init=init;
  p->blob=blob;
  p->destroy=destroy;
  I64SetInsAt(universe_init_pairs,idx,p);
}
U8 *UniverseConstructThing(I64 idx) {
  CUniverseInitPair *p=I64SetGetAt(universe_init_pairs,idx);
  if(!p) return NULL;
  CFrogThing *ret=MAllocIdent(p->blob,universe_task);
  if(p->init) {(*p->init)(ret);}
  ret->id=idx;
  return ret;
}
U8 *UniverseConstructThingS(U8 *name) {
  I64 idx=NameToUniverseNumber(name);
  return UniverseConstructThing(idx);
}
U0 UniverseDestroyThing(CFrogThing *t) {
  CUniverseInitPair *p=I64SetGetAt(universe_init_pairs,t->id);
  if(!p) {Free(t);return NULL;}
  if(p->destroy) (*p->destroy)(t);
  else Free(t);
}
