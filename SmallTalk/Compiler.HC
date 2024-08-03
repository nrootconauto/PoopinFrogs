# ifndef ST_COMPILER_HH
#define ST_COMPILER_HH 1
#include "RunTime.HC";
#define DEBUG 1
CFrogThing *Useless(CFrogThing *, ...) {
  return FROG_SMALL_NIL;
}
U0 GenerateUselessMethod(U8 *class_name,U8 *method_name,U8 *return_class)  {
  U8 *canon=MStrPrint("METHOD_%s.%s",class_name,method_name);
  U8 *rt=MStrPrint("RET_TYPE_%s.%s",class_name,method_name);
  if(return_class)
    FramePtrAdd(rt,StrNew(return_class));
  if(!FramePtr(canon)) {
    FramePtrAdd(canon,&Useless);
  }
  Free(canon);
  Free(rt);
}
//Dont Free
U8 *MethodReturnClass(U8 *class_name,U8 *method_name) {
  U8 *rt=MStrPrint("RET_TYPE_%s.%s",class_name,method_name);
  U8 *r=FramePtr(rt);
  Free(rt);  
  return r;
}
//Dont Free
U8 *StackFrame2Var(I64 stk) {
  I64 old=FramePtr("ST@@stk_depth");
  if(stk+1>old)
    FramePtrSet("ST@@stk_depth",stk+1);
  switch(stk) {
   case 0:
     return "stk0";
   case 1:
     return "stk1";
   case 2:
     return "stk2";
   case 3:
     return "stk3";
   case 4:
     return "stk4";
   case 5:
     return "stk5";
#exe {
   I64 cnt=0x100-6;
   while(--cnt>=0) {
     StreamPrint("case %d:return \"stk[%d]\";\n",cnt+6,cnt);
   }
};;
  }
}
extern U0 CompileAST(CDoc *doc,CAST *ast,U8*,I64 stack_depth,I64 jump_to=INVALID_PTR,Bool allow_f64=FALSE);


class CLocals {
//HTT_FRAME_PTR with offset
  CLocals *next;
  CHashTable *vars;
  I64 raw_mask,cnt;
  U8 name[STR_LEN];
};
U0 LocalsDel(CLocals *l) {
  HashTableDel(l->vars);
  Free(l);
}

class CLocalsGeneric0:CFrogFrame {
  U64 _type,_raw_mask;//raw_mask means bit is set if is a raw(F64) type in body[bit]
  CLocalsGeneric0 *_next;
  CLocalsGeneric0 *_parent;
  U8 *_return_flag;
  I32 _item_cnt,_ret_flag;
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
  if(parent->type=='Block'||parent->type=='Method') {
    FrogIncRefCnt(parent);
  }
  fr->return_flag=parent->return_flag;
  return fr;
}
U0 MakeAnonBlockFrame(CLocalsGeneric *fr,I64 sz,CLocalsGeneric *parent, U64 type='Block') {
  fr->item_cnt=sz;
  fr->thing_flags=THINGF_FRAME_TYPE;
  fr->parent=parent;
  fr->type=type;
  fr->next=Fs->user_data;
  fr->ref_cnt=1;
  Fs->user_data=fr;
  if(parent) fr->return_flag=parent->return_flag;
  MemSetI64(fr->body,FROG_SMALL_NIL,sz);
}
U0 STSetReturnFlags(I64 *who) {
  CLocalsGeneric *g=Fs->user_data;
  while(g) {
    g->return_flag[0]=1;
    if(g->return_flag==who&&g->type=='Method')
      break;
    g=g->next;
  }
}

CLocalsGeneric *STAddMethodFrame(CMethod *method,U8 *frame_title,U8*class_name) {
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
  fr->ret_flag=0;
  fr->return_flag=&fr->ret_flag;
  fr->next=Fs->user_data;
  fr->parent=Fs->user_data;
  Fs->user_data=fr;
  return fr;
}


