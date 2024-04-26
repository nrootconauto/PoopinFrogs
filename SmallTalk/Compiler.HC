#ifndef ST_COMPILER_HH
#define ST_COMPILER_HH 1
#include "RunTime.HC";
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
  if(parent->type=='Block'||parent->type=='Method')
    FrogIncRefCnt(parent);
  fr->return_flag=parent->return_flag;
  return fr;
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
  CHashGeneric3 *g=HashFind(var,l->vars,HTT_FRAME_PTR);
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
CFrogThing *Useless(CFrogThing *, ...) {
  return FROG_SMALL_NIL;
}
U0 GenerateMethodCall(CDoc *doc,U8 *class_name,U8 *method_name) {
  CHashGeneric *gen;
//See AddMethod
  U8 *canon=MStrPrint("METHOD_%s.%s",class_name,method_name);
  if(!FramePtr(canon)) {
    FramePtrAdd(canon,&Useless);
  }
  gen=HashFind(canon,Fs->hash_table,HTT_FRAME_PTR);
  if(!StrCmp("CFrogNum",class_name)) {
//Checking numbers will be too tiresome
    if(gen->user_data0!=&Useless)
      DocPrint(doc,"CallPtr(%d,NULL,",gen->user_data0,class_name);
    else
      DocPrint(doc,"CallPtr(%d(I64**)[0],NULL,",&gen->user_data0,class_name);
  } else {
    if(gen->user_data0!=&Useless)
      DocPrint(doc,"CallPtr(%d,\"%Q\",",gen->user_data0,class_name);
    else
      DocPrint(doc,"CallPtr(%d(I64**)[0],\"%Q\",",&gen->user_data0,class_name);
  }
  Free(canon);

}
U0 GenerateUselessMethod(U8 *class_name,U8 *method_name)  {
  U8 *canon=MStrPrint("METHOD_%s.%s",class_name,method_name);
  if(!FramePtr(canon)) {
    FramePtrAdd(canon,&Useless);
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
  I64 idx,off=0;
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
        if(RawAccessType(for_class,mlst->str)) {
	  gen->user_data1=TRUE;
          gen->user_data3="CFrogNum";
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
      gen=CAlloc(sizeof CHashGeneric3);
      gen->type=HTT_FRAME_PTR;
      gen->user_data0=off++;
      gen->str=StrNew(name->name);
      HashAdd(gen,ret->vars);
      DocPrint(dummy,"  CFrogThing *%s;\n",gen->str);
      gen->user_data3=name->var_class_name;
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
  CHashGeneric3 *gen;
  StrPrint(ret->name,"CThunkLocals@%d",cnt++);
  ret->vars=HashTableNew(0x10);
  CAST *name,*head;
  I64 off=0;
  DocPrint(dummy,"class %s:CLocalsGeneric0 {\n",ret->name);
  head=&thunk->args;
  for(name=head->next;name!=head;name=name->next) {
    gen=CAlloc(sizeof CHashGeneric3);
    gen->type=HTT_FRAME_PTR;
    gen->user_data0=off++;
    gen->user_data3=name->var_class_name;
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
  U8 *ret;
  I64 idx,thunk_idx=thunk_cnt++;
  CDoc *doc=DocNew;
  CDocEntry *replace;
  CLocals *locals=GenerateLocalsFromThunk(block);
  locals->next=parent;
  CAST *var,*head;
  FramePtrAdd("ST@@stk_depth",0);
  DocPrint(doc,"CFrogThing *Thunk@@%d(CFrogThing *self,CLocalsGeneric0 *parent_frame,...) {\n",thunk_idx);
  replace=DocPrint(doc,"  CFrogThing *stk[$$LK,\"replace_me\"$$],*retval=FROG_SMALL_NIL,**tmp;\n");
  DocPrint(doc,"CFrogThing *stk0,*stk1,*stk2,*stk3,*stk4,*stk5;\n");
  DocPrint(doc,"  Bool false=FALSE;\n");
  DocPrint(doc,"  Bool *return_flag=STNewBlockFrame(\"%Q\",parent_frame)->return_flag;\n",locals->name,block);
  DocPrint(doc,"  if(!return_flag) return_flag=&false;\n");
  DocPrint(doc,"  parent_frame=Fs->user_data;\n");
  DocPrint(doc,"  I64 unwind=0;I64 next_case=%d;\n",ast_case_num);
  head=&block->args;
  idx=0;
  for(var=head->next;var!=head;var=var->next) {
    DocPrint(doc,"  tmp=BungisReduce(self,&");
    STGetLocal(doc,locals,var->name);
    DocPrint(doc,");\n");
    DocPrint(doc,"  *tmp=argv[%d];\n",idx);
    idx++;
  }

  head=&block->body;
  DocPrint(doc,"enter:");
  DocPrint(doc,"  if(*return_flag||ThingIsError(retval)) {goto ret;} \n");
  DocPrint(doc,"switch(next_case) {\n");
  for(var=head->next;var!=head;var=var->next) {
    if(var->type!=AST_STR) {
      CompileASTFinal(doc,var,locals,0);
    }
  }

  head=&block->args;
  idx=0;
  DocPrint(doc,"}\n");
  DocPrint(doc,"ret:\n");
  DocPrint(doc,"  while(--unwind>=0) ThingDel(stk[unwind]);");
  DocPrint(doc,"  STFrameDel;\n");
  DocPrint(doc,"  return stk0;\n");
  DocPrint(doc,"};");
  ReplaceElem(doc,replace,"%d",MaxI64(FramePtr("ST@@stk_depth")-6,0));
  ret=DocSave(doc);//Saves to string
  ExePutS(ret);
  Free(ret);
  DocDel(doc);
  FramePtrDel("ST@@stk_depth");
  return MStrPrint("Thunk@@%d",thunk_idx);
}
U0 DftCall(CDoc *doc,CLocals *l,CAST *ast,I64 stack_depth,U8 *op,I64 cnt=2) {
  U8 *cls_name;
  CAST *self=ast->args.next;
  if(self->type==AST_VAR) {
    if(cls_name=VarHasMethod(l,self->name,op)) {
      DocPrint(doc,"  retval=");
      GenerateMethodCall(doc,cls_name,op);
      goto args;
    }
  } else if(self->is_f64) {
    cls_name=ClassHasMethod("CFrogNum",op);
try_class:
    if(cls_name) {
      DocPrint(doc,"  retval=");
      GenerateMethodCall(doc,cls_name,op);
      goto args;
    }
  } else if(self->type==AST_BLOCK) {
    cls_name=ClassHasMethod("CFrogBlock",op);
    goto try_class;
  } else if(self->type==AST_ARRAY) {
    cls_name=ClassHasMethod("CFrogArray",op);
    goto try_class;
  }
//TODO static return-type of method
  I64 idx;
  DocPrint(doc,"  retval=CallScriptFast(\n");
  DocPrint(doc,"  #exe{ExeKey2StringLiteral(\"%s\");},\n",op);
  DocPrint(doc,"  #exe{ExeKey2StringLiteral(\".%s\");},\n",op);
args:
  DocPrint(doc,"%s\n",StackFrame2Var(stack_depth));
  for(idx=0;idx<cnt;idx++) {
    DocPrint(doc,",");
    DocPrint(doc,"%s",StackFrame2Var(stack_depth+1+idx));
 }
  DocPrint(doc,");\n");
  DocPrint(doc,"ThingDel(%s);\n",StackFrame2Var(stack_depth));
  DocPrint(doc,"  %s=retval;\n",StackFrame2Var(stack_depth));
}
Bool IsAllF64(CAST *ast) {
  if(!ast->is_f64) return FALSE;
  CAST *head=&ast->args,*cur=head->next;
  while(head!=cur) {
    if(!IsAllF64(cur)) return FALSE;
    cur=cur->next;
  }
  return TRUE;
}
Bool IsF64ExprNode(CLocals *l,CAST *ast) {
  U8 *cn;
  CAST *a,*b;
  switch(ast->type) {
    case AST_NUM:
      return ast->is_f64=TRUE;
    case AST_VAR:
      if(cn=VarClassName(l,ast->name))
        return ast->is_f64=!StrCmp(cn,"CFrogNum");
      return FALSE;
   case AST_UNOP:
     a=ast->args.next;
     if(IsF64ExprNode(l,a))
       return ast->is_f64=ClassHasMethod("CFrogNum",ast->op_name);
     return FALSE;
   case AST_BINOP:
     a=ast->args.next;
     b=ast->args.last;
     if(IsF64ExprNode(l,a)&&IsF64ExprNode(l,b))
       return ast->is_f64=ClassHasMethod("CFrogNum",ast->op_name);
     return FALSE;
   case AST_KEYWORD:
     a=&ast->args;
     for(b=a->next;a!=b;b=b->next) {
       if(!IsF64ExprNode(l,b)) return FALSE;
     }
     return ast->is_f64=ClassHasMethod("CFrogNum",ast->op_name);
  }
  return FALSE;
}
U0 NumPrimDft(CDoc *doc,CLocals *l,CAST *ast,I64 stack_depth) {
  CAST *head=&ast->args,*cur;
  I64 idx=0;
  ast->is_f64=TRUE;
  DocPrint(doc,"AsF64(");
  GenerateMethodCall(doc,"CFrogNum",ast->name);
  for(cur=head->next;cur!=head;cur=cur->next) {
    DocPrint(doc,"FrogNumNew(");
    CompileAST(doc,cur,l,stack_depth);
    DocPrint(doc,")");
    if(cur->next!=head)
      DocPrint(doc,",");
 }
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
}
U0 NumPrim1(CDoc *doc,CLocals *l,CAST *ast,I64 stack_depth,U8 *op,U8 *alt_name=NULL) {
  if(!alt_name) alt_name=op;
  CDoc *tmp;
  U8 *save;
  CAST *a=ast->args.next;
  DocPrint(doc,"(%s(",op);
  CompileAST(doc,a,l,stack_depth,,TRUE);
  DocPrint(doc,"))");
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
    DocPrint(doc,"case %d:\n",bl->switch_num);
  }
  DocPrint(doc,"  retval=FrogBlockValue(%s);",StackFrame2Var(stack_depth));
  DocPrint(doc,"  %s=retval;\n",StackFrame2Var(stack_depth));
  if(jump_to==INVALID_PTR)
    DocPrint(doc,"next_case=%d;goto enter;\n",ast_case_num);
  else
    DocPrint(doc,"next_case=%d;goto enter;\n",jump_to);
}
U0 CompileAST(CDoc *doc,CAST *ast,CLocals *locals,I64 stack_depth,I64 jump_to=INVALID_PTR,Bool allow_f64=FALSE) {
  U8 dummy[STR_LEN];
  I64 cnt,idx;
  CDocEntry *ent,*ent2;
  CAST *cur,*cur2;
  U8 *thunk_name;
  U8 *raw_class_name;
  U8 *conv_name;
  CMemberLst *mlst;
  if(allow_f64) {
    ast->is_f64=IsF64ExprNode(locals,ast);
  }
  switch(ast->type) {
      break;case AST_UNOP:
      cnt=0;
pass:
//Skip past object we are calling to
      cur=ast->args.next->next;

      if(!StrCmp(ast->op_name,"whileTrue:")) {
        idx=ast_case_num;
        UnrollBlock(doc,locals,stack_depth,ast->args.next);
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"case %d:\n",ast->switch_num);
        ent=DocPrint(doc,"if(AsF64(%s)==0.) {next_case=$$LK,\"dummy1\"$$;goto enter;}",StackFrame2Var(stack_depth));
        UnrollBlock(doc,locals,stack_depth,ast->args.last,idx);
        ReplaceElem(doc,ent,"%d",ast_case_num);
	return;
      }
      if(!StrCmp(ast->op_name,"whileFalse:")) {
        idx=ast_case_num;
        UnrollBlock(doc,locals,stack_depth,ast->args.next);
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"case %d:\n",ast->switch_num);
        ent=DocPrint(doc,"if(AsF64(%s)) {next_case=$$LK,\"dummy2\"$$;goto enter;}",StackFrame2Var(stack_depth));
        UnrollBlock(doc,locals,stack_depth,ast->args.last,idx);
        ReplaceElem(doc,ent,"%d",ast_case_num);
	return;
	break;
      }
      if(!StrCmp(ast->op_name,"ifTrue:")) {
        cur=ast->args.next;
        CompileAST(doc,cur,locals,stack_depth,,FALSE); //TODO allow f64
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"case %d:\n",ast->switch_num);
        ent=DocPrint(doc,"if(AsF64(%s)==0.) {next_case=$$LK,\"dummy3\"$$;goto enter;}",StackFrame2Var(stack_depth));
        UnrollBlock(doc,locals,stack_depth,ast->args.next->next);
        ReplaceElem(doc,ent,"%d",ast_case_num);
	break;
      }
      if(!StrCmp(ast->op_name,"ifFalse:")) {
        cur=ast->args.next;
        CompileAST(doc,cur,locals,stack_depth,,0); //TODO allow f64
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"case %d:\n",ast->switch_num);
        ent=DocPrint(doc,"if(AsF64(%s)) {next_case=$$LK,\"dummy4\"$$;goto enter;}",StackFrame2Var(stack_depth));
        UnrollBlock(doc,locals,stack_depth,ast->args.next->next);
        ReplaceElem(doc,ent,"%d",ast_case_num);
	break;
      }
      if(!StrCmp(ast->op_name,"ifTrue:ifFalse:")) {
        cur=ast->args.next;
        CompileAST(doc,cur,locals,stack_depth,,0); //TODO allow f64
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"case %d:\n",ast->switch_num);
        ent=DocPrint(doc,"if(AsF64(%s)==0.) {next_case=$$LK,\"dummy5\"$$;goto enter;}",StackFrame2Var(stack_depth));
        UnrollBlock(doc,locals,stack_depth,ast->args.next->next);
