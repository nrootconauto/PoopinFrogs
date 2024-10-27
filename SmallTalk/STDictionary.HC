U0 FrogDictDel(CFrogDictionary *d) {
  HashTableDel(d->t);
  Free(d);
}

U0 FrogDictInit(CFrogDictionary *d) {
  d->t=HashTableNew(0x20,frog_mem_task);
  d->all=FrogArrayNew;
}
CFrogThing *FrogDictAt(CFrogDictionary *d,...) {
  U8 *got=AsString(argv[0]);
  CHashGeneric *gen=NULL;
  if(got) {
    gen=HashFind(got,d->t,HTT_FRAME_PTR);
  }
  Free(got);
  if(!gen) return FROG_SMALL_NIL;
  return gen->user_data1;
}
AddMethod("CFrogDictionary","at:",&FrogDictAt);
CFrogThing *FrogDictAtPut(CFrogDictionary *d,...) {
  U8 *got=AsString(argv[0]);
  CHashGeneric *gen=NULL;
  if(got) {
    if(gen=HashFind(got,d->t,HTT_FRAME_PTR)) 
      HashRemDel(gen,d->t);
    gen=CAlloc(sizeof(CHashGeneric),frog_mem_task);
    gen->str=StrNew(got,frog_mem_task);
    gen->type=HTT_FRAME_PTR;
    gen->user_data1=argv[1];
    HashAdd(gen,d->t);
//Important,keep in garbage collector
    I64SetAdd(d->all->items,argv[1]);
  }
  Free(got);
  if(!gen) return FROG_SMALL_NIL;
  return gen->user_data1;
}
AddMethod("CFrogDictionary","at:put:",&FrogDictAtPut);
CFrogThing *FrogDictDoKeys(CFrogDictionary *d,...) {
  I64 idx,mask=d->t->mask;
  CHashGeneric *gen;
  for(idx=0;idx<=mask;idx++) {
    gen=d->t->body[idx];
    while(gen) {
      FrogBlockValue(argv[0],FrogStrNew(gen->str));
      gen=gen->next;
    }
  }
  return FROG_SMALL_NIL;
}
AddMethod("CFrogDictionary","doKeys:",&FrogDictDoKeys);