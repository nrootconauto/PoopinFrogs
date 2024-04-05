#ifndef ST_COMPILER_HH
#define ST_COMPILER_HH 1
#include "RunTime.HC";
//Dont Free
U8 *StackFrame2Var(I64 stk) {
  switch(stk) {
#exe {
   I64 cnt=0x100;
   while(--cnt>=0) {
     StreamPrint("case %d: return \"stk[%d]\";\n",cnt,cnt);
   }
};;
  }
}
extern U0 CompileAST(CDoc *doc,CAST *ast,U8*,I64 stack_depth);
class CLocals {
//HTT_FRAME_PTR with offset
  CLocals *next;
  CHashTable *vars;
  U8 name[STR_LEN];
};
U0 LocalsDel(CLocals *l) {
  HashTableDel(l->vars);
  Free(l);
}

class CLocalsGeneric0:CFrogFrame {
  U64 _type;
  CLocalsGeneric0 *_next;
  CLocalsGeneric0 *_parent;
  U8 *_return_flag;
  I64 _item_cnt;
  CFrogThing *_body[0];
};


CLocalsGeneric *STNewBlockFrame(U8 *frame_title,CLocalsGeneric *parent) {
  CHashClass *as=HashFind(frame_title,frog_mem_task->hash_table,HTT_CLASS);
  CLocalsGeneric *fr2,*fr=MAlloc(as->size,frog_mem_task);
  MemSetI64(fr,FROG_SMALL_NIL,as->size/8);
  QueIns(fr,&allocs_head);
  fr2=Fs->user_data;
  fr->item_cnt=(as->size-sizeof(CLocalsGeneric))/8;
  fr->thing_flags=THINGF_FRAME_TYPE;
  fr->parent=parent;
  fr->type='Block';
  fr->next=Fs->user_data;
  fr->ref_cnt=1;
  Fs->user_data=fr;
  if(parent->type=='Block'||parent->type=='Method')
    FrogIncRefCnt(parent);
  fr->return_flag=parent->return_flag;
  return fr;
}

CLocalsGeneric *STAddMethodFrame(CMethod *method,U8 *frame_title,Bool *ret_flag,U8*class_name) {
  CHashClass *as=HashFind(frame_title,frog_mem_task->hash_table,HTT_CLASS);
  CHashClass *cls;
  CMemberLst *mlst,*mlst2;
  CLocalsGeneric *fr=MAlloc(as->size,frog_mem_task);
  MemSetI64(fr,FROG_SMALL_NIL,as->size/8);
  QueIns(fr,&allocs_head);
  fr->item_cnt=(as->size-sizeof(CLocalsGeneric))/8;
  fr->thing_flags=THINGF_FRAME_TYPE;
  fr->ref_cnt=1;
  fr->type='Method';
  fr->return_flag=ret_flag;
  fr->next=Fs->user_data;
  fr->parent=Fs->user_data;
  Fs->user_data=fr;
  return fr;
}


//Returns string of raw type to access,otherwise returns NULL
//DO NOT FREE
U8 *RawAccessType(U8 *cls,U8 *name) {
  CHashClass *c=HashFind(cls,frog_mem_task->hash_table,HTT_CLASS);
  CMemberLst *mlst=MemberFind(name,c);
  if(mlst) {
    c=mlst->member_class;
    if(!c->ptr_stars_cnt)
      if(IsSmalltalkMember(c)&&1==mlst->dim.total_cnt) {
        return cmp.internal_types[c->raw_type]->str;
      }
  }
  return NULL;
}


