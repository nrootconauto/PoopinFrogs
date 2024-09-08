//Compiler goes to parent directory as it is the "main" file 
#include "Compiler.HC";
#exe {Cd(__DIR__);};
#include "../BlobFile.HC";
#exe {Cd(__DIR__);};
#define STS_ADD_CLASS -100
#define STS_METHOD_HELP -101
#define ST_ROOT	"SmallTalk/" //Must be same length
#define ST_CLASS_ROOT	"STClsRoot/"
#define ST_SCRIPT_ROOT	"STScripts/"
extern U0 LoadMethodsFromBlob(U8 *blob_file=NULL,Bool dry_only=FALSE);
U8 *LumpNameToPath(U8 *str) {
  str+=StrLen(ST_ROOT);
  if(StrOcc(str,'/')) {
    str=StrNew(str);
    *StrLastOcc(str,"/")=0;
  } else
    str=StrNew(str);
  return str;
}
U0 SanitizeStr(U8 *tmp) {
  U8 *tmp2;
  I64 len,idx2;
  len=StrLen(tmp);
  tmp2=tmp;
  for(idx2=0;idx2!=len;idx2++) {
//Raw DolDoc editor likes to put in weird charactyors
    if(tmp[idx2]=='\n'||Bt(char_bmp_displayable,tmp[idx2])) {
      *tmp2++=tmp[idx2];
    }
  }
  *tmp2=0;
}
U0 STSyntaxHighlight(CDoc *out,U8 noreg *txt,Bool clear=TRUE) {
  if(clear) DocClear(out);
  I64 noreg lpos=0,off;
  I64 nest_depth=0;
  SanitizeStr(txt);
//Newline in case our lexer eats the 0
  txt=MStrPrint("%s\n",txt);
  CLexer *l=LexerNew(txt);
  l->flags=LEXF_SILENT;
  try {
again:
    switch(Lex(l)) {
      case 0 :
        DocPrint(out,"$$FD$$");
//Flush whitespace
        while(lpos!=l->pos) {
          if(txt[lpos]=='\d')
	    DocPrint(out,"$$$$",txt[lpos++]);
          else
	  DocPrint(out,"%c",txt[lpos++]);
	}
        LexerDel(l);
	return;
      start:
      case TOK_STR:
        DocPrint(out,"$$LTRED$$");
	break;
      case TOK_CHR:
        DocPrint(out,"$$LTRED$$");
	break;
      case TOK_NUM:
        DocPrint(out,"$$BROWN$$");
	break;
      case TOK_NAME:
        DocPrint(out,"$$BLUE$$");
	break;
      case '(':
      case '[':
        if(nest_depth&1)
          DocPrint(out,"$$RED$$");
	else
          DocPrint(out,"$$GREEN$$");
        nest_depth++;
	break;
      case ')':
      case ']':
        nest_depth--;
        if(nest_depth&1)
          DocPrint(out,"$$RED$$");
	else
          DocPrint(out,"$$LTGREEN$$");
	break;
      default:
        DocPrint(out,"$$FD$$");
	break;
      end:
	off=0;
	if(l->flags&(1<<LEXf_USE_LAST_CHAR))
	  off=-1;
        while(lpos<l->pos+off) {
          if(txt[lpos]=='\d')
	    DocPrint(out,"$$$$",txt[lpos++]);
          else 
	    DocPrint(out,"%c",txt[lpos++]);
	}
        goto again;
    }
  } catch {
//Flush remaining
    DocPrint(out,"$$FD$$%s",txt+lpos);
    Fs->catch_except=TRUE;
  }
  LexerDel(l);
  Free(txt);
}
U0 SynViewAssist(CDoc *who) {
  U8 *t;
  DocTermNew;
  CLexer *l;
  CAST *ast;
  CHashClass *cls=NULL;
  LBts(&(Fs->display_flags),DISPLAYf_SHOW);

  //Load method definitions
  LoadMethodsFromBlob(,TRUE);

  if(t=BlobFileGetLump(,ST_ROOT"CLASSES")) {
    ExePutS(t);
    Free(t);
  }

  if(FramePtr("MethodClass"))
    cls=HashFind(FramePtr("MethodClass"),Fs->hash_table,HTT_CLASS);
  while(TRUE) {
    WinVert(2,TEXT_ROWS-10,Fs->parent_task);
    WinVert(TEXT_ROWS-10+2,TEXT_ROWS-1);
    if(FramePtr("DOC_MODIFIED")) {
      DocClear;
      "$$LTGREEN$$$$TX+CX,\"SmallTalkBuddy:\"$$$$FD$$\n";
      FramePtrSet("DOC_MODIFIED",0);
      t=DocSave(who);
      StrUtil(t,SUF_REM_CTRL_CHARS);
      l=LexerNew(t);
      try {
        Lex(l);
        if(cls)
	  MethodDel(ParseMethod(l,cls,TRUE));
        else if(!FramePtr("MethodClass")) {
	  while(ast=ParseAst(l))
	    ASTDel(ast);
        }
      } catch {
        Fs->catch_except=TRUE;
      };
      LexerDel(l);
      Free(t);
    }
    Sleep(500);
  }
}
Bool SynView(CDoc *doc) {
  FramePtrAdd("DOC_MODIFIED",1);
  CTask *check=Spawn(&SynViewAssist,doc,,,Fs);
  CDoc *pd=Fs->put_doc,*hl=DocNew,*dd=Fs->display_doc;
  Bool ul;
  Fs->put_doc=doc;
  Fs->display_doc=hl;
  U64 ch,*t;
  do {
    doc->flags|=DOCF_PLAIN_TEXT;
    t=DocSave(doc);    
    STSyntaxHighlight(hl,t);
    ul=DocLock(hl);
    hl->x=doc->x;
    hl->y=doc->y;
    DocRecalc(hl,RECALCt_FIND_CURSOR);
    if(ul) DocUnlock(hl);
    ch=DocGetKey;
//Used by SynViewAssist
    FramePtrSet("DOC_MODIFIED",1);
    Free(t);
  } while (ch!=CH_ESC && ch!=CH_SHIFT_ESC);
  DocDel(hl);
  Fs->put_doc=pd;
  Fs->display_doc=dd;
  FramePtrDel("DOC_MODIFIED");
  return ch==CH_ESC;
}


