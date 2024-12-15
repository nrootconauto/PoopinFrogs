#define COMPILER_HH
#define COMPILER_HH "21"
#include "RunTime.HC";
#define BC_RUN_UNIVERSE 1 //arg1.i32[1] is arity,arg1.i32[0] is what
#define BC_VALUE 2
#define BC_STRING 3
#define BC_BLOCK 4 //(arg is num of 8-bytes)
#define BC_CASCADE_UNIVERSE 5 //Same as RUN_UNIVERSE,does not pop self
#define BC_VAR 6 //arg1 is var name
#define BC_ASSIGN_VAR 7 //arg1 is var name
#define BC_ASSIGN_MEMBER 8 //arg1 is var name,arg2 is member_name
#define BC_ASSIGN_SYMBOL 9 //arg1 is var name
#define BC_SELF 10
#define BC_RETURN 11
#define BC_NVAR 12 //arg1 is var name
#define BC_SYMBOL 13 //arg1 is Universe name
#define BC_ARRAY 14 //arg1 is length
#define BC_NVAR_NIL 15 //arg1 is universe name
#define BC_CLASS 16
#define BC_MEMBER 17
#define BC_DROP 18
#define BC_VAR_MEMBER 19 //2 at once u32[0] is var name,u32[1] is member
#define BC_SYMBOL_MEMBER 20 //Same as above
#define BC_JUMP_IF_NOT 21
#define BC_JUMP_IF 22
#define BC_JUMP 23
CFrogThing *InterpFrameGet(CFrogThing *self,CInterpFrame *f,I64 un) {
  I64 key=un<<16|FROG_SMALL_NUM;
enter:;
  I64 have=f->items->cnt,i=0;
  I64 *body=f->items->body;
  for(i=0;i<have;i+=2) {
    if(body[i]==key)
	return body[i+1];
  }
  if(f=f->next_frame)
    if(f!=FROG_SMALL_NIL)
      goto enter;
  if(have=GetClassMemberVal(self,UniverseNumberToName(un))) {
    return have;
  }
  return FROG_SMALL_NIL;
}

U0 InterpFrameSet(CFrogThing *self,CInterpFrame *f,I64 un,CFrogThing *t) {
  I64 key=un<<16|FROG_SMALL_NUM;
enter:;
  I64 have=f->items->cnt,i=0;
  I64 *body=f->items->body;
  U8 *str;
  for(i=0;i<have;i+=2) {
    if(body[i]==key) {
	body[i+1]=t;
	return;
     }
  }
  if(f=f->next_frame)
    if(f!=FROG_SMALL_NIL)
      goto enter;
  str=UniverseNumberToName(un);
  SetClassMemberVal(self,str,t);
}

CFrogThing *I64SetPop(CI64Set *s) {
  if(s->cnt) {
    return s->body[--s->cnt];
  }
Beep;
  throw('ass');
  return FROG_SMALL_NIL;
}

extern CFrogThing *RunByteCode(CFrogThing *self,CI64Set *bytecode_stack,CI64Set *stack,CInterpFrame *fr);


CFrogThing*BytecodeBlock(CFrogBlock *me,I64 *data,I64 len) {
  CI64Set *stack;
  CInterpFrame *frame=ConstructThing("CInterpFrame");
  frame->stack=FrogArrayNew;
  stack=frame->stack->items;
  frame->next_frame=me->frame;
  frame->thing_flags|=THINGF_GC_ROOT;
  I64 i;
  for(i=0;i!=me->arity;i++) {
    if(i<len)
      I64SetAdd(stack,data[i]);
    else
      I64SetAdd(stack,FROG_SMALL_NIL);
  }
  i=RunByteCode(me->self,me->bytecode,stack,frame);
  QueRem(frame->stack); //Remove from GC
  FrogArrayDel(frame->stack);
  frame->stack=FROG_SMALL_NIL;
  frame->thing_flags&=~THINGF_GC_ROOT;
  return i;
}