CLocals *GenerateLocalsFromMethod(CMethod *method,U8 *for_class) {
  CLocals *ret=CAlloc(sizeof CLocals);
  static I64 cnt=0;
  CDoc *dummy=DocNew;
  CHashGeneric *gen;
  CHashClass *cls=HashFind(for_class,frog_mem_task->hash_table,HTT_CLASS);
  CMemberLst *mlst,*mlst2;
  StrPrint(ret->name,"CMethodLocals@%d",cnt++);
  ret->vars=HashTableNew(0x10);
  CAST *name,*head;
  I64 idx,off=0;
  DocPrint(dummy,"class %s:CLocalsGeneric0 {\n",ret->name);
//Account for class members first,THEN account for method locals
  while(cls) {
    if(!StrCmp(cls->str,"CFrogThing"))
      break;
    for(mlst=cls->member_lst_and_root;mlst;mlst=mlst->next)
      if(IsSmalltalkMember(mlst->member_class)) {
        gen=CAlloc(sizeof CHashGeneric);
        gen->type=HTT_FRAME_PTR;
        gen->user_data0=-1; //Not defined(class members are referenced from self)
//If we are a "raw type"(I64/F64 etc),set user_data1 to mark it as such.
//This seperates it from "normal" vars
        if(RawAccessType(for_class,mlst->str)) {
	  gen->user_data1=TRUE;
	}
	gen->user_data2=TRUE; //Is a SELF member
        gen->str=StrNew(mlst->str);
        HashAdd(gen,ret->vars);
      }
    cls=cls->base_class;
  }   


  for(idx=0;idx!=2;idx++) {
    if(!idx)
      head=&method->temps;
    else
      head=&method->args;
    for(name=head->next;name!=head;name=name->next) {
      gen=CAlloc(sizeof CHashGeneric);
      gen->type=HTT_FRAME_PTR;
      gen->user_data0=off++;
      gen->str=StrNew(name->name);
      HashAdd(gen,ret->vars);
      DocPrint(dummy,"  CFrogThing *%s;\n",gen->str);
    }
  }
  DocPrint(dummy,"};\n");
  ExeDoc(dummy);
  DocDel(dummy);
  return ret;
}
CLocals *GenerateLocalsFromThunk(CAST *thunk) {
  CLocals *ret=CAlloc(sizeof CLocals);
  static I64 cnt=0;
  CDoc *dummy=DocNew;
  CHashGeneric *gen;
  StrPrint(ret->name,"CThunkLocals@%d",cnt++);
  ret->vars=HashTableNew(0x10);
  CAST *name,*head;
  I64 off=0;
  DocPrint(dummy,"class %s:CLocalsGeneric0 {\n",ret->name);
  head=&thunk->args;
  for(name=head->next;name!=head;name=name->next) {
    gen=CAlloc(sizeof CHashGeneric);
    gen->type=HTT_FRAME_PTR;
    gen->user_data0=off++;
    gen->str=StrNew(name->name);
    HashAdd(gen,ret->vars);
    DocPrint(dummy,"  CFrogThing *%s;\n",gen->str);
  }
  DocPrint(dummy,"};\n");
  ExeDoc(dummy);
  DocDel(dummy);
  return ret;
}
Bool STHasLocal(CLocals *who,U8 *name) {
  while(who&&!HashSingleTableFind(name,who->vars,HTT_FRAME_PTR)) {
    who=who->next;
  }
  return ToBool(who);
}
Bool STIsRawMember(CLocals *who,U8 *name) {
  CHashGeneric *g;
  while(who&&!(g=HashSingleTableFind(name,who->vars,HTT_FRAME_PTR))) {
    who=who->next;
  }
  if(g){
    return g->user_data1;
  }
  return FALSE;
}
Bool STIsSelfMember(CLocals *who,U8 *name) {
  CHashGeneric *g;
  while(who&&!(g=HashSingleTableFind(name,who->vars,HTT_FRAME_PTR))) {
    who=who->next;
  }
  if(g){
    return g->user_data2;
  }
  return FALSE;
}
//s is a CFrogThing **
CFrogThing **BungisReduce(CFrogThing *self,U64 *s) {
  if(*s&0xffFF==FROG_SMALL_MEMBER_PTR) {
    self=FrogUnSuper(self);
    while(Bt(&self->thing_flags,THINGf_GC_LOCK))
      Yield;
    return self(U8*)+*s>>32;
  }
  return s;
}
Bool STGetLocal(CDoc *doc,CLocals *who,U8 *name) {
  I64 depth=0;
  CHashGeneric *gen;
  DocPrint(doc,"parent_frame");
  while(who&&!(gen=HashSingleTableFind(name,who->vars,HTT_FRAME_PTR))) {
    DocPrint(doc,"->_parent");
    who=who->next;
  }
  if(!gen) {
"%s\n",name;
    throw('STVar');
  }
  DocPrint(doc,"->_body[%d]",gen->user_data0);
  return TRUE;
}
U8 *CompileThunk(CAST *block,CLocals *parent=NULL) {
  static I64 thunk_cnt=0;
  U8 *ret;
  I64 idx,thunk_idx=thunk_cnt++;
  CDoc *doc=DocNew;
  CLocals *locals=GenerateLocalsFromThunk(block);
  locals->next=parent;
  CAST *var,*head;
  DocPrint(doc,"CFrogThing *Thunk@@%d(CFrogThing *self,CLocalsGeneric0 *parent_frame,...) {\n",thunk_idx);
  DocPrint(doc,"  CFrogThing *stk[0x100],*retval,**tmp;\n");
  DocPrint(doc,"  Bool false=FALSE;\n");
  DocPrint(doc,"  Bool *return_flag=STNewBlockFrame(\"%Q\",parent_frame)->return_flag;\n",locals->name,block);
  DocPrint(doc,"  if(!return_flag) return_flag=&false;\n");
  DocPrint(doc,"  parent_frame=Fs->user_data;\n");
  DocPrint(doc,"  I64 unwind=0;\n");
  head=&block->args;
  idx=0;
  for(var=head->next;var!=head;var=var->next) {
    DocPrint(doc,"  tmp=BungisReduce(self,&");
    STGetLocal(doc,locals,var->name);
    DocPrint(doc,");\n");
    DocPrint(doc,"  ThingDel(*tmp);\n");
    DocPrint(doc,"  *tmp=argv[%d];\n",idx);
    idx++;
  }

  head=&block->body;
  for(var=head->next;var!=head;var=var->next) {
    CompileAST(doc,var,locals,0);
    if(var!=head->last) {
      switch(var(CAST*)->type) {
        case AST_KEYWORD:
        case AST_BINOP:
        case AST_UNOP:
        case AST_STR:
        case AST_ARRAY:
        case AST_CASCADE:
        case AST_SELF:
        case AST_SUPER:
	  DocPrint(doc,"ThingDel(stk[0]);\n"); //Cleanup
      }
    } else {
      DocPrint(doc,"retval=stk[0];unwind=0;\n");
    }
  }

  head=&block->args;
  idx=0;
  DocPrint(doc,"ret:\n");
  DocPrint(doc,"  while(--unwind>=0) ThingDel(stk[unwind]);");
  DocPrint(doc,"  STFrameDel;\n");
  DocPrint(doc,"  return retval;\n");
  DocPrint(doc,"};");
  ret=DocSave(doc);//Saves to string
  ExePutS(ret);
  Free(ret);
  DocDel(doc);
  return MStrPrint("Thunk@@%d",thunk_idx);
}


