class CFrogThread:CFrogThing {
   CFrogBlock *block;
   CTask *task;
}; 
U0 STThreadEnd() {
//We are killed IF thread->task is set,otherwise we exited normally
  CFrogThread *thread=FramePtr("ThreadSelf");
  if(thread->task) {
    FrogGarbageCollectUnlock;
  }
  Exit;
}
U0 STThreadRT(CFrogThread *thread) {
  Fs->user_data=0;
 FramePtrAdd("ThreadSelf",thread);
  thread->thing_flags|=THINGF_GC_ROOT;
  Fs->task_end_cb=&STThreadEnd;
  FrogGarbageCollectLock;
  FrogBlockValue(thread->block);
  thread->thing_flags&=~THINGF_GC_ROOT;
  thread->task=NULL;
  Exit;
}
CFrogThread *ThreadNew(CFrogThing *ul,...) {
  if(!ThingHasClass(argv[0],"CFrogBlock")) return FROG_SMALL_NIL;
  CFrogThread *t=ConstructThing("CFrogThread");
  t->block=argv[0];
  Spawn(&STThreadRT,t,,,Fs);
  return t;
}
AddClassMethod("CFrogThread","spawn:",&ThreadNew);
CFrogThread *ThreadKill(CFrogThread *t,...) {
  if(t->task) {
    Kill(t->task,FALSE);
  }
  return FROG_SMALL_NIL;
}
AddMethod("CFrogThread","kill",&ThreadKill);
CFrogThread *ThreadYield(CFrogThread *t,...) {
  FrogGarbageCollectUnlock;
  Sleep(3);
  FrogGarbageCollectLock;
  return FROG_SMALL_NIL;
}
AddClassMethod("CFrogThread","yield",&ThreadYield);
CFrogThread *ThreadSleep(CFrogThread *t,...) {
  FrogGarbageCollectUnlock;
  Sleep(1000*AsF64(argv[0]));
  FrogGarbageCollectLock;
  return FROG_SMALL_NIL;
}
AddClassMethod("CFrogThread","sleep:",&ThreadSleep);
U0 ThreadDel(CFrogThread *t) {
  if(t->task) Kill(t->task,FALSE);
  Free(t);
};