CFrogThing*BytecodeMethod(CFrogBlock *me,CI64Set *bc,I64 *data,I64 len) {
  CI64Set *stack;
  CInterpFrame *frame=ConstructThing("CInterpFrame");
  frame->stack=FrogArrayNew;
  stack=frame->stack->items;
  frame->thing_flags|=THINGF_GC_ROOT;
  I64 i;
  for(i=0;i!=len;i++) {
    I64SetAdd(stack,data[i]);
  }
  RunByteCode(me,bc,stack,frame);
  QueRem(frame->stack); //Remove from GC
  FrogArrayDel(frame->stack);
  frame->stack=FROG_SMALL_NIL;
  frame->thing_flags&=~THINGF_GC_ROOT;
  return frame->returned;
}



CFrogThing *FrogBlockNewBC(CI64Set *bc,CInterpFrame *frame,CFrogThing *self) {
  I64 i=0;
  CFrogBlock *me=FrogBlockNew(&BytecodeBlock,frame,self);
  me->bytecode=bc;
//Dumb hack compute arity
  while(i<bc->cnt) {
    if(bc->body[i]!=BC_NVAR)
      break;
    me->arity++;
    i+=2;
  }
  return me;
}
CFrogThing *RunByteCode(CFrogThing *self,CI64Set *bytecode_stack,CI64Set *stack,CInterpFrame *fr) {
  static F64 last_collect=tS;
  if(tS>last_collect+1./3.) { 
    FrogGarbageCollect(FROG_SMALL_NIL);
    last_collect=tS;
  }
  I64 ip=0,bc,arg1,i;
  I64 *code=bytecode_stack->body;
  I64 sp=stack->cnt,arity;
  I64 *body;
  CFrogSymbol *sym;
  U8 *str_name;
  CFrogThing *tt,*tt2;
  CInterpFrame *fr2;
  I64 fast_ready=0;
  F64 fast_stk[32];
  while(ip<bytecode_stack->cnt) {
    if(Fs->user_data) {
      if(Fs->user_data!=fr) {
        return FROG_SMALL_NIL;
      }
      Fs->user_data=NULL;
      return fr->returned;
    }
    bc=code[ip++];
    arg1=code[ip++];
    tt=FROG_SMALL_NIL;
    switch(bc) {
      case BC_JUMP:
	ip=arg1;
	break;
      case BC_JUMP_IF:
	if(AsF64(I64SetPop(stack)))
	  ip=arg1;
	break;
      case BC_JUMP_IF_NOT:
	if(!AsF64(I64SetPop(stack)))
	  ip=arg1;
	break;
      case BC_CASCADE_UNIVERSE:
      case BC_RUN_UNIVERSE:
        arity=arg1.i32[1];
        sp=stack->cnt;
        if(sp<arity+1) {
	  DbgPrint("sp,%d,%d\n",sp,arity+1);
Beep;
Beep;
	  throw('Fuck');
	  sp=0;
	  tt=FROG_SMALL_NIL;
        } else if(fast_ready>=arity+1) {
	  sp-=arity+1;
	  fast_ready-=arity+1;
	  switch(arg1.i32[0]) {
	      break;case #exe{ExeUniverse("+");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]+fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse("-");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]-fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse("*");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]*fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse("/");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]/fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse("and:");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]&&fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse("or:");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]||fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse(">=");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]>=fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse("<=");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]<=fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse("not");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]==0.;
	      break;case #exe{ExeUniverse(">");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]>fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse("<");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]<fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse("negated");}:
	      fast_stk[fast_ready]=-fast_stk[fast_ready];
	      break;case #exe{ExeUniverse("=");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]==fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse("~=");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]!=fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse("rem:");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]%fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse("raisedTo:");}:
	      fast_stk[fast_ready]=fast_stk[fast_ready]`fast_stk[fast_ready+1];
	      break;case #exe{ExeUniverse("floor");}:
	      fast_stk[fast_ready]=Floor(fast_stk[fast_ready]);
	      break;case #exe{ExeUniverse("ceil");}:
	      fast_stk[fast_ready]=Ceil(fast_stk[fast_ready]);
	      break;case #exe{ExeUniverse("log");}:
	      fast_stk[fast_ready]=Log10(fast_stk[fast_ready]);
	      break;case #exe{ExeUniverse("sqrt");}:
	      fast_stk[fast_ready]=Sqrt(fast_stk[fast_ready]);
	      break;case #exe{ExeUniverse("sin");}:
	      fast_stk[fast_ready]=Sin(fast_stk[fast_ready]);
	      break;case #exe{ExeUniverse("cos");}:
	      fast_stk[fast_ready]=Cos(fast_stk[fast_ready]);
	      break;case #exe{ExeUniverse("tan");}:
	      fast_stk[fast_ready]=Tan(fast_stk[fast_ready]);
	      break;case #exe{ExeUniverse("arcsin");}:
	      fast_stk[fast_ready]=ASin(fast_stk[fast_ready]);
	      break;case #exe{ExeUniverse("arctan");}:
	      fast_stk[fast_ready]=ATan(fast_stk[fast_ready]);
	      break;case #exe{ExeUniverse("arccos");}:
	      fast_stk[fast_ready]=ACos(fast_stk[fast_ready]);
	      break;default:
	      goto dft;
	  }
	  tt=FrogNumNew(fast_stk[fast_ready]);
        } else {
	  sp-=arity+1;
dft:
	  tt=CallScriptUniverse0(arg1.i32[0],stack->body[sp],&stack->body[sp+1],arity);
	  if(bc==BC_CASCADE_UNIVERSE) {
	    tt=stack->body[sp];
	  }
	  fast_ready=0;
        }
        stack->cnt=sp;
        I64SetAdd(stack,tt);
        break;
      case BC_DROP:
        I64SetPop(stack);
        break;
      case BC_NVAR:
        I64SetAdd(fr->items,arg1<<16|FROG_SMALL_NUM);
        I64SetAdd(fr->items,tt=I64SetPop(stack));
        break;
      case BC_NVAR_NIL:
//Check for existing var of same name
	body=fr->items->body;
	for(i=fr->items->cnt-2;i>=0;i-=2){
	  if(body[i]==arg1<<16|FROG_SMALL_NUM) {
	    body[i+1]=FrogNumNew(0.);
	    goto next;
	  }
        }
        I64SetAdd(fr->items,arg1<<16|FROG_SMALL_NUM);
        I64SetAdd(fr->items,FrogNumNew(0.));
        break;
      case BC_VALUE:
        I64SetAdd(stack,tt=arg1);
        break;
      case BC_SYMBOL_MEMBER:
        tt=GetClassMemberVal0(FrogSymbol0(arg1.u32[0])->value,arg1.u32[1]);
        I64SetAdd(stack,tt);
	break;
      case BC_VAR_MEMBER:
        tt=GetClassMemberVal0(InterpFrameGet(self,fr,arg1.u32[0]),arg1.u32[1]);
        I64SetAdd(stack,tt);
	break;
      case BC_SYMBOL:
        I64SetAdd(stack,tt=FrogSymbol0(arg1)->value);
        break;
      case BC_STRING:
        I64SetAdd(stack,tt=FrogStrNew(arg1));
        break;
      case BC_ASSIGN_SYMBOL:
        FrogSymbol0(arg1)->value=I64SetPop(stack);
        break;
      case BC_ASSIGN_VAR:
        InterpFrameSet(self,fr,arg1,I64SetPop(stack));
        break;
      case BC_MEMBER:
        tt=I64SetPop(stack);
        tt=GetClassMemberVal0(tt,arg1);
        I64SetAdd(stack,tt);
        break;
      case BC_ASSIGN_MEMBER:
        tt2=I64SetPop(stack);
        tt=I64SetPop(stack);
        SetClassMemberVal0(tt2,arg1,tt);
        tt=FROG_SMALL_NIL;
        break;
      case BC_SELF:
        I64SetAdd(stack,tt=self);
        break;
      case BC_VAR:
        I64SetAdd(stack,tt=InterpFrameGet(self,fr,arg1));
        break;
      case BC_ARRAY:
        tt=ConstructThing("CFrogArray");
        arity=arg1;
        if(arity<=stack->cnt) {
	  stack->cnt-=arity;
	  for(arg1=0;arg1!=arity;arg1++) {
	    I64SetAdd(tt(CFrogArray*)->items,stack->body[stack->cnt+arg1]);
	  }
        }
        I64SetAdd(stack,tt);
        break;
      case BC_BLOCK:
        if(arg1) {
	  tt=FrogBlockNewBC(arg1,fr,self);
        } else
	  tt=FROG_SMALL_NIL;
        I64SetAdd(stack,tt);
        break;
      case BC_RETURN:
        tt=I64SetPop(stack);
        fr2=fr;
        while(fr2) {
	  if(fr2==FROG_SMALL_NIL)
	    break;
	  fr2->returned=tt;
	  Fs->user_data=fr2;
	  fr2=fr2->next_frame;
        }
        if(Fs->user_data==fr)
	  Fs->user_data=NULL;
        return tt;
      default:
        DbgPrint("%d\n",bc);
Beep;
Beep;
Beep;
        throw('As');
    }
next:;
    if(tt&0xffFF==FROG_SMALL_NUM) {
      fast_stk[fast_ready++]=AsF64(tt);
    } else {
      fast_ready=0;
    }

  }
final:
  if(Fs->user_data==fr)
    Fs->user_data=NULL;
  if(stack->cnt)
    return I64SetPop(stack);
  return FROG_SMALL_NIL;
}
extern U0 CompileAST(CI64Set *to,CAST *ast,Bool cascade=FALSE);
U0 UnrollBlock(CI64Set *to,CAST *ast,I64 arity=0) {
  if(ast->type!=AST_BLOCK) {
    switch(arity) {
      case 0:
        I64SetAdd(to,BC_RUN_UNIVERSE);
        I64SetAdd(to,UniverseAddClass("value"));
        break;
      case :
        I64SetAdd(to,BC_RUN_UNIVERSE);
        I64SetAdd(to,UniverseAddClass("value:"));
    }
    return;
  }
  I64 depth=FramePtr("UnrollDepth")+1,idx;
  U8 buf[STR_LEN];
  FramePtrSet("UnrollDepth",depth);
  CAST *arg,*head;
  head=&ast->args;
  for(arg=head->last;arg!=head;arg=arg->last) {
    idx=NameToUniverseNumber(arg->name)|depth<<32;
    I64SetAdd(to,BC_NVAR_NIL); //BC_NVAR_NIL will automaticalyl reuse vars
    I64SetAdd(to,idx);
    StrPrint(buf,"VAR.%s",arg->name);
    FramePtrAdd(buf,idx);
    I64SetAdd(to,BC_ASSIGN_VAR);
    I64SetAdd(to,idx);
  } 
  head=&ast->body;
  for(arg=head->next;arg!=head;arg=arg->next) {
    CompileAST(to,arg);
    if(head->last!=arg) {
      if(arg->type!=AST_ASSIGN) {
        I64SetAdd(to,BC_DROP);
        I64SetAdd(to,0);
      }
    }
    if(head->last==arg) {
      if(arg->type==AST_ASSIGN) {
        I64SetAdd(to,BC_VALUE);
        I64SetAdd(to,FROG_SMALL_NIL);
      }
    }
  }
  head=&ast->args;
  for(arg=head->next;arg!=head;arg=arg->next) {
    StrPrint(buf,"VAR.%s",arg->name);
    FramePtrDel(buf);
  }
  FramePtrSet("UnrollDepth",depth-1);
}
U0 CompileAST(CI64Set *to,CAST *ast,Bool cascade=FALSE) {
  I64 argc,u;
  I64 bc,arg1,arg2,ptr,ptr2;
  Bool first;
  I64 old_sz;
  U8 buf[STR_LEN];
  CAST *arg;
  CI64Set *tmp;
  switch(ast->type) {
    case AST_RETURN:
      CompileAST(to,ast->args.next);
      I64SetAdd(to,BC_RETURN);
      I64SetAdd(to,0);
      break;
    case AST_STR:
      I64SetAdd(to,BC_STRING);
      I64SetAdd(to,StrNew(ast->str,frog_mem_task)); 
      break;
    case AST_CHR:
      I64SetAdd(to,BC_VALUE);
      I64SetAdd(to,FrogChrNew(ast->name[0]));
      break;
    case AST_ARRAY:
      arg=ast->body.next;
      while(arg!=&ast->body) {
        CompileAST(to,arg);
        arg=arg->next;
      }
      I64SetAdd(to,BC_ARRAY);
      I64SetAdd(to,QueCnt(&ast->body));
      break;
    case AST_CASCADE:
      first=TRUE;
      arg=ast->args.next;
      while(arg!=&ast->args) {
        CompileAST(to,arg,!first);
        arg=arg->next;
        first=FALSE;
      }
      return;
    case AST_NUM:
      I64SetAdd(to,BC_VALUE);
      I64SetAdd(to,FrogNumNew(ast->num));
      return;
    case AST_BLOCK:
      arg=ast->args.last;
      tmp=I64SetNew;
      while(arg!=&ast->args) {
        I64SetAdd(tmp,BC_NVAR);
	I64SetAdd(tmp,NameToUniverseNumber(arg->name));
        arg=arg->last;
      }
      arg=ast->body.next;
      while(arg!=&ast->body) {
        CompileAST(tmp,arg);
	if(arg->next!=&ast->body) {
	  if(arg->type!=AST_ASSIGN) {
	    I64SetAdd(tmp,BC_DROP);
	    I64SetAdd(tmp,0);
	  }
	}
        arg=arg->next;
      }

      bc=BC_BLOCK;
      arg1=tmp;
      I64SetAdd(to,bc);
      I64SetAdd(to,arg1);
      break;
    case AST_UNOP:
    case AST_BINOP:
    case AST_KEYWORD:
      if(!StrCmp(ast->name,"ifTrue:")) {
//Store a NIL in case we fail
	I64SetAdd(to,BC_VALUE);
	I64SetAdd(to,FROG_SMALL_NIL);
        arg=ast->args.next;
        CompileAST(to,arg);
	I64SetAdd(to,BC_JUMP_IF_NOT);
	ptr=to->cnt;
	I64SetAdd(to,0);
	I64SetAdd(to,BC_DROP); //Drop our nil
	I64SetAdd(to,0);
        arg=arg->next;
	UnrollBlock(to,arg);
	to->body[ptr]=to->cnt;
        break;
      }
      if(!StrCmp(ast->name,"ifFalse:")) {
//Store a NIL in case we fail
	I64SetAdd(to,BC_VALUE);
	I64SetAdd(to,FROG_SMALL_NIL);
        arg=ast->args.next;
        CompileAST(to,arg);
	I64SetAdd(to,BC_JUMP_IF);
	ptr=to->cnt;
	I64SetAdd(to,0);
	I64SetAdd(to,BC_DROP); //Drop our nil
	I64SetAdd(to,0);
        arg=arg->next;
	UnrollBlock(to,arg);
	to->body[ptr]=to->cnt;
        break;
      }
      if(!StrCmp(ast->name,"ifFalse:ifTrue:")) {
        arg=ast->args.next;
        CompileAST(to,arg);
	I64SetAdd(to,BC_JUMP_IF);
	ptr=to->cnt;
	I64SetAdd(to,0);
        arg=arg->next;
	UnrollBlock(to,arg);
	to->body[ptr]=to->cnt;
	I64SetAdd(to,BC_JUMP);
	ptr2=to->cnt;
	I64SetAdd(to,0);
	to->body[ptr]=to->cnt;
        arg=arg->next;
	UnrollBlock(to,arg);
	to->body[ptr2]=to->cnt;
        break;
      }
      if(!StrCmp(ast->name,"ifTrue:ifFalse:")) {
        arg=ast->args.next;
        CompileAST(to,arg);
	I64SetAdd(to,BC_JUMP_IF_NOT);
	ptr=to->cnt;
	I64SetAdd(to,0);
        arg=arg->next;
	UnrollBlock(to,arg);
	to->body[ptr]=to->cnt;
	I64SetAdd(to,BC_JUMP);
	ptr2=to->cnt;
	I64SetAdd(to,0);
	to->body[ptr]=to->cnt;
        arg=arg->next;
	UnrollBlock(to,arg);
	to->body[ptr2]=to->cnt;
        break;
      }
      if(!StrCmp(ast->name,"whileTrue:")) {
	ptr=to->cnt;
        arg=ast->args.next;
        UnrollBlock(to,arg);
	I64SetAdd(to,BC_JUMP_IF_NOT);
	ptr2=to->cnt;
	I64SetAdd(to,0);
	arg=arg->next;
        UnrollBlock(to,arg);
	I64SetAdd(to,BC_DROP);
	I64SetAdd(to,0);
	I64SetAdd(to,BC_JUMP);
	I64SetAdd(to,ptr);
	to->body[ptr2]=to->cnt;
	I64SetAdd(to,BC_VALUE);
	I64SetAdd(to,FROG_SMALL_NIL);
	break;
      }
      if(!StrCmp(ast->name,"whileFalse:")) {
	ptr=to->cnt;
        arg=ast->args.next;
        UnrollBlock(to,arg);
	I64SetAdd(to,BC_JUMP_IF);
	ptr2=to->cnt;
	I64SetAdd(to,0);
	arg=arg->next;
        UnrollBlock(to,arg);
	I64SetAdd(to,BC_DROP);
	I64SetAdd(to,0);
	I64SetAdd(to,BC_JUMP);
	I64SetAdd(to,ptr);
	to->body[ptr2]=to->cnt;
	I64SetAdd(to,BC_VALUE);
	I64SetAdd(to,FROG_SMALL_NIL);
	break;
      }
      argc=QueCnt(&ast->args);
      u=NameToUniverseNumber(ast->name);
      bc=BC_RUN_UNIVERSE;
      arg1.i32[1]=argc-1;
      arg1.u32[0]=u;
      arg=ast->args.next;
      while(--argc>=0) {
        CompileAST(to,arg);
        arg=arg->next;
      }
      I64SetAdd(to,bc);
      I64SetAdd(to,arg1);
      break;
    case AST_SYMBOL:
      bc=BC_SYMBOL;
      arg1=NameToUniverseNumber(ast->name);
      I64SetAdd(to,bc);
      I64SetAdd(to,arg1);
      break;
    case AST_VAR:
//See UnrollBlock
      StrPrint(buf,"VAR.%s",ast->name);
      if(!FramePtr(buf))
        arg1=NameToUniverseNumber(ast->name);
      else
        arg1=FramePtr(buf);
      if(HashFind(ast->name,frog_mem_task->hash_table,HTT_CLASS)) {
	bc=BC_VALUE;
	arg1=FrogClassNew(arg1);
      } else
        bc=BC_VAR;
      I64SetAdd(to,bc);
      I64SetAdd(to,arg1);
      break;
    case AST_MEMBER:
      arg=ast->args.last;
      if(arg->type==AST_VAR) {
        I64SetAdd(to,BC_VAR_MEMBER);
        I64SetAdd(to,NameToUniverseNumber(ast->name)<<32|NameToUniverseNumber(arg->name));
      } else if(arg->type==AST_SYMBOL) {
        I64SetAdd(to,BC_SYMBOL_MEMBER);
        I64SetAdd(to,NameToUniverseNumber(ast->name)<<32|NameToUniverseNumber(arg->name));
      } else {
        CompileAST(to,arg);
        I64SetAdd(to,BC_MEMBER);
        I64SetAdd(to,NameToUniverseNumber(ast->name));
      }
      break;
    case AST_SELF:
      I64SetAdd(to,BC_SELF);
      I64SetAdd(to,0);
      break;
    case AST_ASSIGN:
      arg=ast->args.last;
      CompileAST(to,arg);
      arg=ast->args.next;
      if(arg->type==AST_VAR) {
        bc=BC_ASSIGN_VAR;
        arg1=NameToUniverseNumber(arg->name);

        I64SetAdd(to,bc);
        I64SetAdd(to,arg1);
      } else if(arg->type==AST_SYMBOL) {
        bc=BC_ASSIGN_SYMBOL;
        arg1=NameToUniverseNumber(arg->name);
        I64SetAdd(to,bc);
        I64SetAdd(to,arg1);
      } else if(arg->type==AST_MEMBER) {
        arg1=NameToUniverseNumber(arg->name);
        arg=arg->args.next;
	CompileAST(to,arg);
        bc=BC_ASSIGN_MEMBER;
        I64SetAdd(to,bc);
        I64SetAdd(to,arg1);
      }
      break;
default:
"%d\n",ast->type;
DumpAst(ast);
throw('Unimp');
  }
}


U0 STRepl(U8 *dft="",Bool interactive=TRUE) {
  Bool br;
  U8 *str;
  CLexer *lex; //TODO feed into lexer
  CAST *ast,dummy;
  CDoc *doc;
  CDocEntry *replace;
  lex=LexerNew(dft);
  CI64Set *bc=I64SetNew;
  CI64Set *stk=I64SetNew;
  CInterpFrame *it=ConstructThing("CInterpFrame");
  FramePtrAdd("Escapes",TRUE);
  if(interactive)
    lex->flags|=LEXF_CMD_LINE|LEXF_WANTS_INPUT;
  while(TRUE) {
    bc->cnt=0;
    try {
      br=FALSE;
      ast=NULL;
      if(!Lex(lex)&&!interactive)
        br=TRUE;
      if(!br)
        ast=ParseAst(lex);
//Dont delete,the REPL will need to keep info on Blocks and stuff
    } catch
      PutExcept(TRUE);
    if(br) break;
    if(ast) {
      doc=DocNew;
      stk->cnt=0;
      CompileAST(bc,ast);
      RunByteCode(FROG_SMALL_NIL,bc,stk,it);
      ASTDel(ast);
      FrogGarbageCollect(FROG_SMALL_NIL);
    }
skip:;
  }
  FramePtrDel("Escapes");
}


U0 CompileToHolyC(U8 *src,U8 *class_name,U8 *src_path=NULL,Bool class_method=FALSE,Bool register_method=FALSE) {
  FramePtrAdd("MethodClass",class_name);
  FramePtrAdd("UnrollDepth",0);
  try {
    CDoc *dumb=DocNew;
    I64 idx;
    CI64Set *to=I64SetNew;
    CAST *var,*head;
    CLexer *lex=LexerNew(src,src_path);
    Lex(lex);
    CMethod *m=ParseMethod(lex,HashFind(class_name,frog_mem_task->hash_table,HTT_CLASS));
    LexerDel(lex);
    var=m->args.last;
    while(var!=&m->args) {
      idx=NameToUniverseNumber(var->name);
      I64SetAdd(to,BC_NVAR);
      I64SetAdd(to,idx);
      var=var->last;
    }
    var=m->temps.last;
    while(var!=&m->temps) {
      idx=NameToUniverseNumber(var->name);
      I64SetAdd(to,BC_NVAR_NIL);
      I64SetAdd(to,idx);
      var=var->last;
    }
    var=m->body.next;
    while(var!=&m->body) {
      CompileAST(to,var);
      var=var->next;
    }
    DocPrint(dumb,"CFrogThing *Dumb(CFrogThing *self,I64 *argv,I64 argc) {\n");
    DocPrint(dumb,"  return BytecodeMethod(self,%d,argv,argc);\n",to);
    DocPrint(dumb,"};\n");
    if(!class_method) {
      DocPrint(dumb,"AddMethod(\"%Q\",\"%Q\",&Dumb,FALSE);;",class_name,m->name);
    } else {
      DocPrint(dumb,"AddClassMethod(\"%Q\",\"%Q\",&Dumb,FALSE);;",class_name,m->name);
    }
    DocTop(dumb);
    ExeDoc(dumb);
    DocDel(dumb);
fin:
    FramePtrDel("MethodClass");
    FramePtrDel("UnrollDepth");
    MethodDel(m);
  } catch {
    FramePtrDel("UnrollDepth");
    FramePtrDel("MethodClass");
  }
}

F64 t=tS;
STRepl(
"  #Y _ [:f=CFrogBlock | [:x=CFrogBlock | x value: x] value: [:g=CFrogBlock| f value: [:x| (g value: g) value: x] ] ]."
"  #fib _ #Y value: [:f| [:i=CFrogNum | i <= 1 ifTrue: [i] ifFalse: [ (f value: i - 1) + (f value: i - 2)] ] ]."
"  (#fib value: 10 ) show .",
FALSE
);
#endif