U0 CompileAST(CDoc *doc,CAST *ast,CLocals *locals,I64 stack_depth) {
  U8 dummy[STR_LEN];
  I64 cnt,idx;
  CAST *cur,*cur2;
  U8 *thunk_name;
  U8 *raw_class_name;
  CMemberLst *mlst;
  switch(ast->type) {
      break;case AST_UNOP:
      cnt=0;
pass:
//Skip past object we are calling to
      cur=ast->args.next->next;
      CompileAST(doc,ast->args.next,locals,stack_depth);
      for(idx=0;idx<cnt;idx++) {
        CompileAST(doc,cur,locals,stack_depth+1+idx);
        cur=cur->next;
      }
      DocPrint(doc,"  retval=CallScriptFast(\n");
      DocPrint(doc,"#exe{ExeKey2StringLiteral(\"%s\");},\n",ast->op_name);
      DocPrint(doc,"#exe{ExeKey2StringLiteral(\".%s\");},\n",ast->op_name);
      DocPrint(doc,"%s\n",StackFrame2Var(stack_depth));
      for(idx=0;idx<cnt;idx++) {
	DocPrint(doc,",");
	DocPrint(doc,"%s",StackFrame2Var(stack_depth+1+idx));
     }
      DocPrint(doc,");\n");
      DocPrint(doc,"  ThingDel(%s);\n",StackFrame2Var(stack_depth));
      DocPrint(doc,"  %s=retval;\n",StackFrame2Var(stack_depth));
      DocPrint(doc,"  if(*return_flag||ThingIsError(retval)) {unwind=%d;goto ret;} \n",stack_depth,StackFrame2Var(stack_depth));
      break;case AST_BINOP:
      cnt=1;
      goto pass;
      break;case AST_SYMBOL:
      DocPrint(doc,"  %s=FrogSymbolValueGet(\"%Q\");\n",StackFrame2Var(stack_depth),ast->name);
      break;case AST_KEYWORD:
      cnt=StrOcc(ast->op_name,':');
      goto pass;
      break;case AST_ASSIGN:
      CompileAST(doc,ast->args.last,locals,stack_depth);
      cur=ast->args.next;
      if(cur->type==AST_SYMBOL) {
        DocPrint(doc,"\n  FrogSymbolValueSet(\"%Q\",%s);\n",cur->name,StackFrame2Var(stack_depth));
      } else if(cur->type==AST_VAR) {      
        if(STIsSelfMember(locals,cur->name)) {
	  mlst=MemberFind(cur->name,HashFind(FramePtr("MethodClass"),frog_mem_task->hash_table,HTT_CLASS));
	  DocPrint(doc,"  tmp=ToI64(FrogUnSuper(self))+%d;\n",mlst->offset);
	  if(STIsRawMember(locals,cur->name))
	    goto assign_raw;
	  goto assign_st;
	} else if(!STIsRawMember(locals,cur->name)) {
	  DocPrint(doc,"  tmp=BungisReduce(self,&");
	  STGetLocal(doc,locals,cur->name);
	  DocPrint(doc,");\n");
assign_st:
	  DocPrint(doc,"  ThingDel(*tmp);\n");
	  DocPrint(doc,"\n*tmp=%s;\n",StackFrame2Var(stack_depth));
        } else {
	  DocPrint(doc,"  tmp=BungisReduce(self,&");
	  STGetLocal(doc,locals,cur->name);
	  DocPrint(doc,");\n");
assign_raw:
	  raw_class_name=RawAccessType(FramePtr("MethodClass"),cur->name);
	  DocPrint(doc,"tmp(%s*)[0]=AsF64(%s);\n",raw_class_name,StackFrame2Var(stack_depth));
        }
      }else
        throw('Compile');
      DocPrint(doc,"  stk[0]=retval=FROG_SMALL_NIL;\n");
      break;case AST_STR:
      DocPrint(doc,"  %s=FrogStrNew(\"%Q\");\n",StackFrame2Var(stack_depth),ast->str);
      break;case AST_VAR:
      if(STHasLocal(locals,ast->name)) {
        if(STIsSelfMember(locals,ast->name)) {
	  mlst=MemberFind(ast->name,HashFind(FramePtr("MethodClass"),frog_mem_task->hash_table,HTT_CLASS));
	  DocPrint(doc,"  tmp=ToI64(FrogUnSuper(self))+%d;\n",mlst->offset);
	  if(STIsRawMember(locals,ast->name))
	    goto read_raw;
	  DocPrint(doc,"  %s=FrogIncRefCnt(*tmp);\n",StackFrame2Var(stack_depth));
	} else if(!STIsRawMember(locals,ast->name)) {
	  DocPrint(doc,"  %s=FrogIncRefCnt(*BungisReduce(self,&",StackFrame2Var(stack_depth));
	  STGetLocal(doc,locals,ast->name);
	  DocPrint(doc,"));\n");
        } else {
	  DocPrint(doc,"  tmp=BungisReduce(self,&");
	  STGetLocal(doc,locals,ast->name);
	  DocPrint(doc,");\n");
read_raw:
	  raw_class_name=RawAccessType(FramePtr("MethodClass"),ast->name);
	  DocPrint(doc,"%s=FrogNumNew(tmp(%s*)[0]);\n",StackFrame2Var(stack_depth),raw_class_name);
        }
      } else 
        DocPrint(doc,"  %s=STGetVar(self,\"%Q\");\n",StackFrame2Var(stack_depth),ast->name);
      break;case AST_ARRAY:
      DocPrint(doc,"  %s=FrogArrayNew;\n",StackFrame2Var(stack_depth));
      stack_depth++;
      for(cur=ast->body.next;cur!=&ast->body;cur=cur->next) {
        CompileAST(doc,cur,locals,stack_depth);
        DocPrint(doc,"  I64SetAdd(%s(CFrogArray*)->items,%s);\n",StackFrame2Var(stack_depth-1),StackFrame2Var(stack_depth));
      }
      stack_depth--;
      break;case AST_CASCADE:
      FramePtrAdd("?CascadeDepth",stack_depth);
      cur=ast->args.next;
      CompileAST(doc,cur,locals,stack_depth);
      stack_depth++;
      for(cur=ast->args.next->next;cur!=&ast->args;cur=cur->next) {
        CompileAST(doc,cur,locals,stack_depth);
      }
      stack_depth--;
      FramePtrDel("?CascadeDepth");
      DocPrint(doc,"  retval=%s;\n",StackFrame2Var(stack_depth));
      DocPrint(doc,"  if(*return_flag) {unwind=%d;goto ret;} \n",stack_depth,StackFrame2Var(stack_depth));
      break;case AST_BLOCK:
      thunk_name=CompileThunk(ast,locals);
      DocPrint(doc,"  %s=FrogBlockNew(&%s,parent_frame,self);\n",StackFrame2Var(stack_depth),thunk_name);
      Free(thunk_name);
      break;case AST_CHR:
      DocPrint(doc,"  %s=FrogChrNew(%d);\n",StackFrame2Var(stack_depth),ast->name[0](U64));
      break;case AST_CASCADE_HEAD:
      DocPrint(doc,"  %s=FrogIncRefCnt(%s)\n;",StackFrame2Var(stack_depth),StackFrame2Var(FramePtr("?CascadeDepth"))); 
      break;case AST_SUPER:
      DocPrint(doc,"  %s=FrogSuper(self);\n",StackFrame2Var(stack_depth),stack_depth);
      break;case AST_SELF:
      DocPrint(doc,"  %s=FrogIncRefCnt(self);\n",StackFrame2Var(stack_depth)); 
      break;case AST_NUM:
      DocPrint(doc,"  %s=FrogNumNew(%n);\n",StackFrame2Var(stack_depth),ast->num); 
      break;case AST_RETURN:
      CompileAST(doc,ast->args.next,locals,stack_depth);
      DocPrint(doc,"  return_flag[0]=TRUE;\n");
      DocPrint(doc,"  retval=%s;\n  unwind=%d;\n  goto ret;\n",StackFrame2Var(stack_depth),stack_depth);
      break; 
    default:
      throw('fuck');
  }
}
U0 CompileToHolyC(U8 *src,U8 *class_name,U8 *src_path=NULL,Bool class_method=FALSE) {
  Bool old=Option(OPTf_WARN_UNUSED_VAR,FALSE);
  CDoc *doc=DocNew;
  static I64 fun_num=0;
  U8 *ret,*fun_name;
  I64 idx;
  CAST *var,*head;
  CLexer *lex=LexerNew(src,src_path);
  Lex(lex);
  CMethod *m=ParseMethod(lex,HashFind(class_name,frog_mem_task->hash_table,HTT_CLASS));
  CLocals *locals=GenerateLocalsFromMethod(m,class_name);
  LexerDel(lex);
//MUST SET THIS
  FramePtrAdd("MethodClass",class_name);
  fun_name=MStrPrint("%s@%d",class_name,fun_num++);
  DocPrint(doc,"CFrogThing *%s(CFrogThing *self,...) {\n",fun_name);
  DocPrint(doc,"  CFrogThing *stk[0x100],*retval,**tmp;\n");
  DocPrint(doc,"  Bool st_return=FALSE;\n");
  DocPrint(doc,"  Bool *return_flag=STAddMethodFrame(%d,\"%Q\",&st_return,\"%Q\")->return_flag;\n",m,locals->name,class_name);
  DocPrint(doc,"  CLocalsGeneric0 *parent_frame=Fs->user_data;\n");
  DocPrint(doc,"  I64 unwind=0;\n");
  head=&m->args;
  idx=0;
  for(var=head->next;var!=head;var=var->next) {
    DocPrint(doc,"  tmp=BungisReduce(self,&");
    STGetLocal(doc,locals,var->name);
    DocPrint(doc,");\n");
    DocPrint(doc,"  ThingDel(*tmp);\n");
    DocPrint(doc,"  *tmp=argv[%d];\n",idx);
    idx++;
  }
  head=&m->body;
  for(var=head->next;var!=head;var=var->next) {
    CompileAST(doc,var,locals,0);
    switch(var(CAST*)->type) {
      case AST_KEYWORD:
      case AST_BINOP:
      case AST_UNOP:
      case AST_STR:
      case AST_ARRAY:
      case AST_CASCADE:
      case AST_SELF:
      case AST_SUPER:
      DocPrint(doc,"ThingDel(stk[0]);\n"); //Cleanup
    }
  }

  head=&m->args;
  idx=0;
  DocPrint(doc,"ret:\n");
  DocPrint(doc,"  while(--unwind>=0) ThingDel(stk[unwind]);");
  DocPrint(doc,"  STFrameDel;\n");
  DocPrint(doc,"  return retval;\n");
  DocPrint(doc,"};\n");
  if(!class_method) {
    DocPrint(doc,"AddMethod(\"%Q\",\"%Q\",&%s);",class_name,m->name,fun_name);
  } else {
    DocPrint(doc,"AddClassMethod(\"%Q\",\"%Q\",&%s);",class_name,m->name,fun_name);
  }
  ret=DocSave(doc);
  ExePutS(ret);
  DocDel(doc);
  Free(fun_name);
  Free(ret);
  LocalsDel(locals);
  Option(OPTf_WARN_UNUSED_VAR,old);
//DONE WITH IT
  FramePtrDel("MethodClass");
}

