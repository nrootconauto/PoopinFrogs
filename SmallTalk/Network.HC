#include"../CrossNetShims/Aiwnios2";
#exe {Cd(__DIR__);};
class CNetStream:CFrogThing {
  I64 sock;
  U8 *destroy dft "NetStreamDel";
  Bool closed,pad[7];
};
U0 NetStreamDel(CNetStream *ns) {
  if(!ns->closed)
    close(ns->sock);
  Free(ns);
}

CNetStream *NetStreamNewConnection(CFrogClass *c,I64 *argv,I64 argc) {
  CNetStream *ret=FROG_SMALL_NIL;
  U8 *addr=AsString(argv[0]);
  if(addr) {
    ret=ConstructThing("CNetStream");
    ret->sock=create_connection(addr,AsF64(argv[1]));
    Free(addr);
  }
  return ret;
}
AddClassMethod("CNetStream","newConnectionTo:atPort:",&NetStreamNewConnection);
CNetStream *NetStreamNewServer(CFrogClass *c,I64 *argv,I64 argc) {
  CNetStream *ret=FROG_SMALL_NIL;
  U8 *addr=AsString(argv[0]);
  if(addr) {
    ret=ConstructThing("CNetStream");
    ret->sock=create_server(addr,AsF64(argv[1]));
    Free(addr);
  }
  return ret;
}
AddClassMethod("CNetStream","newServerAt:atPort:",&NetStreamNewServer);
CNetStream *NetStreamSendString(CNetStream *ns,I64 *argv,I64 argc) {
  U8 *s=AsString(argv[0]);
  sendString(ns->sock,s,0);
  Free(s);
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","sendString:",&NetStreamSendString);
CNetStream *NetStreamGetLine(CNetStream *ns,I64 *argv,I64 argc) {
  U8 buf[4048];
  FrogGarbageCollectUnlock;
  if(0<recvLine(ns->sock,buf,4047,0)) {
    FrogGarbageCollectLock;
    return FrogStrNew(buf);
  } else {
    FrogGarbageCollectLock;
    CallScript("close",ns);
    return FROG_SMALL_NIL;
  }
}
AddMethod("CNetStream","getLine",&NetStreamGetLine);
CNetStream *NetStreamRecvBytes(CNetStream *ns,I64 *argv,I64 argc) {
  CFrogStr *str=FROG_SMALL_NIL;
  CU8Set *bytes=U8SetNew(frog_mem_task);
  I64 want=AsF64(argv[0]),got;
  U8 buf[2048];
  FrogGarbageCollectUnlock;
  for(;want>0;) {
    got=recv(ns->sock,buf,MinI64(2048,want),0);
    if(got<=0) {
      FrogGarbageCollectLock;
      CallScript("close",ns);
      U8SetDel(bytes);
      break;
    }
    U8SetAddBytes(bytes,buf,got);
    want-=got;
  }
  FrogGarbageCollectLock;
//recv Sleeps which may lead to garbage collection
//Create the string after we sleep.
  if(want==0) {
    str=FrogStrNew("");
    U8SetDel(str->items);
    str->items=bytes;
  }
  return str; 
}
AddMethod("CNetStream","getBytes:",&NetStreamRecvBytes);
CNetStream *NetStreamSendBytes(CNetStream *ns,I64 *argv,I64 argc) {
  CFrogStr *str=argv[0];
  if(ThingHasClass(str,"CFrogStr")) {
    return AsF64(send(ns->sock,str->items->body,str->items->cnt,0));
  }
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","sendBytes:",&NetStreamSendBytes);
CNetStream *NetStreamClose(CNetStream *ns,I64 *argv,I64 argc) {
  if(!ns->closed) {
    ns->closed=TRUE;
    close(ns->sock);
  }
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","close",&NetStreamClose);

CNetStream *NetStreamAccept(CNetStream *ns,I64 *argv,I64 argc) {
  U8 buf[4048];
  FrogGarbageCollectUnlock;
  I64 sock=accept(ns->sock,NULL,0);
  FrogGarbageCollectLock;
  CNetStream *ret=FROG_SMALL_NIL;
  if(sock>0) {
    ret=ConstructThing("CNetStream");
    ret->sock=sock;
  } else
    CallScript("close",ns);
  return ret;
}
AddMethod("CNetStream","accept",&NetStreamAccept);


CNetStream *NetStreamReadU32(CNetStream *ns,I64 *argv,I64 argc) {
  U8 buf[4048];
  CFrogThing *t;
  U32 num;
  FrogGarbageCollectUnlock;
  if(4==recv(ns->sock,&num,4,0)) {
    FrogGarbageCollectLock;
    return FrogNumNew(num);
  }
  CallScript("close",ns);
  FrogGarbageCollectLock;
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","getU32",&NetStreamReadU32);
CNetStream *NetStreamReadI32(CNetStream *ns,I64 *argv,I64 argc) {
  U8 buf[4048];
  CFrogThing *t;
  I32 num;
  FrogGarbageCollectUnlock;
  if(4==recv(ns->sock,&num,4,0)) {
  FrogGarbageCollectLock;
    return FrogNumNew(num);
  }
  CallScript("close",ns);
  FrogGarbageCollectLock;
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","getI32",&NetStreamReadI32);
CNetStream *NetStreamReadU8(CNetStream *ns,I64 *argv,I64 argc) {
  U8 buf[4048];
  CFrogThing *t;
  U8 num;
  FrogGarbageCollectUnlock;
  if(1==recv(ns->sock,&num,1,0)) {
    FrogGarbageCollectLock;
    return FrogNumNew(num);
  }
  CallScript("close",ns);
  FrogGarbageCollectLock;
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","getU8",&NetStreamReadU8);


CNetStream *NetStreamSendI32(CNetStream *ns,I64 *argv,I64 argc) {
  U8 buf[4048];
  CFrogThing *t;
  U32 num=AsF64(argv[0]);
  send(ns->sock,&num,4,0);
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","sendI32:",&NetStreamSendI32);
CNetStream *NetStreamSendU8(CNetStream *ns,I64 *argv,I64 argc) {
  U8 buf[4048];
  CFrogThing *t;
  U32 num=AsF64(argv[0]);
  send(ns->sock,&num,1,0);
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","sendU8:",&NetStreamSendU8);