//Make a dummy switch statement that delegates to end
        DocPrint(doc,"case %d:\n",ast_case_num++);
        ent2=DocPrint(doc,"next_case=$$TX+CX,\"dummy6\"$$;goto enter;");
        ReplaceElem(doc,ent,"%d",ast_case_num);
        UnrollBlock(doc,locals,stack_depth,ast->args.last);
        ReplaceElem(doc,ent2,"%d",ast_case_num);
	break;
      }

      //Primtive method time
      if(!IsAllF64(ast)) { //These(is_f64) are computed beforehand
        cur=ast->args.next;
//Compile non-numbers first
        for(idx=0;idx<cnt+1;idx++) { //+1 includes self
	  if(!IsF64ExprNode(locals,cur))
	    CompileAST(doc,cur,locals,stack_depth+idx,,FALSE);
	  cur=cur->next;
        }
///Compile F64 after the label prolog
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"case %d:\n",ast->switch_num);

        cur=ast->args.next;
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
        if(!StrCmp(ast->op_name,"round")) {
	  NumPrim1(doc,locals,ast,stack_depth,"Round","round");
	  goto prim_skip;
        }
        if(!StrCmp(ast->op_name,"raisedTo:")) {
	  NumPrim2(doc,locals,ast,stack_depth,"`","raisedTo:");
	  goto prim_skip;
        }
	NumPrimDft(doc,locals,ast,stack_depth);
        goto prim_skip;
      }