U0 STRepl(U8 *dft="",Bool interactive=TRUE) {
  Bool br;
  U8 *str;
  CLexer *lex; //TODO feed into lexer
  CAST *ast,dummy;
  CDoc *doc;
  lex=LexerNew(dft);
  if(interactive)
    lex->flags|=LEXF_CMD_LINE|LEXF_WANTS_INPUT;
  while(TRUE) {
    try {
      br=FALSE;
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
      DocPrint(doc,"CFrogThing *REPLFun(CFrogThing *self) {\n");
      DocPrint(doc,"  CFrogThing *stk[0x100],*retval;\n");
      DocPrint(doc,"  static Bool st_return=FALSE;\n");
      DocPrint(doc,"  Bool *return_flag=STNewReplFrame(&st_return)->return_flag;\n");
      DocPrint(doc,"  CLocalsGeneric0 *parent_frame=Fs->user_data;\n");
      DocPrint(doc,"  I64 unwind=0;\n");
      dummy.type=AST_RETURN;
      QueInit(&dummy.args);
      QueIns(ast,dummy.args);
      CompileAST(doc,&dummy,NULL,0);
      DocPrint(doc,"ret:\n");
//
// Dumb hack,blocks have a reference to the retunr_flag,so reset it.
//
      DocPrint(doc,"  *return_flag=0;\n");
      DocPrint(doc,"  while(--unwind>=0) ThingDel(stk[unwind]);");
      DocPrint(doc,"  STFrameDel;\n");
      DocPrint(doc,"  return retval;\n");
      DocPrint(doc,"}REPLFun(FrogNil);\n");
      str=DocSave(doc);
      ExePutS2(str);
      Free(str);
      DocDel(doc);
      FrogGarbageCollect(FROG_SMALL_NIL);
    }
skip:;
  }
}
U0 STRunStmt(U8 *str) {
  STRepl(str,FALSE);
}
#include "Studio.HC";;
STRunStmt(
"  #Y _ [:f| [:x| x value: x] value: [:g| f value: [:x| (g value: g) value: x] ] ]."
"  #fib _ #Y value: [:f| [:i| i <= 1 ifTrue: [i] ifFalse: [(f value: i - 1) + (f value: i - 2)] ] ]."
" (#fib value: 10 ) show ."
);
#endif
#endif