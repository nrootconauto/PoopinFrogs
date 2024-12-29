#include "Lexer.HC";
#define AST_UNOP 1
#define AST_BINOP 2
#define AST_KEYWORD 3
#define AST_ASSIGN 4
#define AST_STR 5
#define AST_VAR 6
#define AST_ARRAY 7
#define AST_CASCADE 8
#define AST_BLOCK 9
#define AST_CHR 10
#define AST_NUM 11
#define AST_SYMBOL 12
#define AST_CASCADE_HEAD 13 //str points to cascade head
#define AST_RETURN 14
#define AST_SELF 15
#define AST_MEMBER 17
//Used by Compiler.HC
#define AST_STACK_TEMPORARY 18
//Dont Free
extern U8 *MethodReturnClass(U8 *class_name,U8 *method_name);
extern Bool HasMethod(U8 *class_name,U8 *method_name);
class CAST:CQue {
  CQue args;
  CQue body;
  I32 type,is_literal;
  I32 switch_num,is_f64; //For compiler
  union {
    U8 op_name[STR_LEN/2];
    U8 name[STR_LEN/2];
  };
  U8 var_class_name[STR_LEN/2];
  union {
    I64 stk_idx;
    F64 num;
    CAST *cascade_head;
    U8 *str;
  };
  Bool compiled;
//Used by escape analysis
  Bool refs_extern_vars;
  Bool escapes;
};
class CMethod {
  U8 name[STR_LEN];
  U8 return_class[STR_LEN];
  I64 arity;
  CQue args; //CAST
  CQue temps;
  CQue body; //CAST
};
extern U0 DumpAst(CAST *s);
extern CAST *ParseAst(CLexer *l);
extern CAST *ParseCascade(CLexer *l);
extern Bool IsSmalltalkMember(CHashClass *cls);
U0 AddToScope(U8 *name,U8 *typename) {
  U8 buf[STR_LEN];
  StrPrint(buf,"V.%s",name);
  FramePtrAdd(buf,typename);
}
U0 RemFromScope(U8 *name) {
  U8 buf[STR_LEN];
  StrPrint(buf,"V.%s",name);
  FramePtrDel(buf);
}
Bool IsVar(U8 *name) {
  U8 buf[STR_LEN];
  StrPrint(buf,"V.%s",name);
  return ToBool(HashFind(buf,Fs->hash_table,HTT_FRAME_PTR));
}
U8 *VarClass(U8 *name) {
  U8 buf[STR_LEN];
  StrPrint(buf,"V.%s",name);
  return FramePtr(buf);
}
CAST *ParseVarWithType(CLexer *l,Bool warn=FALSE) {
  CAST *ret=NULL;
  if(l->tok==TOK_NAME) {
    ret=CAlloc(sizeof CAST);
    ret->type=AST_VAR;
    StrCpy(ret->name,l->str);
    Lex(l);
    switch(l->tok) {
      case '=':
	Lex(l);
	if(l->tok==TOK_NAME) {
 	  StrCpy(ret->var_class_name,l->str);
	} else
	  LexExcept(l,"Expected a type name");
	Lex(l);
	break;
      case '*':
	Lex(l);
	break;
      default:
	if(warn) LexWarn(l,"Untyped variable!");
    }
  }
  return ret;
}
CAST *ParseLiteral(CLexer *l) {
  CAST *ret=NULL,*item;
  CHashClass *cls;
  U8 buf[STR_LEN];
  if(l->tok=='(') {
    Lex(l);
    ret=ParseCascade(l);
    if(l->tok!=')')
      LexExcept(l,"Expeted a [Redacted for GH]fuckin ')' poopbrain.");
    Lex(l);
    if(ret) ret->is_literal=TRUE;
    return ret;
  }
  if(l->tok=='#') {
    if(Lex(l)=='(') {
      ret=CAlloc(sizeof CAST);
      ret->type=AST_ARRAY;
      QueInit(&ret->body);
      QueInit(ret);
      Lex(l);
      do {
        if(l->tok==')')
	  break;
        if(!l->tok)
	  LexExcept(l,"Unexpected end of input you fuckin goatballer.");
        item=ParseLiteral(l);
        if(!item)
	  LexExcept(l,"Expected a motherfuckin array item.");
        QueIns(item,ret->body.last);
      } while(TRUE);
      Lex(l);
      ret->is_literal=TRUE;
      return ret;
    } else if(l->tok==TOK_NAME) {
      ret=CAlloc(sizeof CAST);
      ret->type=AST_SYMBOL;
      QueInit(&ret->args);
      QueInit(ret);
      StrCpy(ret->name,l->str);
      ret->is_literal=TRUE;
      item=ret;
      goto np;
    } else if(!l->tok)
      LexExcept(l,"Erection's over;Unexpected end of input.");
  } else if(l->tok=='[') {
    ret=CAlloc(sizeof CAST);
    ret->type=AST_BLOCK;
    QueInit(&ret->args);
    QueInit(&ret->body);
    QueInit(ret);
//Arguemnts Poopbrain!
    Lex(l);
    if(l->tok==':') {
      while(l->tok!='|') {
        if(l->tok==':') {
	  Lex(l);
	  item=ParseVarWithType(l,TRUE);
	  if(!item)
	    LexExcept(l,"Put away you 50 inch donkey kong shlong and give me and argument.");
	  AddToScope(item->name,item->var_class_name);
	  QueInit(&item->args);
	  QueIns(item,ret->args.last);
        } else
	  LexExcept(l,"Bitch please,expected a ':'");
      }
      Lex(l);
    }
    while(l->tok!=']') {
      item=ParseAst(l);
      if(!item)
        LexExcept(l,"Are you fucking kidding me? I need an expression here.");
      QueIns(item,ret->body.last);
      if(l->tok=='.')
        Lex(l);
    }
    for(item=ret->args.next;item!=&ret->args;item=item->next) {
      RemFromScope(item->name);
    }
    Lex(l);
    ret->is_literal=TRUE;
    return ret;
  } else if(l->tok==TOK_STR) {
    item=CAlloc(sizeof CAST);
    item->type=AST_STR;
    item->str=StrNew(l->str);
    goto np;
  } else if(l->tok==TOK_NAME) {
    item=CAlloc(sizeof CAST);
    if(!StrCmp(l->str,"self")) {
      item->type=AST_SELF;
      goto np;
    }/* else if(!StrCmp(l->str,"super")) {
      item->type=AST_SUPER;
      goto np;
    }*/
    item->type=AST_VAR;
    StrCpy(item->name,l->str);
    if(!IsVar(item->name)&&!HashFind(item->name,Fs->hash_table,HTT_CLASS)) {
      LexExcept(l,"Use of undefined var '%s'\n",item->name);
    } else if(IsVar(item->name)) {
      if(VarClass(item->name))
        StrCpy(item->var_class_name,VarClass(item->name));
    }
np:
    QueInit(&item->args);
    QueInit(item);
    Lex(l);
again:
    if(l->tok=='->') {
      ret=CAlloc(sizeof CAST);
      ret->type=AST_MEMBER;
      Lex(l);
      if(l->tok!=TOK_NAME)
        LexExcept(l,"Expected a fucking member name.");
      StrCpy(ret->name,l->str);
      if(cls=HashFind(item->var_class_name,Fs->hash_table,HTT_CLASS)) {
        if(MemberFind(l->str,cls)) {
	  cls=MemberFind(l->str,cls)->member_class;
	  if(IsSmalltalkMember(cls)) {
	    if(cls->ptr_stars_cnt==1)
	      StrCpy(ret->var_class_name,cls[-1].str);
	    else
	      StrCpy(ret->var_class_name,cls->str);
	  }
        } else {
	  LexExcept(l,"Expected a fuckin valid member(got %s,have class %s)\n",l->str,cls->str);
        }
      }
      Lex(l);
      QueInit(&ret->args);
      QueInit(ret);
      QueIns(item,&ret->args);
      ret->is_literal=TRUE;
      item=ret;
      goto again;
    }

    item->is_literal=TRUE;
    return item;    
  } else if(l->tok==TOK_CHR) {
    item=CAlloc(sizeof CAST);
    item->type=AST_CHR;
    item->name[0]=l->chr;
    item->name[1]=0;
    goto np;
  } else if(l->tok==TOK_NUM) {
    item=CAlloc(sizeof CAST);
    item->type=AST_NUM;
    item->num=l->num;
    goto np;
  }
  return NULL;
}
U0 TryAssignType(CLexer *l,CAST *a) {
  return;
  CAST *who,*cur;
  U8 *rc;
  CHashClass *cls;
  switch(a->type) {
    case AST_UNOP:
    case AST_BINOP:
    case AST_KEYWORD:
      who=a->args.next;
      if(who->var_class_name[0]&&who->var_class_name[0]!='*') {
        if(rc=MethodReturnClass(a->var_class_name,a->name)) {
	  StrCpy(a->var_class_name,rc);
        }
        if(cls=HashFind(who->var_class_name,Fs->hash_table,HTT_CLASS)) {
	  while(cls) {
	    cls-=cls->ptr_stars_cnt;
	    if(cls->str&&!StrCmp(cls->str,"CFrogThing")) {
	      if(!HasMethod(who->var_class_name,a->name)) {
	        LexWarn(l,"Coudlnt find '%s' for class '%s'.",a->name,who->var_class_name);
		break;
	      }
	    }
	    cls=cls->base_class;
	  }
        }
      }
      break;
  }
}
CAST *ParseUnop(CLexer *l,CAST *left=NULL) {
  if(!left) left=ParseLiteral(l);
  CAST *ret=NULL;
  CLexer backup;
  I64 old_pos,old_ch;
  U8 *rn;
  if(!left) return NULL;
again:
  if(l->tok==TOK_NAME) {
    MemCpy(&backup,l,sizeof CLexer);
    if(Lex(l)==':') {
      MemCpy(l,&backup,sizeof CLexer);
      return left;
    }
    ret=CAlloc(sizeof CAST);
    ret->type=AST_UNOP;
    QueInit(&ret->args);
    QueInit(ret);
    QueIns(left,&ret->args);
    StrCpy(ret->name,backup.str);
    TryAssignType(l,ret);
    left=ret;
    goto again;
  }
  return left;
}
CAST *ParseBinop(CLexer *l,CAST *left=NULL) {
  CAST *right,*ret=NULL;
  U8 *rn;
  CHashClass *cls;
  if(!left) left=ParseUnop(l);
  if(!left) return NULL;
  I64 idx;
again:
  if(l->tok!=TOK_NAME) {
    for(idx=0;l->tok.u8[idx];idx++) {
      if(!IsOperatorChr(l->tok.u8[idx])) 
        goto fail;
    }
    ret=CAlloc(sizeof CAST);
    ret->type=AST_BINOP;
    QueInit(&ret->args);
    QueInit(ret);
    QueIns(left,ret->args.last);
    StrCpy(ret->name,&l->tok);
    if(!idx) goto fail;
    Lex(l);

    right=ParseUnop(l);
    if(!right)
      LexExcept(l,"Binop needs 2 fucking operands asshole.");
    QueIns(right,ret->args.last);
    TryAssignType(l,ret);
    left=ret;
    goto again;
  }
fail:
  return left;
}
CAST *ParseKeyword(CLexer *l,CAST *left=NULL) {
  if(!left) left=ParseBinop(l);
  CAST *ret=NULL,*right;
  CLexer backup;
  U8 buf[STR_LEN],str2[STR_LEN],*rn;
  buf[0]=0;
  if(!left) return NULL;
again:
  if(l->tok==TOK_NAME) {
    MemCpy(&backup,l,sizeof CLexer);
    StrCpy(str2,l->str);
    if(Lex(l)!=':') {
      MemCpy(l,&backup,sizeof CLexer);
      return left;
    }
    CatPrint(buf,"%s:",str2);
    if(!ret) {
      ret=CAlloc(sizeof CAST);
      ret->type=AST_KEYWORD;
      QueInit(&ret->args);
      QueInit(ret);
      QueIns(left,ret->args.last);
    }
    Lex(l);
    right=ParseBinop(l);
    if(!right)
      LexExcept(l,"Where the fuck is my operand");
    QueIns(right,ret->args.last);
    goto again;
  }
  if(!StrLen(buf))
    return left;
  StrCpy(ret->name,buf);
  TryAssignType(l,ret);
  return ret;
}
CAST *ParseCascade(CLexer *l) {
  CAST *left=ParseKeyword(l),*ret=NULL,*item,*alias,*left_parent,*orig;
  if(!left) return left;
  while(l->tok==';') {
    if(!ret) {
      ret=CAlloc(sizeof CAST);
      ret->type=AST_CASCADE;
      QueInit(&ret->args);
      QueInit(ret);
//Find first literal node of left
      // Do    (Transcript) show: 1 ;show: 2
      // Don't (Transcript show:1);show: 2
      orig=left;
      left_parent=NULL;
      while(!left->is_literal) {
         left_parent=left;
        left=left->args.next;
      }
      ret->cascade_head=left;
//
//Replace left_parents reference to left with an alias,this makes the cascade head at the bottom of the stack
//
// This is needed for the Compiler.HC
//
      if(left_parent) {
        alias=CAlloc(sizeof CAST);
        alias->type=AST_CASCADE_HEAD;
        alias->str=left;
	QueIns(alias,left);
	QueRem(left);
        QueIns(left,ret->args.last);
        QueIns(orig,ret->args.last);
      }
    }
    Lex(l);
    alias=CAlloc(sizeof CAST);
    alias->type=AST_CASCADE_HEAD;
    alias->str=left;
    item=ParseKeyword(l,alias);
    if(alias!=item) {
      QueIns(item,ret->args.last);
    } else {
      item=ParseUnop(l,alias);
      if(alias!=item) {
        QueIns(item,ret->args.last);
      } else
        LexExcept(l,"Expected a fuckin cascade operation butthole.");
    }
  }
  if(!ret) return left;
  return ret;
}
CAST *ParseAst(CLexer *l) {
  CLexer backup;
  CAST *var,*right,*tmp,*assign;
  CHashClass *cls;
  U8 assign_to[STR_LEN],symbol=FALSE;
  I64 old_pos=l->pos,old_flags=l->flags,old_ch=l->last_chr;
  if(l->tok==TOK_NAME||l->tok=='#') {
    MemCpy(&backup,l,sizeof CLexer);
    if(l->tok=='#') {
      symbol=TRUE;
      if(Lex(l)!=TOK_NAME) {
        goto cont;
      }
    }
    StrCpy(assign_to,l->str);
    Lex(l);

    var=CAlloc(sizeof CAST);
    QueInit(var);
    StrCpy(var->name,assign_to);

    if(symbol)
      var->type=AST_SYMBOL;
    else {
      var->type=AST_VAR;
      if(IsVar(var->name)) {
	StrCpy(var->var_class_name,VarClass(var->name));
      } else if(StrCmp(var->name,"self")&&!HashFind(var->name,Fs->hash_table,HTT_CLASS)) {
        LexExcept(l,"I need a valid ass variable(got %s).",var->name);
      }
    }
    if(l->tok=='->') {
      tmp=CAlloc(sizeof CAST);
      tmp->type=AST_MEMBER;
      Lex(l);
      if(l->tok!=TOK_NAME)
        LexExcept(l,"Expected a fucking member name.");
      StrCpy(tmp->name,l->str);
      if(cls=HashFind(var->var_class_name,Fs->hash_table,HTT_CLASS)) {
        if(MemberFind(l->str,cls)) {
	  cls=MemberFind(l->str,cls)->member_class;
	  if(IsSmalltalkMember(cls)) {
	    if(cls->ptr_stars_cnt==1)
	      StrCpy(tmp->var_class_name,cls[-1].str);
	    else
	      StrCpy(tmp->var_class_name,"CFrogNum");
	  }
        } else {
	  LexExcept(l,"Expected a fuckin valid member(got %s,have class %s)\n",l->str,cls->str);
        }
      }
      Lex(l);
      QueInit(&tmp->args);
      QueInit(tmp);
      QueIns(var,&tmp->args);
      tmp->is_literal=TRUE;
      var=tmp;
    }

    if(l->tok=='_') {
      Lex(l);
      if(right=ParseCascade(l)) {
        assign=CAlloc(sizeof CAST);
        assign->type=AST_ASSIGN;
        QueInit(assign);
        QueInit(&assign->args);
        QueIns(var,assign->args.last);
        QueIns(right,assign->args.last);
        return assign;
      } else 
        LexExcept(l,"I want something to asign to '%s' asswipe.",assign_to);
    } else {
      Free(var);
cont:
      MemCpy(l,&backup,sizeof CLexer);
    }
  }
  if(l->tok=='^') {
    Lex(l);
    right=ParseCascade(l);
    if(!right)
      LexExcept(l,"Butt toads fiegning 4 a 50 inch gorilla dick return.");
    assign=CAlloc(sizeof CAST);
    assign->type=AST_RETURN;
    QueInit(assign);
    QueInit(&assign->args);
    QueIns(right,assign->args.last);    
    return assign;
  }
  var=ParseCascade(l);
  return var;
}