Bool STStudioRegisterNewClasses(U8 *blob_file) {
  if(!FileFind(blob_file)) return;
  CHashTable *new=HashTableNew(0x100);
  CHashClass *cls;
  Bool ret=FALSE;
  U8 buf[STR_LEN],*dummy;
  I64 idx;
  U8 *new_header=BlobFileGetLump(blob_file,ST_ROOT"CLASSES");
  new->next=Fs->hash_table;
  Fs->hash_table=new;
  try {
    ExePutS(new_header);
    ret=TRUE;
    for(idx=0;idx<=new->mask;idx++) {
      cls=new->body[idx];
      while(cls) {
	if(cls->type&HTT_CLASS) {
	  StrPrint(buf,ST_ROOT"%s/CONSTRUCTOR",cls->str);
          if(dummy=BlobFileGetLump(blob_file,buf)) {
//Lump already exists
          } else {
	    dummy=MStrPrint("init | |\n ^ self\n");
            BlobFileAddLump(blob_file,buf,dummy,StrLen(dummy),'SCRIPT');
          }
          Free(dummy);
//Class Methods
	  StrPrint(buf,ST_CLASS_ROOT"%s/NEW",cls->str);
          if(dummy=BlobFileGetLump(blob_file,buf)) {
//Lump already exists
          } else {
	    dummy=MStrPrint("new | |\n ^ self basicNew init\n");
            BlobFileAddLump(blob_file,buf,dummy,StrLen(dummy),'SCRIPT');
          }
          Free(dummy);
	}
	cls=cls->next;
      }
    }
  } catch {
    Fs->catch_except=TRUE;
  }
  Fs->hash_table=new->next;
  Free(new_header);
  HashTableDel(new);
  return ret;
};
//Blob file is needed for headers
U0 STValidateCode(U8 *blob_file="../ASS",U8 *code,U8 *path,Bool script=FALSE) {
  U8 *headers;
  U8 class_name[STR_LEN],*class_name_ptr=class_name;
  CDoc *pd=Fs->put_doc,*new=DocNew;
  CMethod *m;
  CAST *ast;
  //
  //Dumy hash table for tmeporary headers
  //
  CHashTable *dummy=HashTableNew(0x100);
  dummy->next=Fs->hash_table;
  Fs->hash_table=dummy;
//Parse the headers for information on the classes
  if(headers=BlobFileGetLump(blob_file,ST_ROOT"CLASSES")) {
    ExePutS(headers);
    Free(headers);
  }

  SanitizeStr(code); //raw DolDoc puts in werid charactors
  CLexer *l=LexerNew(code,path);
  DocClear(new);
  try {
    Fs->put_doc=new;
    Lex(l);
    StrScan(path,ST_ROOT"%s/",&class_name_ptr);
    if(!script) {
      m=ParseMethod(l,HashFind(class_name,Fs->hash_table,HTT_CLASS));
      MethodDel(m);
    } else {
      while(ast=ParseAst(l))
        ASTDel(ast);
    }
    DocPrint(new,"No errors in code!!!\n");
    DocPrint(new,"\n\n$$BT+CX,\"Cool\",LE=1$$\n\n");
  } catch {
    DocPrint(new,"\n\n$$BT+CX,\"Ok\",LE=1$$\n\n");
    Fs->catch_except=TRUE;

  }
  Fs->put_doc=pd;
  PopUpMenu(new);
  DocDel(new);
  Fs->hash_table=dummy->next;
//
// Done with header symbols
//
  HashTableDel(dummy);
}
U0 STHelpIdx(CDoc *help_doc,U8 *blob_file="../ASS",U8 *method_wildcard="*",Bool include_src=TRUE) {
  blob_file=ExtDft(blob_file,"BLOB");
  if(!FileFind(blob_file)) {
    PopUpOk("Cant Find Blob file!!!");
    Free(blob_file);
    return;
  }
again:;
  CI64Set *matches=I64SetNew;
  STStudioRegisterNewClasses(blob_file);
  CHashTable *new=HashTableNew(0x100);
  new->next=Fs->hash_table;
  U8 *new_header=BlobFileGetLump(blob_file,ST_ROOT"CLASSES");
  ExePutS(new_header);
  Free(new_header);
  CDocEntry *doc_e;
  Bool repeat=TRUE;
  I64 idx,idx2;
  CLexer *l;
  I64 class_method;
  U8 cls_name[STR_LEN],*cls_name_ptr=cls_name;
  U8 *prefix,*en,*tmp,*method_name,*blob;
  CBlobFileHeader *lumps=FileRead(blob_file);
  CLumpHeader *hdr;
  CMethod *m;
  DocPrint(help_doc,"$$PURPLE$$$$TX+CX,\"Help Index\"$$$$FD$$\n"); 
  DocMax(help_doc);
  Silent(TRUE);
  for(idx2=0;idx2!=2;idx2++) {
    if(idx2)
      DocBottom(help_doc);
//Phase 1,Methods
    for(idx=0;idx!=lumps->lump_cnt;idx++) {
      hdr=&lumps->lump_table[idx];
      if(!StrNCmp(hdr->name,ST_ROOT,StrLen(ST_ROOT))&&
	    StrCmp(hdr->name,ST_ROOT"CLASSES") //Make sure not CLASSES lump
	    &&StrOcc(hdr->name,'/')==2) { //1 '/' for root,1 '/' for class/method
        prefix=LumpNameToPath(hdr->name);
        if(!idx2) { 
	  tmp=MStrPrint("Instance Methods/%s",prefix);
	  if(en=StrLastOcc(hdr->name,"/")) {
	    method_name=StrNew(en+1);
	    try {
	      blob=BlobFileGetLump(blob_file,hdr->name);
	      l=LexerNew(blob);
	      Lex(l);
	      StrScan(hdr->name,ST_ROOT"%s/",&cls_name_ptr);
	      m=ParseMethod(l,HashFind(cls_name,Fs->hash_table,HTT_CLASS));
	      Free(method_name);
	      method_name=StrNew(m->name);
	      MethodDel(m);
	    } catch {
	      Fs->catch_except=TRUE;
	    }
	    if(WildMatch(method_name,method_wildcard)) {
	      I64SetAdd(matches,hdr);
	      DocTreeAppend(help_doc,tmp,FALSE,"$$LK,\"%Q\",A=\"FA:/SmallTalkHelp.DD,%Q\"$$\n",method_name,hdr->name);
            }
	  }
        } else if(I64SetHas(matches,hdr)) {
	  if(en=StrLastOcc(hdr->name,"/")) {
	    DocPrint(help_doc,"$$AN+CX,\"%Q\",A=\"%Q\"$$\n",en+1,hdr->name);
	    DocPrint(help_doc,"$$ID,2$$\n");
	    tmp=BlobFileGetLump(blob_file,hdr->name);
	    STSyntaxHighlight(help_doc,tmp,FALSE);
	    DocPrint(help_doc,"$$ID,-2$$\n");
	  }
        } else {
	  tmp=NULL;
        }
        Free(prefix);
        Free(tmp);
      }
    }
//Phase 2,Class Methods(start with .)
    for(idx=0;idx!=lumps->lump_cnt;idx++) {
      hdr=&lumps->lump_table[idx];
      if(!StrNCmp(hdr->name,ST_CLASS_ROOT,StrLen(ST_CLASS_ROOT))&&
	    StrCmp(hdr->name,ST_CLASS_ROOT) //Make sure not CLASSES lump
	    &&StrOcc(hdr->name,'/')==2) { //1 '/' for root,1 '/' for class/method
        prefix=LumpNameToPath(hdr->name);
        if(!idx2) {
	  tmp=MStrPrint("Class Methods/%s",prefix);
	  if(en=StrLastOcc(hdr->name,"/")) {
	    method_name=StrNew(en+1);
	    try {
	      blob=BlobFileGetLump(blob_file,hdr->name);
	      l=LexerNew(blob);
	      Lex(l);
	      StrScan(hdr->name,ST_ROOT"%s/",&cls_name_ptr);
	      m=ParseMethod(l,HashFind(cls_name,Fs->hash_table,HTT_CLASS));
	      Free(method_name);
	      method_name=StrNew(m->name);
	      MethodDel(m);
	    } catch
	      Fs->catch_except=TRUE;
	    if(WildMatch(method_name,method_wildcard)) {
	      I64SetAdd(matches,hdr);
 	      DocTreeAppend(help_doc,tmp,FALSE,"$$LK,\"%Q\",A=\"FA:/SmallTalkHelp.DD,%Q\"$$\n",method_name,hdr->name);
	    }
	    Free(method_name);
	  }
        } else if(I64SetHas(matches,hdr)) {
	  if(en=StrLastOcc(hdr->name,"/")) {
	    DocPrint(help_doc,"$$AN+CX,\"%Q\",A=\"%Q\"$$\n",en+1,hdr->name);
	    DocPrint(help_doc,"$$ID,2$$\n");
	    tmp=BlobFileGetLump(blob_file,hdr->name);
	    STSyntaxHighlight(help_doc,tmp,FALSE);
	    DocPrint(help_doc,"$$ID,-2$$\n");
	  }
        } else {
	  tmp=NULL;
        }
        Free(prefix);
        Free(tmp);
      }
    }
//Phase 3,Load scripts
    for(idx=0;idx!=lumps->lump_cnt;idx++) {
      hdr=&lumps->lump_table[idx];
      if(!StrNCmp(hdr->name,ST_SCRIPT_ROOT,StrLen(ST_SCRIPT_ROOT))) {
        if(!idx2) {
	  if(en=StrLastOcc(hdr->name,"/")) {
	    DocTreeAppend(help_doc,"Scripts",FALSE,"$$LK,\"%Q\",A=\"FA:/SmallTalkHelp.DD,%Q\"$$\n",en+1,hdr->name);
	  }
        } else {
	  if(en=StrLastOcc(hdr->name,"/")) {
	    DocPrint(help_doc,"$$AN+CX,\"%Q\",A=\"%Q\"$$\n",en+1,hdr->name);
	    DocPrint(help_doc,"$$ID,2$$\n");
	    tmp=BlobFileGetLump(blob_file,hdr->name);
	    STSyntaxHighlight(help_doc,tmp,FALSE);
	    Free(tmp);
	    DocPrint(help_doc,"$$ID,-2$$\n");
	  }
        }
      }
    }
  }
  Silent(FALSE);
  U8 *filename,*needle;
  I64 num;
  DocCollapse(FALSE,help_doc);
  DocRecalc(help_doc);
  for(doc_e=help_doc->head.next;doc_e!=&help_doc->head;doc_e=doc_e->next) {
    if(doc_e->type_u8==DOCT_LINK&&doc_e->de_flags&DOCEF_AUX_STR) {
      if(LK_FILE_ANCHOR==EdLinkCvt(tmp=StrNew(doc_e->aux_str),&filename,&needle,&num)) {
        if(DocAnchorFind(help_doc,needle)) {
	  idx=help_doc->cur_entry->y;
	  help_doc->cur_entry=doc_e;
	  DocPrint(help_doc,"$$LK\"%Q\",A=\"FL:/SmallTalkHelp.DD,%d\"$$",doc_e->tag,idx);
	  DocEntryDel(help_doc,doc_e);
          DocRecalc(help_doc);
        }
      }
      Free(tmp);
      Free(filename);
      Free(needle);
    }
  }
  I64SetDel(matches);
  Fs->hash_table=new->next;
  HashTableDel(new);
}

