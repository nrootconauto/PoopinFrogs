#ifndef SET_H
#define SET_H "gay frogballer"
class CI64Set {
  I64 cnt,cap;
  CTask *mem_task;
  I64 *body;
};
CTask  *set_mem_task=Fs;
U0 I64SetDel(CI64Set *s) {
  Free(s->body);
  Free(s);
}
CI64Set *I64SetNew(CTask *mem_task=set_mem_task) {
  CI64Set *s=CAlloc(sizeof(CI64Set),mem_task);
  s->mem_task=mem_task;
  s->cap=16;
  s->body=CAlloc(16*8,mem_task);
  return s;
}
U0 I64SetAdd(CI64Set *s,I64 v) {
  I64 *new;
  if(s->cnt+1>=s->cap) {
     new=CAlloc(s->cap*8+16*8,s->mem_task);
     s->cap+=16;
     MemCpy(new,s->body,s->cnt*8);
     Free(s->body);
     s->body=new;
  }
  s->body[s->cnt++]=v;
}
U0 I64SetRem(CI64Set *s,I64 v) {
  I64 idx,ptr=0,del=0;
  for(idx=0;idx!=s->cnt;idx++) {
    if(s->body[idx]!=v)
      s->body[ptr++]=s->body[idx];
    else
      del++;
  }
  s->cnt-=del;
}


Bool I64SetHas(CI64Set *s,I64 v) {
  I64 idx;
  for(idx=0;idx!=s->cnt;idx++) {
    if(s->body[idx]==v)
      return TRUE;
  }
  return FALSE;
}


class CU8Set {
  I64 cnt,cap;
  CTask *mem_task;
  U8 *body;
};

CU8Set *U8SetNew(CTask *mem_task=set_mem_task) {
  CU8Set *s=CAlloc(sizeof(CU8Set),mem_task);
  s->mem_task=mem_task;
  s->cap=64;
  s->body=CAlloc(64,mem_task);
  return s;
}

U0 U8SetAdd(CU8Set *s,I64 v) {
  U8 *new;
  if(s->cnt+1>=s->cap) {
     s->cap=s->cnt;
     new=CAlloc(s->cap+16,s->mem_task);
     s->cap+=16;
     MemCpy(new,s->body,s->cnt);
     Free(s->body);
     s->body=new;
  }
  s->body[s->cnt++]=v;
}

U0 U8SetAddBytes(CU8Set *s,U8 *body,I64 cnt) {
  U8 *new;
  if(s->cnt+cnt>=s->cap) {
     s->cap=2*s->cnt+cnt+16;
     new=CAlloc(s->cap,s->mem_task);
     MemCpy(new,s->body,s->cnt);
     Free(s->body);
     s->body=new;
  }
  MemCpy(s->body+s->cnt,body,cnt);
  s->cnt+=cnt;
}

U0 U8SetDel(CU8Set *s) {
  Free(s->body);
  Free(s);
}

#endif