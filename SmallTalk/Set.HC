#ifndef SET_H
#define SET_H "gay frogballer"
class CI64Set {
  I64 cnt,cap;
  CTask *mem_task;
  I64 *body;
};
U0 I64SetDel(CI64Set *s) {
  Free(s->body);
  Free(s);
}
CI64Set *I64SetNew(CTask *mem_task=NULL) {
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
#endif