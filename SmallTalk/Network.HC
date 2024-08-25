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
  if(addr) {
    ret=ConstructThing("CNetStream");
    ret->sock=create_server(addr,AsF64(argv[1]));
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
  if(0<recvLine(ns->sock,buf,4047,0)) {
    return FrogStrNew(buf);
  } else
    return FROG_SMALL_NIL;
}
AddMethod("CNetStream","getLine",&NetStreamGetLine);
CNetStream *NetStreamRecvBytes(CNetStream *ns,...) {
  CFrogStr *str=ConstructThing("CFrogStr");
  I64 want=AsF64(argv[0]),got;
  U8 buf[2048];
  for(;want>0;) {
    got=recv(ns->sock,buf,MinI64(2048,want),0);
    if(got<=0);
      return FROG_SMALL_NIL;
    U8SetAddBytes(str->items,buf,got);
    want-=got;
  }
  return str; 
}
AddMethod("CNetStream","getBytes:",&NetStreamGetLine);
CNetStream *NetStreamSendBytes(CNetStream *ns,...) {
  CFrogStr *str=argv[0];
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
  I64 sock=bind(ns->sock,NULL,0);
  CNetStream *ret=FROG_SMALL_NIL;
  if(sock) {
    ret=ConstructThing("CNetStream");
    ret->sock=sock;
  }
  return ret;
}
AddMethod("CNetStream","accept",&NetStreamAccept);