//Returns string of raw type to access,otherwise returns NULL
//DO NOT FREE
U8 *RawAccessType(U8 *cls,U8 *name) {
  CHashClass *c=HashFind(cls,frog_mem_task->hash_table,HTT_CLASS);
  if(!c) return NULL;
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
class CHashGeneric3:CHashGeneric {
  I64 user_data3;
//Think Escape-Analysis
  I64 is_escaped;
};
U8 *VarClassName(CLocals *l,U8 *var) {
  if(!l) return FALSE;
  CHashGeneric3 *g;
  while(l&&!(g=HashSingleTableFind(var,l->vars,HTT_FRAME_PTR))) {
    l=l->next;
  }
  if(g)
    if(g->user_data3) {
      return g->user_data3;
    }
  return NULL;
}
//Returns classname that has the method or NULL.
U8 *ClassHasMethod(U8 *cn,U8 *method) {
  U8 *canon;
  if(cn) {
    CHashClass *cls=HashFind(cn,Fs->hash_table,HTT_CLASS);
    while(cls) {
      canon=MStrPrint("METHOD_%s.%s",cls->str,method);
      if(FramePtr(canon)) {
        Free(canon);
        return cls->str;
      }
      Free(canon);
      cls=cls->base_class;
    }
  }
  return NULL;

}
//Returns classname that has the method or NULL.
U8 *VarHasMethod(CLocals *l,U8 *var,U8 *method) {
  U8 *cn=VarClassName(l,var);
  return ClassHasMethod(cn,method);
}
U0 GenerateMethodCall(CDoc *doc,U8 *class_name,U8 *method_name,Bool check=TRUE) {
  CHashGeneric *gen;
//See AddMethod
  U8 *canon=MStrPrint("METHOD_%s.%s",class_name,method_name),*rc;
  if(!FramePtr(canon)) {
    FramePtrAdd(canon,&Useless);
  }
  gen=HashFind(canon,Fs->hash_table,HTT_FRAME_PTR);
  if(!StrCmp("CFrogNum",class_name)||!check) {
//Checking numbers will be too tiresome
    if(gen->user_data0!=&Useless)
      DocPrint(doc,"CallPtr(%d,NULL,",gen->user_data0,class_name);
    else
      DocPrint(doc,"CallPtr(%d(I64**)[0],NULL,",&gen->user_data0,class_name);
  } else {
    if(gen->user_data0!=&Useless)
      DocPrint(doc,"CallPtr2(%d,%d,",gen->user_data0,UniverseAddClass(class_name));
    else
      DocPrint(doc,"CallPtr2(%d(I64**)[0],%d,",&gen->user_data0,UniverseAddClass(class_name));
  }
  Free(canon);
}
CLocals *GenerateLocalsFromMethod(CMethod *method,U8 *for_class) {
  CLocals *ret=CAlloc(sizeof CLocals);
  static I64 cnt=0;
  CDoc *dummy=DocNew;
  CHashGeneric3 *gen;
  CHashClass *cls=HashFind(for_class,frog_mem_task->hash_table,HTT_CLASS);
  CMemberLst *mlst,*mlst2;
  StrPrint(ret->name,"CMethodLocals@%d",cnt++);
  ret->vars=HashTableNew(0x10);
  CAST *name,*head;
  U8 *var_class_name;
  I64 idx,off=0,mask;
  DocPrint(dummy,"class %s:CLocalsGeneric0 {\n",ret->name);
//Account for class members first,THEN account for method locals
  while(cls) {
    if(!StrCmp(cls->str,"CFrogThing"))
      break;
    for(mlst=cls->member_lst_and_root;mlst;mlst=mlst->next)
      if(IsSmalltalkMember(mlst->member_class)) {
        gen=CAlloc(sizeof CHashGeneric3);
        gen->type=HTT_FRAME_PTR;
        gen->user_data0=-1; //Not defined(class members are referenced from self)
//If we are a "raw type"(I64/F64 etc),set user_data1 to mark it as such.
        //This seperates it from "normal" vars
        if(var_class_name=RawAccessType(for_class,mlst->str)) {
	  gen->user_data1=TRUE;
	  gen->user_data3=var_class_name;
        }
        gen->user_data2=TRUE; //Is a SELF member
        gen->str=StrNew(mlst->str);
//	ret->cnt++;
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
      gen=CAlloc(sizeof CHashGeneric3);
      gen->type=HTT_FRAME_PTR;
      if(!StrCmp(name->var_class_name,"CFrogNum")) {
        gen->user_data1=TRUE;
        Bts(&mask,off);
        DocPrint(dummy,"  CFrogThing *%s;\n",gen->str); //Treat like a pointer
        gen->user_data3="F64";
      } else {
        DocPrint(dummy,"  CFrogThing *%s;\n",gen->str);
        gen->user_data3=name->var_class_name;
      }
      gen->user_data0=off++;
      gen->str=StrNew(name->name);
      ret->cnt++;
      HashAdd(gen,ret->vars);
    }
  }
  ret->raw_mask=mask;
  DocPrint(dummy,"};\n");
  ExeDoc(dummy);
  DocDel(dummy);
  return ret;
}
CLocals *GenerateLocalsFromThunk(CAST *thunk) {
  CLocals *ret=CAlloc(sizeof CLocals);
  static I64 cnt=0;
  U8 *tmp;
  CDoc *dummy=DocNew;
  CHashGeneric3 *gen;
  StrPrint(ret->name,"CThunkLocals@%d",cnt++);
  ret->vars=HashTableNew(0x10);
  CAST *name,*head;
  I64 off=0,mask=0;
  DocPrint(dummy,"class %s:CLocalsGeneric0 {\n",ret->name);
  head=&thunk->args;
  for(name=head->next;name!=head;name=name->next) {
    gen=CAlloc(sizeof CHashGeneric3);
    if(!StrCmp(name->var_class_name,"CFrogNum")) {
      gen->user_data1=TRUE;
      Bts(&mask,off);
      DocPrint(dummy,"  CFrogThing *%s;\n",gen->str);
       gen->user_data3="F64";
    } else {
      DocPrint(dummy,"  CFrogThing *%s;\n",gen->str);
      gen->user_data3=name->var_class_name;
    }
    gen->type=HTT_FRAME_PTR;
    gen->user_data0=off++;
    gen->str=StrNew(name->name);
    ret->cnt++;
    HashAdd(gen,ret->vars);
  }
  DocPrint(dummy,"};\n");
  ret->raw_mask=mask;
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
Bool LocalsIsEscaped(CLocals *locals) {
  CHashGeneric3 *g;
  CHashTable *t;
  I64 idx;
  Bool ret=FALSE;
//Heres the deal,any escaped parents need to have a (non-stack) chain the the parent.

$SP,"<1>",BI=1$;













  for(;locals;locals=locals->next) {
    t=locals->vars;
    for(idx=0;idx<=t->mask;idx++)
      for(g=t->body[idx];g;g=g->next) 
        if(g->is_escaped)
         ret=TRUE;
  }
  return ret;
}
//Used with escape anaylsis
Bool STEscapeMarkLocal(CLocals *who,U8 *name) {
//Dont mark a local in the current scope
  CHashGeneric3 *got;
  if(HashSingleTableFind(name,who->vars,HTT_FRAME_PTR))
    return FALSE;

  while(who&&!(got=HashSingleTableFind(name,who->vars,HTT_FRAME_PTR)))
    who=who->next;
  if(got&&!got->user_data2)
    got->is_escaped=TRUE;
  return ToBool(got);
}
U0 Escape(CLocals *l,CAST *ast) {
  if(ast->type==AST_VAR) {
    STEscapeMarkLocal(l,ast->name);
    return;
  }
  CAST *head=&ast->args,*cur;
  if(ast->type==AST_BLOCK) {
    head=&ast->body;
    for(cur=head->next;cur!=head;cur=cur->next)
      Escape(l,cur);
  } else {
    if(head->next) {
      for(cur=head->next;cur!=head;cur=cur->next)
        Escape(l,cur);
    
    }
  }
}

Bool STIsRawMember(CLocals *who,U8 *name) {
  CHashGeneric *g=NULL;
  while(who&&!(g=HashSingleTableFind(name,who->vars,HTT_FRAME_PTR))) {
    who=who->next;
  }
  if(g){
    return g->user_data1;
  }
  return FALSE;
}
Bool STIsSelfMember(CLocals *who,U8 *name) {
  CHashGeneric *g=NULL;
  while(who&&!(g=HashSingleTableFind(name,who->vars,HTT_FRAME_PTR))) {
    who=who->next;
  }
  if(g){
    return g->user_data2;
  }
  return FALSE;
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
I64 ast_case_num=0;
U0 CompileASTFinal(CDoc *doc,CAST *ast,U8 *locals,I64 stack_depth,I64 jump_to=INVALID_PTR,Bool allow_f64=FALSE) {
  CompileAST(doc,ast,locals,stack_depth,jump_to,allow_f64);
}
U0 ReplaceElem(CDoc *doc,CDocEntry *ent,U8 *with,...) {
  if(!ent) return;
  with=StrPrintJoin(NULL,with,argc,argv);
  CDocEntry *old=doc->cur_entry;
  doc->cur_entry=ent;
  DocPutS(doc,with);
  DocEntryDel(doc,ent);
  doc->cur_entry=old;
  DocBottom(doc);
  Free(with);
}

U8 *CompileThunk(CAST *block,CLocals *parent=NULL) {
  static I64 thunk_cnt=0;
  U8 *ret,*tmp;
  I64 idx,thunk_idx=thunk_cnt++;
#ifdef DEBUG
  tmp=MStrPrint("/STDebugDir/Thunks@%s",FramePtr("MethodClass"));
  if(!FileFind(tmp)) DirMk(tmp);
  Free(tmp);
  tmp=MStrPrint("/STDebugDir/Thunks@%s/t%d.HC",FramePtr("MethodClass"),thunk_cnt);
  CDoc *doc=DocNew(tmp),*old_put=Fs->put_doc;
  DocPrint(doc,"#if 0\n");
  DocPrint(doc,"/*This is a generated file,DON'T FUCKIN EDIT*/\n");
  Fs->put_doc=doc;
  DumpAst(block);
  Fs->put_doc=old_put;
  Free(tmp);
  DocPrint(doc,"\n#endif\n");
#else
  CDoc *doc=DocNew;
#endif
  CDocEntry *replace,*frame;
  CLocals *locals=GenerateLocalsFromThunk(block);
  locals->next=parent;
  CAST *var,*head;
  FramePtrAdd("ST@@stk_depth",0);
  DocPrint(doc,"CFrogThing *Thunk@@%d(CFrogThing *self,CLocalsGeneric0 *parent_frame,...) {\n",thunk_idx);
  replace=DocPrint(doc,"  CFrogThing *stk[$$LK,\"replace_me\"$$],*retval=FROG_SMALL_NIL,**tmp;\n");
  DocPrint(doc,"CFrogThing *stk0,*stk1,*stk2,*stk3,*stk4,*stk5;\n");
  DocPrint(doc,"  Bool false=FALSE;\n");
  frame=DocPrint(doc,"  $$LK,\"replaxe_me\"$$");
  DocPrint(doc,"  if(!return_flag) return_flag=&false;\n");
  DocPrint(doc,"  parent_frame=Fs->user_data;\n");
  DocPrint(doc,"  parent_frame->_raw_mask=%d;\n",locals->raw_mask);
  DocPrint(doc,"  I64 unwind=0;I64 next_case=%d;\n",ast_case_num);
  head=&block->args;
  idx=0;
  for(var=head->next;var!=head;var=var->next) {
    DocPrint(doc,"  tmp=&");
    STGetLocal(doc,locals,var->name);
    DocPrint(doc,";\n");
    if(STIsRawMember(locals,var->name)){
      DocPrint(doc,"  tmp(F64*)[0]=AsF64(argv[%d]);\n",idx);
    } else
      DocPrint(doc,"  *tmp=argv[%d];\n",idx);
    idx++;
  }

  head=&block->body;
  DocPrint(doc,"FrogThingLock(self);\n");
  for(var=head->next;var!=head;var=var->next)
    Escape(locals,var);
  for(var=head->next;var!=head;var=var->next) {
    if(var->type!=AST_STR) {
      CompileASTFinal(doc,var,locals,0);
    }
  }
  DocPrint(doc,"L%d:\n",ast_case_num++);
  head=&block->args;
  idx=0;
  DocPrint(doc,"ret:\n");
  DocPrint(doc,"  FrogThingUnlock(self);\n");
  DocPrint(doc,"  STFrameDel;\n"); //Does not Free(frame data may be on stack)
  DocPrint(doc,"  return stk0;\n");
  DocPrint(doc,"};");
  ReplaceElem(doc,replace,"%d",MaxI64(FramePtr("ST@@stk_depth")-6,0));
  if(LocalsIsEscaped(locals)) 
    ReplaceElem(doc,frame,"Bool *return_flag=STNewBlockFrame(\"%Q\",parent_frame)->return_flag;\n",locals->name);
  else
    ReplaceElem(doc,frame,"%Q stk_frame;MakeAnonBlockFrame(&stk_frame,%d,parent_frame); Bool *return_flag=parent_frame->_return_flag;\n",locals->name,locals->cnt);
  ret=DocSave(doc);//Saves to string
#ifdef DEBUG
  DocWrite(doc);
#endif
  ExePutS(ret);
  Free(ret);
  DocDel(doc);
  FramePtrDel("ST@@stk_depth");
  LocalsDel(locals);
  return MStrPrint("Thunk@@%d",thunk_idx);
}
U0 DftCall(CDoc *doc,CLocals *l,CAST *ast,I64 stack_depth,U8 *op,I64 cnt=2) {
  U8 *cls_name=NULL,*rc;
 Bool check=FALSE;
  CAST *self=ast->args.next;
  if(self->type==AST_VAR) {
//TODO
    if(cls_name=VarHasMethod(l,self->name,op)) {
      DocPrint(doc,"  retval=");
      GenerateMethodCall(doc,cls_name,op,TRUE);
      goto args;
    }
  } else if(self->is_f64) {
    cls_name=ClassHasMethod("CFrogNum",op);
try_class:
    if(cls_name) {
      DocPrint(doc,"  retval=");
      GenerateMethodCall(doc,cls_name,op,FALSE);
      goto args;
    }
  } else if(self->type==AST_BLOCK) {
    cls_name=ClassHasMethod("CFrogBlock",op);
    goto try_class;
  } else if(self->type==AST_ARRAY) {
    cls_name=ClassHasMethod("CFrogArray",op);
    goto try_class;
  } else if(self->type==AST_SELF) {
    cls_name=ClassHasMethod(FramePtr("MethodClass"),op);
    goto try_class;
  } else if(ast->var_class_name[0]) {
    cls_name=self->var_class_name;
    goto try_class;
  }
//TODO static return-type of method
  I64 idx;
  DocPrint(doc,"  retval=CallScriptUniverse(%d,\n",NameToUniverseNumber(op));
args:
  DocPrint(doc,"%s\n",StackFrame2Var(stack_depth));
  for(idx=0;idx<cnt;idx++) {
    DocPrint(doc,",");
    DocPrint(doc,"%s",StackFrame2Var(stack_depth+1+idx));
 }
  DocPrint(doc,");/* %s */\n",op);
  DocPrint(doc,"  %s=retval;\n",StackFrame2Var(stack_depth));
  if(rc=MethodReturnClass(cls_name,op)) {
    StrCpy(ast->var_class_name,rc);
  }

}
Bool IsF64ExprNode(CLocals *l,CAST *ast) {
  U8 *cn;
  CAST *a,*b;
  switch(ast->type) {
    case AST_NUM:
      return ast->is_f64=TRUE;
    case AST_VAR:
      if(STIsRawMember(l,ast->name)) {
        return ast->is_f64=TRUE;
      }
      return FALSE;
    case AST_MEMBER:
      a=ast->args.next;
      if(a->type==AST_VAR&&StrLen(a->var_class_name)) {
        if(RawAccessType(a->var_class_name,ast->name))
	  return ast->is_f64=TRUE;
      }
      return FALSE;
    case AST_UNOP:
      a=ast->args.next;
      if(IsF64ExprNode(l,a)) {
        if(ToBool(ClassHasMethod("CFrogNum",ast->op_name)))
	  if(cn=MethodReturnClass("CFrogNum",ast->op_name)) {
	    return ast->is_f64=!StrCmp(cn,"CFrogNum");
          }
      }
      return FALSE;
    case AST_BINOP:
      a=ast->args.next;
      b=ast->args.last;
      if(IsF64ExprNode(l,a)&&IsF64ExprNode(l,b)) {
        if(ToBool(ClassHasMethod("CFrogNum",ast->op_name)))
	  if(cn=MethodReturnClass("CFrogNum",ast->op_name))
	    return ast->is_f64=!StrCmp(cn,"CFrogNum");
      }
      return FALSE;
    case AST_KEYWORD:
      a=&ast->args;
      for(b=a->next;a!=b;b=b->next) {
        if(!IsF64ExprNode(l,b)) return FALSE;
      }
      if(ToBool(ClassHasMethod("CFrogNum",ast->op_name)))
        if(cn=MethodReturnClass("CFrogNum",ast->op_name))
	  return ast->is_f64=!StrCmp(cn,"CFrogNum");
  }
  return FALSE;
}

U0 AssignTypeToNode(CLocals *l,CAST *ast) {
  U8 *cn;
  if(*ast->var_class_name) return;
  CAST *a;
  switch(ast->type) {
   case AST_VAR:
     if(!ast->var_class_name[0]) {
       if(HashFind(ast->name,Fs->hash_table,HTT_CLASS))
	 StrCpy(ast->var_class_name,ast->name);
     }
     break;
   case AST_UNOP:
   case AST_BINOP:
   case AST_KEYWORD:
     a=ast->args.next;
     if(cn=ClassHasMethod(a->var_class_name,ast->op_name)) {
        if(cn=MethodReturnClass(cn,ast->op_name)) {
	  StrCpy(ast->var_class_name,cn);
	}
     }
  }
}
Bool ReturnsF64(CLocals *l,CAST *ast) {
  AssignTypeToNode(l,ast);
  return !StrCmp(ast->var_class_name,"CFrogNum");
}


Bool IsAllF64(CAST *ast) {
  if(!ast->is_f64) return FALSE;
  CAST *head=&ast->args,*cur=head->next;
  while(head!=cur) {
//Special case,AST_MEMBER's var side might not be a f64,but the result is an f64
    if(cur->type!=AST_MEMBER) {
      if(!IsAllF64(cur)) return FALSE;
    } else if(!cur->is_f64) //cur->tpye==AST_MEMBER
      return FALSE;
    cur=cur->next;
  }
  return TRUE;
}
U0 NumPrimDft(CDoc *doc,CLocals *l,CAST *ast,I64 stack_depth) {
  CAST *head=&ast->args,*cur;
  I64 idx=0;
  U8 *cls_name;
  ast->is_f64=TRUE;
  DocPrint(doc,"AsF64(");
  if(cls_name=ClassHasMethod("CFrogNum",ast->name))
    GenerateMethodCall(doc,cls_name,ast->name,FALSE);
  else
    DocPrint(doc,"CallScriptUniverse(%d,\n",NameToUniverseNumber(ast->name));
  for(cur=head->next;cur!=head;cur=cur->next) {
    DocPrint(doc,"FrogNumNew(");
    CompileAST(doc,cur,l,stack_depth,,TRUE);
    DocPrint(doc,")");
    if(cur->next!=head)
      DocPrint(doc,",");
 }
  StrCpy(ast->var_class_name,"CFrogNum");
  DocPrint(doc,"))");
}
U0 NumPrim2(CDoc *doc,CLocals *l,CAST *ast,I64 stack_depth,U8 *op,U8*alt_name=NULL) {
  if(!alt_name) alt_name=op;
  CAST *a=ast->args.next,*b=ast->args.last;
  CDoc *tmp;
  U8 *save,*save2;
  ast->is_f64=1;
  DocPrint(doc,"(");
  CompileAST(doc,a,l,stack_depth,,TRUE);
  DocPrint(doc,"%s",op);
  CompileAST(doc,b,l,stack_depth,,TRUE);
  DocPrint(doc,")");
  StrCpy(ast->var_class_name,"CFrogNum");
}
U0 NumPrim2B(CDoc *doc,CLocals *l,CAST *ast,I64 stack_depth,U8 *op,U8*alt_name=NULL) {
  if(!alt_name) alt_name=op;
  CAST *a=ast->args.next,*b=ast->args.last;
  CDoc *tmp;
  U8 *save,*save2;
  ast->is_f64=1;
  DocPrint(doc,"%s(",op);
  CompileAST(doc,a,l,stack_depth,,TRUE);
  DocPrint(doc,",");
  CompileAST(doc,b,l,stack_depth,,TRUE);
  DocPrint(doc,")");
  StrCpy(ast->var_class_name,"CFrogNum");
}
U0 NumPrim1(CDoc *doc,CLocals *l,CAST *ast,I64 stack_depth,U8 *op,U8 *alt_name=NULL) {
  if(!alt_name) alt_name=op;
  CDoc *tmp;
  U8 *save;
  CAST *a=ast->args.next;
  DocPrint(doc,"(%s(",op);
  CompileAST(doc,a,l,stack_depth,,TRUE);
  DocPrint(doc,"))");
  StrCpy(ast->var_class_name,"CFrogNum");
}
U0 UnrollBlock(CDoc *doc,CLocals *l,I64 stack_depth,CAST *bl,I64 jump_to=INVALID_PTR) {
  CAST *head,*cur; 
  if(bl) {
    if(bl->type==AST_BLOCK) {
      head=&bl->body;
      for(cur=head->next;cur!=head;cur=cur->next) {
	if(cur->type!=AST_STR||cur==head->last) {
	  if(cur==head->last) 
            CompileAST(doc,cur,l,stack_depth,jump_to);
	  else
            CompileAST(doc,cur,l,stack_depth);
	}
      }
    }
    return;
  }
  if(!bl->switch_num) {
    bl->switch_num=ast_case_num++;
    DocPrint(doc,"L%d:\n",bl->switch_num);
  }
  DocPrint(doc,"  retval=FrogBlockValue(%s);",StackFrame2Var(stack_depth));
  DocPrint(doc,"if(return_flag[0]) goto ret;\n");
  DocPrint(doc,"  %s=retval;\n",StackFrame2Var(stack_depth));
  if(jump_to!=INVALID_PTR)
    DocPrint(doc,"goto L%d;\n",jump_to);
}
F64 MemberF64(U8 *self,U8 *expect_type,I64 offset,I64 raw_type) {
  if(!ThingHasClass2(self,expect_type)) return 0.;
  self+=offset;
  switch(raw_type) {
    case RT_I8: return self(I8*)[0];
    case RT_I16: return self(I16*)[0];
    case RT_I32: return self(I32*)[0];
    case RT_I64: return self(I64*)[0];
    case RT_U8: return self(U8*)[0];
    case RT_U16: return self(U16*)[0];
    case RT_U32: return self(U32*)[0];
    case RT_U64: return self(U64*)[0];
    case RT_F64: return self(F64*)[0];
  }
  return 0.;
}
U0 CompileAST(CDoc *doc,CAST *ast,CLocals *locals,I64 stack_depth,I64 jump_to=INVALID_PTR,Bool allow_f64=FALSE) {
  U8 dummy[STR_LEN];
  I64 cnt,idx;
  CDocEntry *ent,*ent2;
  CAST *cur,*cur2;
  U8 *thunk_name;
  U8 *raw_class_name;
  U8 *conv_name;
  Bool has_non_f64,wants_end_paren=FALSE;
  CMemberLst *mlst;
  if(allow_f64) {
    ast->is_f64=IsF64ExprNode(locals,ast);
  } else if(IsF64ExprNode(locals,ast)) {
    DocPrint(doc,"L%d:\n",ast_case_num++);
    DocPrint(doc,"retval=FrogNumNew(");
    CompileAST(doc,ast,locals,stack_depth+1,jump_to,TRUE);
    DocPrint(doc,");\n");
    DocPrint(doc,"%s=retval;",StackFrame2Var(stack_depth));
    if(jump_to!=INVALID_PTR) {
      DocPrint(doc,"goto L%d;\n",jump_to);
    }
    return;
  }
  if(ast->type!=AST_STACK_TEMPORARY)
    if(ast->compiled++) {
      DocInsDoc(,doc);
      idx=64;
      while(--idx>=0) "%P\n",Caller(idx);
      throw('AST2');
    }
  switch(ast->type) {
      break;case AST_STACK_TEMPORARY:
      DocPrint(doc,"AsF64(%s)",StackFrame2Var(ast->stk_idx));
      return;
      break;case AST_UNOP:
      cnt=0;
pass:
//Skip past object we are calling to
      cur=ast->args.next->next;
      if(!StrCmp(ast->op_name,"whileTrue:")) {
        idx=ast_case_num;
        UnrollBlock(doc,locals,stack_depth,ast->args.next);
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"L%d:\n",ast->switch_num);
        ent=DocPrint(doc,"if(AsF64(%s)==0.) {goto L$$LK,\"dummy1\"$$;}",StackFrame2Var(stack_depth));
        UnrollBlock(doc,locals,stack_depth,ast->args.last,idx);
        ReplaceElem(doc,ent,"%d",ast_case_num);
        return;
      }
      if(!StrCmp(ast->op_name,"whileFalse:")) {
        idx=ast_case_num;
        UnrollBlock(doc,locals,stack_depth,ast->args.next);
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"L%d:\n",ast->switch_num);
        ent=DocPrint(doc,"if(AsF64(%s)) {goto L$$LK,\"dummy2\"$$;}",StackFrame2Var(stack_depth));
        UnrollBlock(doc,locals,stack_depth,ast->args.last,idx);
        ReplaceElem(doc,ent,"%d",ast_case_num);
        return;
        break;
      }
      if(!StrCmp(ast->op_name,"ifTrue:")) {
        cur=ast->args.next;
        if(IsF64ExprNode(locals,cur)) {
	  ast->switch_num=ast_case_num++;
	  DocPrint(doc,"L%d:\n",ast->switch_num);
	  DocPrint(doc,"if((");
	  CompileAST(doc,cur,locals,stack_depth,,TRUE);
	  ent=DocPrint(doc,")==0) {goto L$$LK,\"dummy3\"$$;}",StackFrame2Var(stack_depth));
        } else {
	  CompileAST(doc,cur,locals,stack_depth,,0);
	  ast->switch_num=ast_case_num++;
	  DocPrint(doc,"L%d:\n",ast->switch_num);
	  DocPrint(doc,"if(AsF64(%s",StackFrame2Var(stack_depth));
	  ent=DocPrint(doc,")==0) {goto L$$LK,\"dummy3\"$$;}",StackFrame2Var(stack_depth));
        }
        UnrollBlock(doc,locals,stack_depth,ast->args.last);
        ReplaceElem(doc,ent,"%d",ast_case_num++);
        DocPrint(doc,"L%d:\n",ast_case_num-1);
        return ;
      }
      if(!StrCmp(ast->op_name,"ifFalse:")) {
        cur=ast->args.next;
        if(IsF64ExprNode(locals,cur)) {
	  ast->switch_num=ast_case_num++;
	  DocPrint(doc,"L%d:\n",ast->switch_num);
	  DocPrint(doc,"if((");
	  CompileAST(doc,cur,locals,stack_depth,,TRUE);
	  ent=DocPrint(doc,")) {goto L$$LK,\"dummy3\"$$;}",StackFrame2Var(stack_depth));
        } else {
	  CompileAST(doc,cur,locals,stack_depth,,0);
	  ast->switch_num=ast_case_num++;
	  DocPrint(doc,"L%d:\n",ast->switch_num);
	  DocPrint(doc,"if(AsF64(%s",StackFrame2Var(stack_depth));
	  ent=DocPrint(doc,")) {goto L$$LK,\"dummy3\"$$;}",StackFrame2Var(stack_depth));
        }
        UnrollBlock(doc,locals,stack_depth,ast->args.last);
        ReplaceElem(doc,ent,"%d",ast_case_num);
        return ;
      }
      if(!StrCmp(ast->op_name,"ifTrue:ifFalse:")) {
        cur=ast->args.next;
        CompileAST(doc,cur,locals,stack_depth,,FALSE);
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"L%d:\n",ast->switch_num);
        DocPrint(doc,"if(AsF64(%s",StackFrame2Var(stack_depth));
        ent=DocPrint(doc,")==0.) {goto L$$LK,\"dummy5\"$$;}",StackFrame2Var(stack_depth));
        UnrollBlock(doc,locals,stack_depth,ast->args.next->next);
//Make a dummy switch statement that delegates to end
        DocPrint(doc,"L%d:\n",ast_case_num++);
        ent2=DocPrint(doc,"goto L$$TX+CX,\"dummy6\"$$;");
        ReplaceElem(doc,ent,"%d",ast_case_num);
        UnrollBlock(doc,locals,stack_depth,ast->args.last);
        ReplaceElem(doc,ent2,"%d",ast_case_num);
        return;
      }
//Primtive method time
      if(!IsAllF64(ast)) { //These(is_f64) are computed beforehand
        cur=ast->args.next;
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"L%d:\n",ast->switch_num);
        has_non_f64=FALSE;
//Compile non-numbers first
        for(idx=0;idx<cnt+1;idx++) { //+1 includes self
	  if(IsF64ExprNode(locals,cur)) {
//Have an F64
	  } else if(ReturnsF64(locals,cur)){
//Have an F64
	  } else
	    has_non_f64=TRUE;
	  if(!IsF64ExprNode(locals,cur))
	    CompileAST(doc,cur,locals,stack_depth+idx,,FALSE);
	  cur=cur->next;
        }

        cur=ast->args.next;

        if(raw_class_name=MethodReturnClass("CFrogNum",ast->op_name))
	  if(!StrCmp(raw_class_name,"CFrogName"))
	    if(!has_non_f64) {
	      for(idx=0;idx<cnt+1;idx++) { //+1 includes self
	        if(!IsF64ExprNode(locals,cur)) {
		  cur->type=AST_STACK_TEMPORARY;
		  cur->stk_idx=stack_depth+idx;
		  cur->is_f64=TRUE;
	        }
	        cur=cur->next;
	      }
	      wants_end_paren=TRUE;
	      DocPrint(doc,"%s=FrogNumNew(",StackFrame2Var(stack_depth));
	      goto force_f64;
	    }

        for(idx=0;idx<cnt+1;idx++) { //+1 includes self
	  if(IsF64ExprNode(locals,cur)) {
	    DocPrint(doc,"%s=FrogNumNew(",StackFrame2Var(stack_depth+idx));
	    CompileAST(doc,cur,locals,stack_depth+idx,,TRUE);
	    DocPrint(doc,");");
	  }
	  cur=cur->next;
        }
      } else 
        goto force_f64;
      if(allow_f64) {
force_f64:;
        if(!StrCmp(ast->op_name,"+")) {
	  NumPrim2(doc,locals,ast,stack_depth,"+");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"-")) {
	  NumPrim2(doc,locals,ast,stack_depth,"-");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"*")) {
	  NumPrim2(doc,locals,ast,stack_depth,"*");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"/")) {
	  NumPrim2(doc,locals,ast,stack_depth,"/");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,">")) {
	  NumPrim2(doc,locals,ast,stack_depth,">");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"<")) {
	  NumPrim2(doc,locals,ast,stack_depth,"<");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"<=")) {
	  NumPrim2(doc,locals,ast,stack_depth,"<=");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,">=")) {
	  NumPrim2(doc,locals,ast,stack_depth,">=");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"=")) {
	  NumPrim2(doc,locals,ast,stack_depth,"==","=");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"~=")) {
	  NumPrim2(doc,locals,ast,stack_depth,"!=","~=");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"negated")) {
	  NumPrim1(doc,locals,ast,stack_depth,"-","negated");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"cos")) {
	  NumPrim1(doc,locals,ast,stack_depth,"Cos","cos");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"sin")) {
	  NumPrim1(doc,locals,ast,stack_depth,"Sin","sin");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"squared")) {
	  NumPrim1(doc,locals,ast,stack_depth,"Sqr","squared");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"tan")) {
	  NumPrim1(doc,locals,ast,stack_depth,"Tan","tan");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"arcsin")) {
	  NumPrim1(doc,locals,ast,stack_depth,"ASin","arcsin");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"arctan")) {
	  NumPrim1(doc,locals,ast,stack_depth,"ATan","arctan");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"arccos")) {
	  NumPrim1(doc,locals,ast,stack_depth,"ACos","arccos");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"sqrt")) {
	  NumPrim1(doc,locals,ast,stack_depth,"Sqrt","sqrt");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"floor")) {
	  NumPrim1(doc,locals,ast,stack_depth,"Floor","floor");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"ceil")) {
	  NumPrim1(doc,locals,ast,stack_depth,"Ceil","ceil");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"sign")) {
	  NumPrim1(doc,locals,ast,stack_depth,"Sign","sign");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"abs")) {
	  NumPrim1(doc,locals,ast,stack_depth,"Abs","abs");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"round")) {
	  NumPrim1(doc,locals,ast,stack_depth,"Round","round");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"raisedTo:")) {
	  NumPrim2(doc,locals,ast,stack_depth,"`","raisedTo:");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"or:")) {
	  NumPrim2(doc,locals,ast,stack_depth,"||","or:");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"and:")) {
	  NumPrim2(doc,locals,ast,stack_depth,"&&","and:");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"max:")) {
	  NumPrim2B(doc,locals,ast,stack_depth,"Max","max:");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"min:")) {
	  NumPrim2B(doc,locals,ast,stack_depth,"Min","min:");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"not")) {
	  NumPrim1(doc,locals,ast,stack_depth,"!","not");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"arg:")) {
	  NumPrim2B(doc,locals,ast,stack_depth,"Arg","arg:");
	  goto prim_skip;
        }
        NumPrimDft(doc,locals,ast,stack_depth);
        goto prim_skip;
      }
      DftCall(doc,locals,ast,stack_depth,ast->op_name,cnt);
      DocPrint(doc,"if(return_flag[0]) { goto ret;}");
      break;