U0 STStudio(U8 *blob_file="../ASS") {
  blob_file=ExtDft(blob_file,"BLOB");
  if(!FileFind(blob_file)) {
    PopUpOk("Cant Find Blob file!!!");
    Free(blob_file);
    return;
  }
again:;
  STStudioRegisterNewClasses(blob_file);
  Bool repeat=TRUE;
  I64 idx,code,len;
  I64 class_method;
  U8 *prefix,*en,*tmp;
  CDoc *main_menu=DocNew,*edit;
  CBlobFileHeader *lumps=FileRead(blob_file);
  CLumpHeader *hdr;
  DocPrint(main_menu,"$$PURPLE$$$$TX+CX,\"SmallTalk Studio\"$$$$FD$$\n");
  DocPrint(main_menu,"\n\n$$BT+CX,\"Add Class\",LE=STS_ADD_CLASS$$\n\n");
  DocPrint(main_menu,"\n\n$$BT+CX,\"Method Name Search\",LE=STS_METHOD_HELP$$\n\n");
  DocPrint(main_menu,"$$RED$$$$TX+CX,\"Edit A Method\"$$$$FD$$\n");
 
//Phase 1,New method button
  for(idx=0;idx!=lumps->lump_cnt;idx++) {
    hdr=&lumps->lump_table[idx];
    if(!StrNCmp(hdr->name,ST_ROOT,StrLen(ST_ROOT))&&
	StrCmp(hdr->name,ST_ROOT"CLASSES") //Make sure not CLASSES lump
	&&StrOcc(hdr->name,'/')==2) { //1 '/' for root,1 '/' for class/method
      prefix=LumpNameToPath(hdr->name);
      tmp=MStrPrint("Instance Methods/%s",prefix);
      DocTreeWrite(main_menu,tmp,FALSE,"$$RED$$$$MU,\"New Method\",LE=%d$$$$FD$$\n",idx|(1<<32));
      Free(prefix);
      Free(tmp);
    }
  }
//Phase 2,fill in methods
  for(idx=0;idx!=lumps->lump_cnt;idx++) {
    hdr=&lumps->lump_table[idx];
    if(!StrNCmp(hdr->name,ST_ROOT,StrLen(ST_ROOT))
       &&StrCmp(hdr->name,ST_ROOT"CLASSES") //Make sure not CLASSES lump
	&&StrOcc(hdr->name,'/')==2 //"SmallTalk/Class/Method"
	&&hdr->name[0]!='.'
       ) {
      prefix=LumpNameToPath(hdr->name);
      tmp=MStrPrint("Instance Methods/%s",prefix);
      if(en=StrLastOcc(hdr->name,"/")) {
        DocTreeAppend(main_menu,tmp,FALSE,"$$BLUE$$$$MU,\"%Q\",LE=%d$$$$RED$$$$MU,\"(delete)\",LE=%d$$$$FD$$\n",en+1,idx,idx|(2<<32));
      }
      Free(prefix);
      Free(tmp);
    }
  }
//Phase 3,Class Methods(start with .)
  for(idx=0;idx!=lumps->lump_cnt;idx++) {
    hdr=&lumps->lump_table[idx];
    if(!StrNCmp(hdr->name,ST_CLASS_ROOT,StrLen(ST_CLASS_ROOT))
	&&StrOcc(hdr->name,'/')==2
	) { //1 '/' for root,1 '/' for class/method
      prefix=LumpNameToPath(hdr->name);
      tmp=MStrPrint("Class Methods/%s",prefix);
      DocTreeWrite(main_menu,tmp,FALSE,"$$RED$$$$MU,\"New Method\",LE=%d$$$$FD$$\n",idx|(4<<32));
      Free(prefix);
      Free(tmp);
    }
  }
//Phase 4 fill in class Methods
  for(idx=0;idx!=lumps->lump_cnt;idx++) {
    hdr=&lumps->lump_table[idx];
    if(!StrNCmp(hdr->name,ST_CLASS_ROOT,StrLen(ST_CLASS_ROOT))
	&&StrOcc(hdr->name,'/')==2 //"SmallTalk/Class/Method"
       ) {
      prefix=LumpNameToPath(hdr->name);
      tmp=MStrPrint("Class Methods/%s",prefix);
      if(en=StrLastOcc(hdr->name,"/")) {
        DocTreeAppend(main_menu,tmp,FALSE,"$$BLUE$$$$MU,\"%Q\",LE=%d$$$$RED$$$$MU,\"(delete)\",LE=%d$$$$FD$$\n",en+1,idx,idx|(2<<32));
      }
      Free(prefix);
      Free(tmp);
    }
  }
//Phase 5,Load scripts
  DocTreeWrite(main_menu,"Scripts",FALSE,"$$RED$$$$MU,\"New Script\",LE=%d$$$$FD$$\n",3<<32);
  for(idx=0;idx!=lumps->lump_cnt;idx++) {
    hdr=&lumps->lump_table[idx];
    if(!StrNCmp(hdr->name,ST_SCRIPT_ROOT,StrLen(ST_SCRIPT_ROOT))) {
      tmp=MStrPrint("Scripts");
      if(en=hdr->name+StrLen(ST_SCRIPT_ROOT)) {
        DocTreeAppend(main_menu,tmp,FALSE,"$$BLUE$$$$MU,\"%Q\",LE=%d$$$$RED$$$$MU,\"(delete)\",LE=%d$$$$FD$$\n",en,idx,idx|(2<<32));
      }
      Free(tmp);
    }
  }

  code=PopUpMenu(main_menu);
  DocDel(main_menu);
  switch(code) {
    case DOCM_CANCEL:
      repeat=FALSE;
    break;
    case STS_ADD_CLASS:
    edit=DocNew;
    en=BlobFileGetLump(blob_file,ST_ROOT"CLASSES");
    if(!en)
      DocType(edit,__DIR__ "/RunTime.HH");
    else
      DocPrint(edit,"%s",en);
    Free(en);
    PopUpPrint("FramePtrAdd(\"SAVED?\",DocEd(%d),%d);\n",edit,Fs);
    if(FramePtr("SAVED?")) {
      en=DocSave(edit);
      BlobFileAddLump(blob_file,ST_ROOT"CLASSES",en,StrLen(en),'HEADER');
      Free(en);
    }
    DocDel(edit);
    break;
    case STS_METHOD_HELP:
    edit=DocNew("/SmallTalkHelp.DD");
    tmp=PopUpGetStr("Enter Method Name Fragment:\n");
    if(StrLen(tmp)) {
      en=MStrPrint("*%s*",tmp);
    } else
      en=StrNew("*");
    STHelpIdx(edit,blob_file,en);
    DocWrite(edit);
    PopUpMenu(edit);
    Free(tmp),Free(en);
    DocDel(edit);
    break;
    default:
    hdr=&lumps->lump_table[code&(1<<32-1)];
    if(!StrNCmp(ST_ROOT,hdr->name,StrLen(ST_ROOT))) {
      tmp=StrNew(hdr->name+StrLen(ST_ROOT));
      if(StrOcc(tmp,'/')) *StrFirstOcc(tmp,"/")=0;
      FramePtrAdd("MethodClass",tmp);
    }
    if(!StrNCmp(ST_CLASS_ROOT,hdr->name,StrLen(ST_CLASS_ROOT))) {
      FramePtrAdd("MethodClass",StrNew("CFrogClass"));
    }
	    if((3<<32)&code==3<<32) {
      en=PopUpFileName("NEW_SCRIPT");
      edit=DocNew;
      PopUpPrint("FramePtrAdd(\"SAVED?\",SynView(%d),%d);\n",edit,Fs);
      if(FramePtr("SAVED?")) {
        tmp=DocSave(edit);
        prefix=MStrPrint(ST_SCRIPT_ROOT"%s",en);
        SanitizeStr(tmp); //raw DolDoc puts in werid cahractors
        BlobFileAddLump(blob_file,prefix,tmp,StrLen(tmp),'SCRIPT');
        STValidateCode(blob_file,tmp,prefix,TRUE);
	Free(prefix);
	Free(tmp);
      }
      Free(en);
    } else if((4<<32)&code) { //New Class Method
      prefix=LumpNameToPath(lumps->lump_table[code&(1<<32-1)].name);
      tmp=MStrPrint("%s/METHOD",prefix);
      en=PopUpFileName(tmp);
      Free(tmp);
      Free(prefix);
      edit=DocNew;
      PopUpPrint("FramePtrAdd(\"SAVED?\",SynView(%d),%d);\n",edit,Fs);
      if(FramePtr("SAVED?")) {
        tmp=DocSave(edit);
        prefix=MStrPrint(ST_CLASS_ROOT"%s",en);
        SanitizeStr(tmp); //raw DolDoc puts in werid cahractors
        BlobFileAddLump(blob_file,prefix,tmp,StrLen(tmp),'SCRIPT');
        STValidateCode(blob_file,tmp,prefix);
	Free(prefix);
      }
      Free(en);
    } else if((2<<32)&code) { //Delete method
      prefix=lumps->lump_table[code&(1<<32-1)].name;
      tmp=MStrPrint("Delete Method \"%Q\"?",prefix);
      if(PopUpNoYes(tmp)) {
	BlobFileDeleteLump(blob_file,prefix);
      }
      Free(tmp);
    } else if((1<<32)&code) { //New Instance method
      prefix=LumpNameToPath(lumps->lump_table[code&(1<<32-1)].name);
      tmp=MStrPrint("%s/METHOD",prefix);
      en=PopUpFileName(tmp);
      Free(tmp);
      Free(prefix);
      edit=DocNew;
      PopUpPrint("FramePtrAdd(\"SAVED?\",SynView(%d),%d);\n",edit,Fs);
      if(FramePtr("SAVED?")) {
        tmp=DocSave(edit);
        prefix=MStrPrint(ST_ROOT"%s",en);
        SanitizeStr(tmp); //raw DolDoc puts in werid cahractors
        BlobFileAddLump(blob_file,prefix,tmp,StrLen(tmp),'SCRIPT');
        STValidateCode(blob_file,tmp,prefix);
	Free(prefix);
      }
      Free(en);
    } else {
      edit=DocNew;
      DocPrint(edit,"%s",tmp=BlobFileGetLump(blob_file,lumps->lump_table[code].name));
      Free(tmp);
      PopUpPrint("FramePtrAdd(\"SAVED?\",SynView(%d),%d);\n",edit,Fs);
      if(FramePtr("SAVED?")) {
        en=DocSave(edit,&len);
        SanitizeStr(en); //raw DolDoc puts in werid cahractors
        BlobFileAddLump(blob_file,lumps->lump_table[code].name,en,StrLen(en),'SCRIPT');
        STValidateCode(blob_file,en,lumps->lump_table[code].name,0==StrNCmp(lumps->lump_table[code].name,ST_SCRIPT_ROOT,StrLen(ST_SCRIPT_ROOT)));
        Free(en);
      }
    }
    Free(FramePtr("MethodClass"));
    FramePtrDel("MethodClass");
    DocDel(edit);
    break;
  }
  Free(lumps);
  if(repeat)
    goto again;
  Free(blob_file);
}
U0 LoadMethodsFromBlob(U8 *blob_file=NULL,Bool dry_only=FALSE) {
  if(!blob_file) blob_file=dft_blob_path;
  blob_file=ExtDft(blob_file,"BLOB");
  if(!FileFind(blob_file)) {
    PopUpOk("Cant Find Blob file!!!");
    Free(blob_file);
    return;
  }
  CBlobFileHeader *lumps=FileRead(blob_file);
  CLumpHeader *hdr;
  U8 *tmp,*tmp2;
  U8 name[STR_LEN],method[STR_LEN];
  U8 *name_ptr=name,*method_ptr=method;
  I64 idx,len,idx2,dry;
  tmp=BlobFileGetLump(blob_file,ST_ROOT"CLASSES");
  ExePutS(tmp);
  Free(tmp);
  for(dry=1;dry>=0;dry--) {
    Silent(dry); 
    for(idx=0;idx!=lumps->lump_cnt;idx++) {
      hdr=&lumps->lump_table[idx];
      if(!StrNCmp(hdr->name,ST_ROOT,StrLen(ST_ROOT))) {
        if(StrOcc(hdr->name,'/')==2) { //1 is in ST_ROOT
	  StrScan(hdr->name,ST_ROOT"%s/%s",&name_ptr,&method_ptr);
	  try {
	    tmp=BlobFileGetLump(blob_file,hdr->name);
	    SanitizeStr(tmp);
	    CompileToHolyC(tmp,name,hdr->name,,dry);
	    Free(tmp);
	  } catch {
	    "In %s:",hdr->name;
	    PutExcept(TRUE);
	  }
        } 
      } else if(!StrNCmp(hdr->name,ST_CLASS_ROOT,StrLen(ST_CLASS_ROOT))) {
        if(StrOcc(hdr->name,'/')==2) { //Check for class method
	  StrScan(hdr->name,ST_CLASS_ROOT"%s/%s",&name_ptr,&method_ptr);
	  try {
	    tmp=BlobFileGetLump(blob_file,hdr->name);
	    SanitizeStr(tmp);
	    CompileToHolyC(tmp,name,hdr->name,TRUE,dry);
	    Free(tmp);
	  } catch {
	    "In %s:",hdr->name;
	    PutExcept(TRUE);
	  }
        }
      } else if(!dry&&!StrNCmp(hdr->name,ST_SCRIPT_ROOT,StrLen(ST_SCRIPT_ROOT))) {
	try {
	  tmp=BlobFileGetLump(blob_file,hdr->name);
	  STRunStmt(tmp);
	  Free(tmp);
	} catch {
	  "In %s:",hdr->name;
	  PutExcept(TRUE);
	}
      }
    }
    if(dry_only) {
      Silent(0);
      break;
    }
  }
  Free(lumps);
  Free(blob_file);
}
#if __CMD_LINE__
STStudio;
LoadMethodsFromBlob;
//STRepl;
//CDoc *d=DocNew("/WWW/SmallTalkHelp.DD");
//STHelpIdx(d);
//DocWrite(d);
//DocDel(d);
#else
F64 t=tS;
LoadMethodsFromBlob;
PrintF("load time ",tS-t);
#endif
