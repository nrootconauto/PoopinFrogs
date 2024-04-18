#include "Compiler.HC";
#include "../BlobFile.HC";
#define STS_ADD_CLASS -100
#define ST_ROOT	"SmallTalk/" //Must be same length
#define ST_CLASS_ROOT	"STClsRoot/"
#define ST_SCRIPT_ROOT	"STScripts/"
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

U0 STSyntaxHighlight(CDoc *out,U8 noreg *txt) {
  DocClear(out);
  I64 noreg lpos=0;
  I64 nest_depth=0;
  SanitizeStr(txt);
//Newline in case our lexer eats the 0
  txt=MStrPrint("%s\n",txt);
  CLexer *l=LexerNew(txt);
  l->flags=LEXF_SILENT;
  try {
again:
    lpos=l->pos;
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
        while(lpos!=l->pos) {
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
  Free(txt);
}
Bool SynView(CDoc *doc) {
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
    Free(t);
  } while (ch!=CH_ESC && ch!=CH_SHIFT_ESC);
  DocDel(hl);
  Fs->put_doc=pd;
  Fs->display_doc=dd;
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
	    dummy=MStrPrint("new | |\n ^ self basicNew\n");
            BlobFileAddLump(blob_file,buf,dummy,StrLen(dummy),'SCRIPT');
          }
          Free(dummy);
	}
	cls=cls->next;
      }
    }
  } catch {
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

  };
  Fs->put_doc=pd;
  PopUpMenu(new);
  DocDel(new);
  Fs->hash_table=dummy->next;
//
// Done with header symbols
//
  HashTableDel(dummy);
}
U0 STStudio(U8 *blob_file="../ASS") {
  blob_file=ExtDft(blob_file,"BLOB.Z");
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
    default:
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
        STValidateCode(blob_file,en,lumps->lump_table[code].name);
        Free(en);
      }
    }
    DocDel(edit);
    break;
  }
  Free(lumps);
  if(repeat)
    goto again;
  Free(blob_file);
}
U0 LoadMethodsFromBlob(U8 *blob_file="../ASS") {
  blob_file=ExtDft(blob_file,"BLOB.Z");
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
	    "In %s:",hdr->name;
	    PutExcept(TRUE);
	  }
        }
      } else if(!StrNCmp(hdr->name,ST_SCRIPT_ROOT,StrLen(ST_SCRIPT_ROOT))) {
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
  }
  Free(lumps);
  Free(blob_file);
}
#if __CMD_LINE__
STStudio;
LoadMethodsFromBlob;
STRepl;
#else
LoadMethodsFromBlob;
#endif