prim_skip:
      if(wants_end_paren) DocPrint(doc,");\n");
      return;
      break;case AST_BINOP:
      cnt=1;
      goto pass;
      break;case AST_SYMBOL:
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"L%d:\n",ast->switch_num);
      DocPrint(doc,"  %s=FrogSymbol0(%d)->value;\n",StackFrame2Var(stack_depth),NameToUniverseNumber(ast->name));
      break;case AST_KEYWORD:
      cnt=StrOcc(ast->op_name,':');
      goto pass;
      break;case AST_ASSIGN:
      cur=ast->args.next;
      if(cur->type==AST_VAR&&STIsRawMember(locals,cur->name)&&IsF64ExprNode(locals,ast->args.last)) {
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"L%d:\n",ast->switch_num);
        raw_class_name=VarClassName(locals,cur->name);
        DocPrint(doc,"");
        if(STIsSelfMember(locals,cur->name)) {
	  mlst=MemberFind(cur->name,HashFind(FramePtr("MethodClass"),frog_mem_task->hash_table,HTT_CLASS));
	  DocPrint(doc,"(ToI64(self)+%d)(%s*)[0]=",mlst->offset,raw_class_name);
        } else {
	  STGetLocal(doc,locals,cur->name);
	  DocPrint(doc,"(%s)=",raw_class_name);
        }
        CompileAST(doc,ast->args.last,locals,stack_depth,,TRUE);
        DocPrint(doc,";\n");
        break;
      }
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"L%d:\n",ast->switch_num);
      if(cur->type==AST_SYMBOL) {
        CompileAST(doc,ast->args.last,locals,stack_depth);
        DocPrint(doc,"\n  FrogSymbol0(%d)->value=%s;\n",NameToUniverseNumber(cur->name),StackFrame2Var(stack_depth));
      } else if(cur->type==AST_VAR) {      
        CompileAST(doc,ast->args.last,locals,stack_depth);
        if(STIsSelfMember(locals,cur->name)) {
	  mlst=MemberFind(cur->name,HashFind(FramePtr("MethodClass"),frog_mem_task->hash_table,HTT_CLASS));
	  DocPrint(doc,"  tmp=ToI64(self)+%d;\n",mlst->offset);
	  if(STIsRawMember(locals,cur->name))
	    goto assign_raw;
	  goto assign_st;
        } else if(!STIsRawMember(locals,cur->name)) {
	  DocPrint(doc,"  tmp=&");
	  STGetLocal(doc,locals,cur->name);
	  DocPrint(doc,";\n");
assign_st :
	  DocPrint(doc,"\n*tmp=%s;\n",StackFrame2Var(stack_depth));
        } else {
	  DocPrint(doc,"  tmp=&");
	  STGetLocal(doc,locals,cur->name);
	  DocPrint(doc,";\n");
assign_raw:
	  raw_class_name=VarClassName(locals,cur->name);
	  DocPrint(doc,"tmp(%s*)[0]=AsF64(%s);\n",raw_class_name,StackFrame2Var(stack_depth));
        }
      } else if(cur->type==AST_MEMBER) {
        cur=ast->args.next;
        CompileAST(doc,cur->args.next,locals,stack_depth,,FALSE);
        CompileAST(doc,ast->args.last,locals,stack_depth+1,,FALSE);
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"L%d:\n",ast->switch_num);
        cur=ast->args.next; //AST_ASSIGN
        cur2=cur;
        cur=cur->args.next; //AST_MEMBER
        DocPrint(doc,"FrogThingLock(%s);\n",StackFrame2Var(stack_depth));
        if(HashFind(cur->var_class_name,Fs->hash_table,HTT_CLASS)) { 
	  DocPrint(doc,"if(ThingHasClass2(%s,%d)) /* %s */ {\n",StackFrame2Var(stack_depth),UniverseAddClass(cur->var_class_name),cur->var_class_name);
	  mlst=MemberFind(cur2->name,HashFind(cur->var_class_name,Fs->hash_table,HTT_CLASS));
	  if(mlst) {
	    if(mlst->member_class->ptr_stars_cnt==0) {
	      raw_class_name=mlst->member_class->str;
	      DocPrint(doc,"(ToI64(%s)+%d)(%s*)[0]=AsF64(%s);",StackFrame2Var(stack_depth),mlst->offset,raw_class_name,StackFrame2Var(stack_depth+1));
	      StrCpy(ast->var_class_name,"CFrogNum");
	    } else if(mlst->member_class->ptr_stars_cnt==1) {
//TODO check for class
	      DocPrint(doc,"(ToI64(%s)+%d)(CFrogThing**)[0]=%s;",StackFrame2Var(stack_depth),mlst->offset,StackFrame2Var(stack_depth+1));
	      StrCpy(ast->var_class_name,mlst->member_class[-1].str);
	    } else
	      throw('Fuck');
	  } else {
	    throw('Member'); 
	  }
	  DocPrint(doc,"}\n");
        } else {
write_generic_member:
//Cur has the member name
	  cur=ast->args.next; //AST_MEMBER
	  DocPrint(doc,"SetClassMemberVal(%s,\"%s\",%s);\n",StackFrame2Var(stack_depth),cur->name,StackFrame2Var(stack_depth+1));
        }
        DocPrint(doc,"FrogThingUnlock(%s);\n",StackFrame2Var(stack_depth));
      } else
        throw('Compile');
      break;case AST_STR:
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"L%d:\n",ast->switch_num);
      DocPrint(doc,"  %s=FrogStrNew(\"%Q\");\n",StackFrame2Var(stack_depth),ast->str);
      break;case AST_VAR:
      if(ast->is_f64) {
        conv_name="ToF64";
      } else {
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"L%d:%s=\n",ast->switch_num,StackFrame2Var(stack_depth));
        conv_name="FrogNumNew";
      }
      if(STHasLocal(locals,ast->name)) {
        idx=VarClassName(locals,ast->name);
        if(idx) StrCpy(ast->var_class_name,idx);
        if(STIsSelfMember(locals,ast->name)) {
	  mlst=MemberFind(ast->name,HashFind(FramePtr("MethodClass"),frog_mem_task->hash_table,HTT_CLASS));
	  raw_class_name=VarClassName(locals,ast->name);
//ToF64 turns an I64(forced) into an F64
	  if(STIsRawMember(locals,ast->name)) {
	    if(ast->is_f64&&!StrCmp(raw_class_name,"F64"))
	      conv_name="";
	    DocPrint(doc,"  %s((ToI64(self)+%d)(%s*)[0])",conv_name,mlst->offset,raw_class_name);
	  } else {
	    if(ast->is_f64)
	      DocPrint(doc,"AsF64(");
	    DocPrint(doc,"  ((ToI64(self)+%d)(CFrogThing**)[0])",mlst->offset);
	    if(ast->is_f64)
	      DocPrint(doc,")");
	  }
        } else if(!STIsRawMember(locals,ast->name)) {
	  if(ast->is_f64)
	    DocPrint(doc,"AsF64(");
	  STGetLocal(doc,locals,ast->name);
	  if(ast->is_f64)
	    DocPrint(doc,")");
        } else {
	  raw_class_name=VarClassName(locals,ast->name);
//ToF64 turns an I64(forced) into an F64
	  if(ast->is_f64&&!StrCmp(raw_class_name,"F64"))
	    conv_name="";
	  DocPrint(doc,"%s((&",conv_name);
	  STGetLocal(doc,locals,ast->name);
	  DocPrint(doc,")(%s*)[0])",raw_class_name);
        }
      } else if(HashFind(ast->name,Fs->hash_table,HTT_CLASS)) {
        DocPrint(doc,"FrogClassNew(%d);",UniverseAddClass(ast->name));
      } else
        DocPrint(doc,"FROG_SMALL_NIL;");
      if(!ast->is_f64) DocPrint(doc,";");
      else return;
      break;case AST_ARRAY:
      stack_depth++;
      idx=0;
      for(cur=ast->body.next;cur!=&ast->body;cur=cur->next) {
        CompileAST(doc,cur,locals,stack_depth+idx++);
      }
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"L%d:\n",ast->switch_num);
      DocPrint(doc,"  %s=FrogArrayNew;\n",StackFrame2Var(stack_depth-1));
      idx=0;
      for(cur=ast->body.next;cur!=&ast->body;cur=cur->next) {
        DocPrint(doc,"  I64SetAdd(%s(CFrogArray*)->items,%s);\n",StackFrame2Var(stack_depth-1),StackFrame2Var(stack_depth+idx++));
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
      return;
      break;case AST_BLOCK:
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"L%d:\n",ast->switch_num);
      thunk_name=CompileThunk(ast,locals);
      DocPrint(doc,"  %s=FrogBlockNew(&%s,parent_frame,self);\n",StackFrame2Var(stack_depth),thunk_name);
      Free(thunk_name);
      break;case AST_CHR:
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"L%d:\n",ast->switch_num);
      DocPrint(doc,"  %s=FrogChrNew(%d);\n",StackFrame2Var(stack_depth),ast->name[0](U64));
      break;case AST_CASCADE_HEAD:
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"L%d:\n",ast->switch_num);
      DocPrint(doc,"  %s=FrogIncRefCnt(%s)\n;",StackFrame2Var(stack_depth),StackFrame2Var(FramePtr("?CascadeDepth"))); 
      break;case AST_SELF:
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"L%d:\n",ast->switch_num);
      DocPrint(doc,"  %s=FrogIncRefCnt(self);\n",StackFrame2Var(stack_depth)); 
      break;case AST_NUM:
      if(!ast->is_f64) { 
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"L%d:\n",ast->switch_num);
//"Unroll" the call to FrogNumNew
        DocPrint(doc,"  %s=%d; /* %n */ \n",StackFrame2Var(stack_depth),FrogNumNew(ast->num),ast->num); 
      } else {
//In some FPU's 30 may become 29.999999...,FrogNumNew will correct this by ensuring the integer componet is lit
        //(Use parens to preserve sign)
        DocPrint(doc,"(%d)(F64) /* %n */ ",AsF64(FrogNumNew(ast->num)),ast->num);
        return;
      }
      break;case AST_MEMBER:
      cur=ast->args.next;
      if(cur->type==AST_VAR&&ast->is_f64&&StrLen(cur->var_class_name)) {
        mlst=MemberFind(ast->name,HashFind(cur->var_class_name,Fs->hash_table,HTT_CLASS));
        if(mlst) {
	  DocPrint(doc,"MemberF64(");
	  if(STIsSelfMember(locals,cur->name)) {
	    DocPrint(doc,"(ToI64(self)+%d)(CFrogThing**)[0]",
		  MemberFind(cur->name,HashFind(FramePtr("MethodClass"),frog_mem_task->hash_table,HTT_CLASS))->offset,
		  raw_class_name);
	  } else {
	    STGetLocal(doc,locals,cur->name);
	  }
	  DocPrint(doc,",%d,%d,%d)",UniverseAddClass(cur->var_class_name),mlst->offset,mlst->member_class->raw_type);
	  return;
        }
      }
      if(cur->type==AST_VAR&&ast->is_f64) {
        DocPrint(doc,"GetClassMemberValF64(");
        if(STIsSelfMember(locals,cur->name)) {
	  mlst=MemberFind(cur->name,HashFind(FramePtr("MethodClass"),frog_mem_task->hash_table,HTT_CLASS));
	  DocPrint(doc,"(ToI64(self)+%d)(CFrogThing**)[0]",mlst->offset,raw_class_name);
        } else {
	  STGetLocal(doc,locals,cur->name);
        }
        DocPrint(doc,",\"%Q\")",ast->name);
        return;
      }
      CompileAST(doc,cur,locals,stack_depth,,FALSE);
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"L%d:\n",ast->switch_num);
      if(HashFind(cur->var_class_name,Fs->hash_table,HTT_CLASS)) { 
        mlst=MemberFind(ast->name,HashFind(cur->var_class_name,Fs->hash_table,HTT_CLASS));
        if(mlst) {
	  DocPrint(doc,"if(ThingHasClass2(%s,%d)) /* %s */ \n ",StackFrame2Var(stack_depth),UniverseAddClass(cur->var_class_name),cur->var_class_name);
	  if(mlst->member_class->ptr_stars_cnt==0) {
	    raw_class_name=mlst->member_class->str;
	    DocPrint(doc,"  %s=FrogNumNew((ToI64(%s)+%d)(%s*)[0]);",StackFrame2Var(stack_depth),StackFrame2Var(stack_depth),mlst->offset,raw_class_name);
	    StrCpy(ast->var_class_name,"CFrogNum");
	  } else if(mlst->member_class->ptr_stars_cnt==1) {
	    raw_class_name=mlst->member_class[-1].str;
	    DocPrint(doc,"  %s=FrogIncRefCnt((ToI64(%s)+%d)(CFrogThing**)[0]);",StackFrame2Var(stack_depth),StackFrame2Var(stack_depth),mlst->offset);
	    StrCpy(ast->var_class_name,raw_class_name);
	  }
	  DocPrint(doc,"else %s=FROG_SMALL_NIL;",StackFrame2Var(stack_depth));
        } else {
	  throw('Compiler');
        }
      } else {
generic_member:
        DocPrint(doc,"%s=GetClassMemberVal(%s,\"%s\");\n",StackFrame2Var(stack_depth),StackFrame2Var(stack_depth),ast->name);
      }
      break;case AST_RETURN:
      cur=ast->args.next;
      CompileAST(doc,cur,locals,stack_depth,,FALSE);
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"L%d:\n",ast->switch_num);
      DocPrint(doc,"  return_flag[0]=1;\n");
      DocPrint(doc,"  STSetReturnFlags(return_flag);");
      DocPrint(doc,"  retval=%s;\n  unwind=%d;\n  goto ret;\n",StackFrame2Var(stack_depth),stack_depth);
      break; 
    default:
      throw('fuck');
  }
  if(jump_to!=INVALID_PTR) {
    DocPrint(doc,"goto L%d;\n",jump_to);
  }
}
U0 CompileToHolyC(U8 *src,U8 *class_name,U8 *src_path=NULL,Bool class_method=FALSE,Bool register_method=FALSE) {
//Make a dummy hash table for the parser(may liter with dumb FramePtrs on throw)
  FramePtrAdd("MethodClass",class_name);
  try {
  Bool old=Option(OPTf_WARN_UNUSED_VAR,FALSE);
  U8 *ret,*fun_name,*tmp;
  static I64 fun_num=0;
  CDocEntry *replace,*frame;
  I64 idx;
  CAST *var,*head;
  CLexer *lex=LexerNew(src,src_path);
  Lex(lex);
  CMethod *m=ParseMethod(lex,HashFind(class_name,frog_mem_task->hash_table,HTT_CLASS));
#ifdef DEBUG
  tmp=MStrPrint("/STDebugDir/%s",class_name);
  if(!FileFind(tmp)) DirMk(tmp);
  Free(tmp);
  tmp=MStrPrint("/STDebugDir/%s/%s.HC",class_name,m->name);
  while(StrOcc(tmp,':'))
    *StrFirstOcc(tmp,":")='.';
  CDoc *doc=DocNew(tmp);
  DocPrint(doc,"#if 0\n");
  DocPrint(doc,"/*For file \"%Q\" */\n",src_path);
  DocPrint(doc,"/*For method \"%Q\" */\n",m->name);
  DocPrint(doc,"/*This is a generated file,DON'T FUCKIN EDIT*/\n");
  DocPrint(doc,"#endif\n");
  Free(tmp);
#else
  CDoc *doc=DocNew;
#endif
  LexerDel(lex);
  FramePtrAdd("ST@@stk_depth",0);
  if(register_method) {
    GenerateUselessMethod(class_name,m->name,m->return_class);
    FramePtrDel("ST@@stk_depth");
    MethodDel(m);
    FramePtrDel("MethodClass");
    return;
  }
  CLocals *locals=GenerateLocalsFromMethod(m,class_name);
  head=&m->body;
  for(var=head->next;var!=head;var=var->next) {
    Escape(locals,var);
  }
//MUST SET THIS
  fun_name=MStrPrint("%s@%d",class_name,fun_num++);
  DocPrint(doc,"CFrogThing *%s(CFrogThing *self,...) {\n",fun_name);
  replace=DocPrint(doc,"  CFrogThing *stk[$$LK,\"replace\"$$],*retval=FROG_SMALL_NIL,**tmp;\n");
  DocPrint(doc,"CFrogThing *stk0,*stk1,*stk2,*stk3,*stk4,*stk5;\n");
  DocPrint(doc,"  Bool false=FALSE;\n");
  frame=DocPrint(doc,"  $$LK,\"dasds\"$$");
  DocPrint(doc,"  CLocalsGeneric0 *parent_frame=Fs->user_data;\n");
  DocPrint(doc,"  parent_frame->_raw_mask=%d;\n",locals->raw_mask);
  DocPrint(doc,"  I64 unwind=0,next_case=%d;\n",ast_case_num);
  head=&m->args;
  idx=0;
//DocPrint(doc,"DbgPrint(\"%s.%Q\n\");",class_name,m->name);
  for(var=head->next;var!=head;var=var->next) {
    DocPrint(doc,"  tmp=&");
    STGetLocal(doc,locals,var->name);
    DocPrint(doc,";\n");
    if(STIsRawMember(locals,var->name)){
      DocPrint(doc,"  tmp(F64*)[0]=AsF64(argv[%d]);\n",idx);
    } else
      DocPrint(doc,"  *tmp=argv[%d];\n",idx);
    idx++;
  }
  DocPrint(doc,"FrogThingLock(self);\n");
  head=&m->body;
  for(var=head->next;var!=head;var=var->next) {
    if(var->type!=AST_STR) {
      CompileASTFinal(doc,var,locals,0);
    }
  }
  DocPrint(doc,"L%d:\n",ast_case_num++);
  head=&m->args;
  idx=0;
  DocPrint(doc,"ret:\n");
  DocPrint(doc,"  FrogThingUnlock(self);\n");
  DocPrint(doc,"  *return_flag=0;\n"); //Allow blocks made in the method to be called agian
  DocPrint(doc,"  STFrameDel;\n"); //Does not Free(frame data may be on stack)
  if(*m->return_class) {
     DocPrint(doc,"if(!ThingHasClass2(retval,%d)) {retval=FROG_SMALL_NIL;}",UniverseAddClass(m->return_class));
  }
//DocPrint(doc,"DbgPrint(\"LEAVE:%s,%Q\n\");",class_name,m->name);
  DocPrint(doc,"  return retval;\n");
  DocPrint(doc,"}");
  if(!class_method) {
    DocPrint(doc,"AddMethod(\"%Q\",\"%Q\",&%s);;",class_name,m->name,fun_name);
  } else {
    DocPrint(doc,"AddClassMethod(\"%Q\",\"%Q\",&%s);;",class_name,m->name,fun_name);
  }
  ReplaceElem(doc,replace,"%d",MaxI64(FramePtr("ST@@stk_depth")-6,0));
  if(LocalsIsEscaped(locals))
    ReplaceElem(doc,frame,"Bool *return_flag=STAddMethodFrame(%d,\"%Q\",\"%Q\")->return_flag;\n",m,locals->name,class_name);
  else
    ReplaceElem(doc,frame,"%Q stk_frame;MakeAnonBlockFrame(&stk_frame,%d,Fs->user_data,'Method');stk_frame._return_flag=&false;Bool *return_flag=&false;\n",locals->name,locals->cnt);
  #ifdef DEBUG
  DocWrite(doc);
  #endif
  ExeDoc(doc);
  DocDel(doc);
  Free(fun_name);
  LocalsDel(locals);
  Option(OPTf_WARN_UNUSED_VAR,old);
//DONE WITH IT
fin:
  FramePtrDel("ST@@stk_depth");
  FramePtrDel("MethodClass");
  MethodDel(m);
  } catch {
    FramePtrDel("MethodClass");
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
  if(interactive)
    lex->flags|=LEXF_CMD_LINE|LEXF_WANTS_INPUT;
  while(TRUE) {
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
      FramePtrAdd("ST@@stk_depth",0);
      DocPrint(doc,"CFrogThing *REPLFun(CFrogThing *self) {\n");
      replace=DocPrint(doc,"  CFrogThing *stk[$$LK,\"replace\"$$],*retval=FROG_SMALL_NIL;\n");
      DocPrint(doc,"CFrogThing *stk0,*stk1,*stk2,*stk3,*stk4,*stk5;\n");
      DocPrint(doc,"  static Bool st_return=FALSE;\n");
      DocPrint(doc,"  Bool *return_flag=STNewReplFrame(&st_return)->return_flag;\n");
      DocPrint(doc,"  CLocalsGeneric0 *parent_frame=Fs->user_data;\n");
      DocPrint(doc,"  I64 unwind=0,next_case=%d;\n",ast_case_num);
      MemSet(&dummy,0,sizeof CAST);
      dummy.type=AST_RETURN;
      QueInit(&dummy.args);
      QueIns(ast,dummy.args);
      CompileASTFinal(doc,&dummy,NULL,0);
      DocPrint(doc,"L%d:\n",ast_case_num++);
      DocPrint(doc,"ret:\n");
//
// Dumb hack,blocks have a reference to the retunr_flag,so reset it.
//
      DocPrint(doc,"  *return_flag=0;\n");
      DocPrint(doc,"  STFrameDel;\n");
      DocPrint(doc,"  return retval;\n");
      DocPrint(doc,"}REPLFun(FrogNil);\n");
      ReplaceElem(doc,replace,"%d",MaxI64(FramePtr("ST@@stk_depth")-6,0));
      FramePtrDel("ST@@stk_depth");
      ExeDoc(doc);
      DocDel(doc);
      ASTDel(ast);
      FrogGarbageCollect(FROG_SMALL_NIL);
    }
skip:;
  }
}
U0 STRunStmt(U8 *str) {
  STRepl(str,FALSE);
}
#include "Studio.HC";
STRunStmt(
"  #Y _ [:f=CFrogBlock | [:x=CFrogBlock | x value: x] value: [:g=CFrogBlock| f value: [:x| (g value: g) value: x] ] ]."
"  #fib _ #Y value: [:f| [:i=CFrogNum | i <= 1 ifTrue: [i] ifFalse: [(f value: i - 1) + (f value: i - 2)] ] ]."
"  (#fib value: 10 ) show ."
);
#endif
#endif
        Â         n   h   _   X   M   K   ;   7   1   *         	)   ,   9   E   P   E   ]   b      ÿÿÿÿ      5             	C   /      $I’$Iú¿oþ>ýÛô}Û·}ß¾Û¾mÚö	   	   a P   J   a  