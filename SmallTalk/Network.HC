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

CNetStream *NetStreamNewConnection(CFrogClass *c,...) {
  CNetStream *ret=FROG_SMALL_NIL;
  U8 *addr=AsString(argv[0]);
PrintI("addr",addr);
  if(addr) {
    ret=ConstructThing("CNetStream");
    ret->sock=create_connection(addr,AsF64(argv[1]));
    Free(addr);
  }
  return ret;
}
AddClassMethod("CNetStream","newConnectionTo:atPort:",&NetStreamNewConnection);
CNetStream *NetStreamNewServer(CFrogClass *c,...) {
  CNetStream *ret=FROG_SMALL_NIL;
  U8 *addr=AsString(argv[0]);
PrintI(addr,AsF64(argv[1]));
  if(addr) {
    ret=ConstructThing("CNetStream");
    ret->sock=create_server(addr,AsF64(argv[1]));
PrintI("server",ret->sock);
    Free(addr);
  }
  return ret;
}
AddClassMethod("CNetStream","newServerAt:atPort:",&NetStreamNewServer);
CNetStream *NetStreamSendString(CNetStream *ns,...) {
  U8 *s=AsString(argv[0]);
  sendString(ns->sock,s,0);
  Free(s);
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","sendString:",&NetStreamSendString);
CNetStream *NetStreamGetLine(CNetStream *ns,...) {
  U8 buf[4048];
PrintI("getline",0);
  if(0<recvLine(ns->sock,buf,4047,0)) {
    return FrogStrNew(buf);
  } else {
    CallScript("close",ns);
    return FROG_SMALL_NIL;
  }
}
AddMethod("CNetStream","getLine",&NetStreamGetLine);
CNetStream *NetStreamRecvBytes(CNetStream *ns,...) {
  CFrogStr *str=FROG_SMALL_NIL;
  CU8Set *bytes=U8SetNew(frog_mem_task);
  I64 want=AsF64(argv[0]),got;
  U8 buf[2048];
  for(;want>0;) {
    got=recv(ns->sock,buf,MinI64(2048,want),0);
    if(got<=0) {
      CallScript("close",ns);
      U8SetDel(bytes);
      break;
    }
    U8SetAddBytes(bytes,buf,got);
    want-=got;
  }
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
CNetStream *NetStreamSendBytes(CNetStream *ns,...) {
  CFrogStr *str=argv[0];
PrintI("send",str);
  if(ThingHasClass(str,"CFrogStr")) {
    return AsF64(send(ns->sock,str->items->body,str->items->cnt,0));
  }
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","sendBytes:",&NetStreamSendBytes);
CNetStream *NetStreamClose(CNetStream *ns,...) {
  if(!ns->closed) {
    ns->closed=TRUE;
    close(ns->sock);
  }
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","close",&NetStreamClose);

CNetStream *NetStreamAccept(CNetStream *ns,...) {
  U8 buf[4048];
PrintI("accept",ns->sock);
  I64 sock=accept(ns->sock,NULL,0);
  CNetStream *ret=FROG_SMALL_NIL;
  if(sock>0) {
    ret=ConstructThing("CNetStream");
    ret->sock=sock;
PrintI("accept2",sock);
  }
  return ret;
}
AddMethod("CNetStream","accept",&NetStreamAccept);


CNetStream *NetStreamReadU32(CNetStream *ns,...) {
  U8 buf[4048];
  CFrogThing *t;
  U32 num;
PrintI("recv",1);
  if(4==recv(ns->sock,&num,4,0)) {
PrintI("recv2",num);
    return FrogNumNew(num);
  }
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","getU32",&NetStreamReadU32);
CNetStream *NetStreamReadI32(CNetStream *ns,...) {
  U8 buf[4048];
  CFrogThing *t;
  I32 num;
PrintI("recv",1);
  if(4==recv(ns->sock,&num,4,0)) {
    PrintI("recv2",num);
    return FrogNumNew(num);
  }
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","getI32",&NetStreamReadI32);
CNetStream *NetStreamReadU8(CNetStream *ns,...) {
  U8 buf[4048];
  CFrogThing *t;
  U8 num;
  if(1==recv(ns->sock,&num,1,0)) {
    return FrogNumNew(num);
  }
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","getU8",&NetStreamReadU8);


CNetStream *NetStreamSendI32(CNetStream *ns,...) {
  U8 buf[4048];
  CFrogThing *t;
  U32 num=AsF64(argv[0]);
PrintI("send",num);
  send(ns->sock,&num,4,0);
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","sendI32:",&NetStreamSendI32);
CNetStream *NetStreamSendU8(CNetStream *ns,...) {
  U8 buf[4048];
  CFrogThing *t;
  U32 num=AsF64(argv[0]);
  send(ns->sock,&num,1,0);
  return FROG_SMALL_NIL;
}
AddMethod("CNetStream","sendU8:",&NetStreamSendU8);