//
      DftCall(doc,locals,ast,stack_depth,ast->op_name,cnt);
      break;
prim_skip:
      return;
      break;case AST_BINOP:
      cnt=1;
      goto pass;
      break;case AST_SYMBOL:
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"case %d:\n",ast->switch_num);
      DocPrint(doc,"  %s=FrogSymbolValueGet(\"%Q\");\n",StackFrame2Var(stack_depth),ast->name);
      break;case AST_KEYWORD:
      cnt=StrOcc(ast->op_name,':');
      goto pass;
      break;case AST_ASSIGN:
      CompileAST(doc,ast->args.last,locals,stack_depth);
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"case %d:\n",ast->switch_num);
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
      DocPrint(doc,"  stk0=retval=FROG_SMALL_NIL;\n");
      break;case AST_STR:
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"case %d:\n",ast->switch_num);
      DocPrint(doc,"  %s=FrogStrNew(\"%Q\");\n",StackFrame2Var(stack_depth),ast->str);
      break;case AST_VAR:
      if(ast->is_f64) {
	conv_name="ToF64";
      } else {
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"case %d:%s=\n",ast->switch_num,StackFrame2Var(stack_depth));
	conv_name="FrogNumNew";
      }
      if(STHasLocal(locals,ast->name)) {
	idx=VarClassName(locals,ast->name);
        if(STIsSelfMember(locals,ast->name)) {
	  mlst=MemberFind(ast->name,HashFind(FramePtr("MethodClass"),frog_mem_task->hash_table,HTT_CLASS));
	  if(STIsRawMember(locals,ast->name)) {
	    raw_class_name=RawAccessType(FramePtr("MethodClass"),ast->name);
//ToF64 turns an I64(forced) into an F64
	    if(ast->is_f64&&!StrCmp(raw_class_name,"F64"))
		conv_name="";
	    DocPrint(doc,"  %s((ToI64(FrogUnSuper(self))+%d)(%s*)[0])",conv_name,mlst->offset,raw_class_name);
          } else {
	    if(ast->is_f64)
	      DocPrint(doc,"AsF64(");
	    DocPrint(doc,"  FrogIncRefCnt((ToI64(FrogUnSuper(self))+%d)(CFrogThing**)[0])",mlst->offset);
	    if(ast->is_f64)
	      DocPrint(doc,")");
          }
        } else if(!STIsRawMember(locals,ast->name)) {
	    if(ast->is_f64)
	      DocPrint(doc,"AsF64(");
	  DocPrint(doc,"FrogIncRefCnt(*BungisReduce(self,&");
	  STGetLocal(doc,locals,ast->name);
	  DocPrint(doc,"))\n");
	    if(ast->is_f64)
	      DocPrint(doc,")");
        } else {
	  raw_class_name=RawAccessType(FramePtr("MethodClass"),ast->name);
//ToF64 turns an I64(forced) into an F64
	  if(ast->is_f64&&!StrCmp(raw_class_name,"F64"))
	    conv_name="";
	  DocPrint(doc,"%s(BungisReduce(self,&",conv_name);
	  STGetLocal(doc,locals,ast->name);
	  DocPrint(doc,")(%s*)[0])",raw_class_name);
        }
      } else 
        DocPrint(doc,"  %s=STGetVar(self,\"%Q\");\n",StackFrame2Var(stack_depth),ast->name);
      if(!ast->is_f64) DocPrint(doc,";");
      else return;
      break;case AST_ARRAY:
      stack_depth++;
      idx=0;
      for(cur=ast->body.next;cur!=&ast->body;cur=cur->next) {
        CompileAST(doc,cur,locals,stack_depth+idx++);
      }
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"case %d:\n",ast->switch_num);
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
      DocPrint(doc,"case %d:\n",ast->switch_num);
      thunk_name=CompileThunk(ast,locals);
      DocPrint(doc,"  %s=FrogBlockNew(&%s,parent_frame,self);\n",StackFrame2Var(stack_depth),thunk_name);
      Free(thunk_name);
      break;case AST_CHR:
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"case %d:\n",ast->switch_num);
      DocPrint(doc,"  %s=FrogChrNew(%d);\n",StackFrame2Var(stack_depth),ast->name[0](U64));
      break;case AST_CASCADE_HEAD:
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"case %d:\n",ast->switch_num);
      DocPrint(doc,"  %s=FrogIncRefCnt(%s)\n;",StackFrame2Var(stack_depth),StackFrame2Var(FramePtr("?CascadeDepth"))); 
      break;case AST_SUPER:
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"case %d:\n",ast->switch_num);
      DocPrint(doc,"  %s=FrogSuper(self);\n",StackFrame2Var(stack_depth),stack_depth);
      break;case AST_SELF:
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"case %d:\n",ast->switch_num);
      DocPrint(doc,"  %s=FrogIncRefCnt(self);\n",StackFrame2Var(stack_depth)); 
      break;case AST_NUM:
      if(!ast->is_f64) { 
        ast->switch_num=ast_case_num++;
        DocPrint(doc,"case %d:\n",ast->switch_num);
        DocPrint(doc,"  %s=FrogNumNew(%n);\n",StackFrame2Var(stack_depth),ast->num); 
      } else {
        DocPrint(doc,"%n",ast->num);
        return;
      }
      break;case AST_RETURN:
      cur=ast->args.next;
      CompileAST(doc,cur,locals,stack_depth,,FALSE);
      ast->switch_num=ast_case_num++;
      DocPrint(doc,"case %d:\n",ast->switch_num);
      DocPrint(doc,"  return_flag[0]=TRUE;\n");
      DocPrint(doc,"  retval=%s;\n  unwind=%d;\n  goto ret;\n",StackFrame2Var(stack_depth),stack_depth);
      break; 
    default:
      throw('fuck');
  }
  if(jump_to!=INVALID_PTR)
    DocPrint(doc,"next_case=%d;\n",jump_to);
  else
    DocPrint(doc,"next_case=%d;\n",ast_case_num);
  DocPrint(doc,"goto enter;\n");
}
U0 CompileToHolyC(U8 *src,U8 *class_name,U8 *src_path=NULL,Bool class_method=FALSE,Bool register_method=FALSE) {
  FramePtrAdd("MethodClass",class_name);
  Bool old=Option(OPTf_WARN_UNUSED_VAR,FALSE);
  CDoc *doc=DocNew;
  static I64 fun_num=0;
  U8 *ret,*fun_name;
  CDocEntry *replace;
  I64 idx;
  CAST *var,*head;
  CLexer *lex=LexerNew(src,src_path);
  Lex(lex);
  FramePtrAdd("ST@@stk_depth",0);
  CMethod *m=ParseMethod(lex,HashFind(class_name,frog_mem_task->hash_table,HTT_CLASS));
  LexerDel(lex);
  if(register_method) {
    GenerateUselessMethod(class_name,m->name);
    goto fin;
  }
  CLocals *locals=GenerateLocalsFromMethod(m,class_name);
//MUST SET THIS
  fun_name=MStrPrint("%s@%d",class_name,fun_num++);
  DocPrint(doc,"CFrogThing *%s(CFrogThing *self,...) {\n",fun_name);
  replace=DocPrint(doc,"  CFrogThing *stk[$$LK,\"replace\"$$],*retval=FROG_SMALL_NIL,**tmp;\n");
  DocPrint(doc,"CFrogThing *stk0,*stk1,*stk2,*stk3,*stk4,*stk5;\n");
  DocPrint(doc,"  Bool *return_flag=STAddMethodFrame(%d,\"%Q\",\"%Q\")->return_flag;\n",m,locals->name,class_name);
  DocPrint(doc,"  CLocalsGeneric0 *parent_frame=Fs->user_data;\n");
  DocPrint(doc,"  I64 unwind=0,next_case=%d;\n",ast_case_num);
  head=&m->args;
  idx=0;
  for(var=head->next;var!=head;var=var->next) {
    DocPrint(doc,"  tmp=BungisReduce(self,&");
    STGetLocal(doc,locals,var->name);
    DocPrint(doc,");\n");
    DocPrint(doc,"  *tmp=argv[%d];\n",idx);
    idx++;
  }
  head=&m->body;
  DocPrint(doc,"enter:");
  DocPrint(doc,"  if(*return_flag||ThingIsError(retval)) {goto ret;} \n");
  DocPrint(doc,"switch(next_case) {\n");
  for(var=head->next;var!=head;var=var->next) {
    if(var->type!=AST_STR) {
      CompileASTFinal(doc,var,locals,0);
    }
  }
  head=&m->args;
  idx=0;
  DocPrint(doc,"}ret:\n");
  DocPrint(doc,"  while(--unwind>=0) ThingDel(stk[unwind]);");
  DocPrint(doc,"  *return_flag=0;\n"); //Allow blocks made in the method to be called agian
  DocPrint(doc,"  STFrameDel;\n");
  DocPrint(doc,"  return retval;\n");
  DocPrint(doc,"}");
  if(!class_method) {
    DocPrint(doc,"AddMethod(\"%Q\",\"%Q\",&%s);;",class_name,m->name,fun_name);
  } else {
    DocPrint(doc,"AddClassMethod(\"%Q\",\"%Q\",&%s);;",class_name,m->name,fun_name);
  }
  ReplaceElem(doc,replace,"%d",MaxI64(FramePtr("ST@@stk_depth")-6,0));
  ret=DocSave(doc);
  ExePutS(ret);
  DocDel(doc);
  Free(fun_name);
  Free(ret);
  LocalsDel(locals);
  Option(OPTf_WARN_UNUSED_VAR,old);
//DONE WITH IT
fin:
  FramePtrDel("ST@@stk_depth");
  MethodDel(m);
  FramePtrDel("MethodClass");
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
      dummy.type=AST_RETURN;
      QueInit(&dummy.args);
      QueIns(ast,dummy.args);
      DocPrint(doc,"enter:");
      DocPrint(doc,"  if(*return_flag||ThingIsError(retval)) {goto ret;} \n");
      DocPrint(doc,"switch(next_case) {\n");
      CompileASTFinal(doc,&dummy,NULL,0);
      DocPrint(doc,"}");
      DocPrint(doc,"ret:\n");
//
// Dumb hack,blocks have a reference to the retunr_flag,so reset it.
//
      DocPrint(doc,"  *return_flag=0;\n");
      DocPrint(doc,"  while(--unwind>=0) ThingDel(stk[unwind]);");
      DocPrint(doc,"  STFrameDel;\n");
      DocPrint(doc,"  return retval;\n");
      DocPrint(doc,"}REPLFun(FrogNil);\n");
      ReplaceElem(doc,replace,"%d",MaxI64(FramePtr("ST@@stk_depth")-6,0));
      FramePtrDel("ST@@stk_depth");
      str=DocSave(doc);
      ExePutS(str);
      Free(str);
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
#include "Studio.HC";;
STRunStmt(
"  #Y _ [:f=CFrogBlock | [:x=CFrogBlock | x value: x] value: [:g=CFrogBlock| f value: [:x| (g value: g) value: x] ] ]."
"  #fib _ #Y value: [:f| [:i=CFrogNum | i <= 1 ifTrue: [i] ifFalse: [(f value: i - 1) + (f value: i - 2)] ] ]."
"  (#fib value: 10 ) show ."
);
#endif
#endif