CMethod *ParseMethod(CLexer *l,CHashClass *cls=NULL,Bool deep_verbose=FALSE) {
  CMethod *m=CAlloc(sizeof CMethod);
  CAST *name,*head;
  CAST *ast;
  CHashTable *old=Fs->hash_table;
  Fs->hash_table=HashTableNew(0x100);
  Fs->hash_table->next=old;
  CMemberLst *mlst;
  CHashClass *ocls=cls;
  I64 idx;
  Bool found_ret_class=FALSE;
  FramePtrAdd("deep_verbose",deep_verbose); //Free'd with hash table
  QueInit(&m->args);
  QueInit(&m->body);
  QueInit(&m->temps);
  try {
    while(cls) {
      if(!StrCmp(cls->str,"CFrogThing"))
        break;
      for(mlst=cls->member_lst_and_root;mlst;mlst=mlst->next) {
        if(IsSmalltalkMember(mlst->member_class)) {
	  if(mlst->member_class->ptr_stars_cnt==1)
	    AddToScope(mlst->str,mlst->member_class[-1].str);
	  else
	    AddToScope(mlst->str,"CFrogNum");
	}
      }
      cls=cls->base_class;
    }
    while(TRUE) {
      if(l->tok=='|') {
        break;
      }
check:
      if(l->tok=='->') {
        found_ret_class=TRUE;
        Lex(l);
        if(l->tok!=TOK_NAME&&l->tok!='*')
	  LexExcept(l,"Expected a return type");
        if(l->tok==TOK_NAME)
	  StrCpy(m->return_class,l->str);
        if(Lex(l)!='|')
	  LexExcept(l,"Expected a '|'!");
        break;
      }
      if(l->tok=='->*') {
        found_ret_class=TRUE;
        if(Lex(l)!='|')
	  LexExcept(l,"Expected a '|'!");
        break;
      }
      if(l->tok==TOK_NAME) {
        CatPrint(m->name,"%s",l->str);

        if(Lex(l)==':') {
	  CatPrint(m->name,":"); 
	  m->arity++;
	  Lex(l);
	  name=ParseVarWithType(l,TRUE);
	  if(!name) LexExcept(l,"Expected a name here");
	  AddToScope(name->name,name->var_class_name);
	  QueIns(name,m->args.last);
        } else if(m->arity>1) {
	  LexExcept(l,"I expected a ':' asswipe.");
        } else {// is unop
	  if(l->tok=='->'||l->tok=='->*')
	    goto check;
	  if(l->tok!='|') 
	    LexExcept(l,"This is an unop fucktard");
	  else
	    break;
        }
      } else {
        for(idx=0;l->tok.u8[idx];idx++) {
	  CatPrint(m->name,"%c",l->tok.u8[idx]);
	  if(!IsOperatorChr(l->tok.u8[idx])) 
	    LexExcept(l,"Expected a operator/method name here poo poo brain.");
        }
        if(Lex(l)==TOK_NAME) {
	  name=CAlloc(sizeof CAST);
	  StrCpy(name->name,l->str);
	  AddToScope(name->name,"*");
	  QueIns(name,m->args.last);
	  m->arity++;
	  if(l->tok=='->'||l->tok=='->*')
	    goto check;
	  if(Lex(l)!='|')
	    LexExcept(l,"Expected a fuckin '|'.");
	  break;
        } else
	  LexExcept(l,"I fuckin need uh argument name asshole.");
      }
    }
    if(!found_ret_class) LexWarn(l,"Untyped return class!");
    Lex(l);
    while(TRUE) {
      if(l->tok==TOK_NAME) {
        name=ParseVarWithType(l,TRUE);
        AddToScope(name->name,name->var_class_name);
        QueIns(name,m->temps.last);
      } else if(l->tok=='|') {
        Lex(l);
        break;
      } else
        LexExcept(l,"Go stupid and give me a fucking temporary name.");
    }

    while(l->tok) {
      if(ast=ParseAst(l)) {
        QueIns(ast,m->body.last);
        while(l->tok=='.')
	  Lex(l);
      } else
        LexExcept(l,"Expected a fuckin statement.");
    }
    head=&m->args;
    for(name=head->next;name!=head;name=name->next)
      RemFromScope(name->name);
    head=&m->temps;
    for(name=head->next;name!=head;name=name->next)
      RemFromScope(name->name);

    cls=ocls;
    while(cls) {
      if(!StrCmp(cls->str,"CFrogThing"))
        break;
      for(mlst=cls->member_lst_and_root;mlst;mlst=mlst->next)
        if(IsSmalltalkMember(mlst->member_class))
	  RemFromScope(mlst->str);
      cls=cls->base_class;
    }
    HashTableDel(Fs->hash_table);
    Fs->hash_table=old;
  } catch  {
    HashTableDel(Fs->hash_table);
    Fs->hash_table=old;
  }
  return m;
}
U0 DumpAst(CAST *s) {
  CAST *cur,*head;
"$$ID,2$$";
  switch(s->type) {
    case AST_ARRAY:
        "ARRAY\n";
        head=&s->body;
        for(cur=head->next;cur!=head;cur=cur->next)
	  DumpAst(cur);
	break;
    start:
      case AST_MEMBER:
        "->%s\n",s->name;
	break;
      case AST_RETURN:
        "RETURN\n";
	break;
      case AST_CASCADE:
        "CASCADE\n";
	break;
      case AST_UNOP:
        "UNOP:%s\n",s->name;
        break;
      case AST_BINOP:
        "BINOP:%s\n",s->name;
        break;
      case AST_KEYWORD:
        "KW:%s\n",s->name;
        break;
      case AST_BLOCK:
        "BLOCK\n";
	break;
      case AST_ASSIGN:
        "_\n";
        break;
    end:
      head=&s->args;
      for(cur=head->next;cur!=head;cur=cur->next) {
        DumpAst(cur);
      }
      if(s->type==AST_BLOCK) {
        head=&s->body;
        for(cur=head->next;cur!=head;cur=cur->next)
	  DumpAst(cur);
      }
      break;
    case AST_SELF:
      "SELF\n";
      break;
    case AST_STR:
      "STR:\"%Q\"\n",s->str;
      break;
    case AST_VAR:
      "VAR:%s\n",s->name;
      break;
    case AST_SYMBOL:
      "SYM:%s\n",s->name;
      break;
    case AST_CHR:
      "CHR:%s\n",s->name;
      break;
//#define AST_CASCADE 8
    case AST_NUM:
      "NUM:%n\n",s->num;
      break;
  }
"$$ID,-2$$";
}
U0 ASTDel(CAST *ast) {
  CAST *head,*cur,*next;
  switch(ast->type) {
    case AST_BLOCK:
      head=&ast->args;
      for(cur=head->next;cur!=head;cur=next) {
        next=cur->next;
        ASTDel(cur);
      }
    case AST_ARRAY:
      head=&ast->body;
      for(cur=head->next;cur!=head;cur=next) {
        next=cur->next;
        ASTDel(cur);
      }
      break;
    case AST_RETURN:
    case AST_CASCADE:
    case AST_UNOP:
    case AST_BINOP:
    case AST_KEYWORD:
    case AST_ASSIGN:
      head=&ast->args;
      for(cur=head->next;cur!=head;cur=next) {
        next=cur->next;
        ASTDel(cur);
      }
      break;
  }
  QueRem(ast);
  Free(ast);
}
U0 MethodDel(CMethod *m) {
  CAST *head,*cur,*next;
  QueDel(&m->args);
  QueDel(&m->temps);
  head=&m->body;
  for(cur=head->next;cur!=head;cur=next) {
    next=cur->next;
    ASTDel(cur);
  }
  Free(m);  
}
CLexer *l=LexerNew("123.4->x + 456.789 +(3 + 4) add: 100 sqrt to: 1");
CLexer *l=LexerNew("1 -> xyz _123 ");
Lex(l);
DumpAst(ParseAst(l));
/*CLexer *l=LexerNew("^ (#Window new) + 2 ; open ; addButton: 'hi' ");
Lex(l);
DumpAst(ParseAst(l));
CLexer *l=LexerNew("Method: a  |b c_c|
  a ifTrue: [ ^ 'poop' ] .
  ^ a+b+c_c -self Method: super
");
Lex(l);
CMethod *m=ParseMethod(l);
DumpAst(m->body.next);
DumpAst(m->body.last);
 */