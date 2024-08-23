//#include "Studio.HC";
U8 *SkipWhitespace(U8 *str) {
  while(*str&&Bt(char_bmp_white_space,*str))
    str++;
  return str;
}
CFrogThing *LoadThing0(U8 **_str,U8 *_member=NULL) {
  CFrogThing *ret=FROG_SMALL_NIL,*tmp;
  CI64Set *init_list=FramePtr("STInitList");
  U8 *str=*_str;
  U8 member[STR_LEN],cls[STR_LEN],dummy[STR_LEN];
  U8 *member_ptr=member,*cls_ptr=cls;
  F64 num;
  I64 inum,ch,ptr;
again:
  str=SkipWhitespace(str);
  if(*str=='^') {
    str=StrScan(str,"^%s.Ptr:%d\n",&member_ptr,&ptr);
    if(_member) StrCpy(_member,member);
    StrPrint(member,"PTR.%d",ptr);
    if(!FramePtr(member))  {
//Nroot here,Pointers are first defined then used as pointers in SaveDefacto.
//You(should) never reach here
      if(!(ptr&0x7))
        PrintI("internalWTF(undef pointer)",ptr);
      else
        ret=ptr;
    } else if(ptr)
      ret=FramePtr(member);
    goto en;
  }
  if(*str=='-') {
    str=StrScan(str,"-%d.%s.%s:{",&ptr,&member_ptr,&cls_ptr);
    if(_member) StrCpy(_member,member);
    if(!StrCmp(cls,"CFrogNum")) {
      num=Str2F64(str,&str);
      ret=FrogNumNew(num);
    } else if(!StrCmp(cls,"CFrogChr")) { 
      str=StrScan(str,"%d",&inum);
      ret=FrogChrNew(inum);
    } else if(!StrCmp(cls,"CFrogClass")) {
      str=StrScan(str,"%s}",&cls_ptr)-1; //-1 to include '}',we EXPECT it later
      ret=FrogClassNew(NameToUniverseNumber(cls));
      StrPrint(dummy,"PTR.%d",ptr);
      FramePtrAdd(dummy,ret);
    } else if(!StrCmp(cls,"CFrogArray")) {
      str=StrScan(str,"%d.",&inum);
      ret=FrogArrayNew;
      StrPrint(dummy,"PTR.%d",ptr);
      FramePtrAdd(dummy,ret);
      while(--inum>=0) {
        I64SetAdd(ret(CFrogArray*)->items,LoadThing0(&str));
      }
    } else if(!StrCmp(cls,"CFrogStr")) {
      ret=FrogStrNew("");
      StrPrint(dummy,"PTR.%d",ptr);
      FramePtrAdd(dummy,ret);
      str=StrScan(str,"%d.",&inum);
      while(--inum>=0) {
        str=StrScan(str,"%d,",&ch);
        U8SetAdd(ret(CFrogArray*)->items,ch);
      }
    } else {
      ret=ConstructThing(cls);
      StrPrint(dummy,"PTR.%d",ptr);
      FramePtrAdd(dummy,ret);
      if(ret) CallScript("beforeRestore",ret);
      str=SkipWhitespace(str);
      while(*str&&*str!='}') {
        tmp=LoadThing0(&str,member);
        if(ret&&tmp) SetClassMemberVal(ret,member,tmp);
        str=SkipWhitespace(str);
      }
    }
    while(*str&&*str!='}') str++;
    if(*str=='}') str++;
  }
  I64SetAdd(init_list,ret);
en:
  *_str=str;
  return ret;
}
CFrogThing *RestoreThing0(U8 *s) {
  CI64Set *init_list=I64SetNew;
  CHashTable *table=HashTableNew(0x100);
  table->next=Fs->hash_table;
  Fs->hash_table=table;
  FramePtrAdd("STInitList",init_list);
  I64 cnt;
  U8 *s2=s;
  CFrogThing *r=LoadThing0(&s2); 
  cnt=init_list->cnt; 
  while(--cnt>=0) {
    CallScript("afterRestore",init_list->body[cnt]);
  }
  Fs->hash_table=table->next;
  HashTableDel(table);
  I64SetDel(init_list);
  FramePtrDel(init_list);
  return r;
}
U0 SaveDefacto0(CDoc *doc,U8 *str,CFrogThing *have,I64 depth=1,CI64Set *save_list) {
  if(I64SetHas(save_list,have)) {
    DocPrint(doc,"^%s.Ptr:%d\n",str,have); //Pointer
    return;
  }
  I64SetAdd(save_list,have);
  if(depth<=0) return;
  I64 cnt,val,idx,force_ser;
  F64 fval;
  U8 *ptr,buf[STR_LEN];
  CHashClass *cls;
  CMemberLst *mlst;
  CFrogThing *as,**array_body,dummy;
  CallScript("beforeSave",have);
  if(ThingHasClass(have,"CFrogNum")) {
    DocPrint(doc,"-0.%s.CFrogNum:{%n}\n",str,AsF64(have));
  } else if(ThingHasClass(have,"CFrogUndefined")) {
nil:
    DocPrint(doc,"-0.%s.CFrogUndefined:{}\n",str);
  } else if(ThingHasClass(have,"CFrogChr")) {
    DocPrint(doc,"-0.%s.CFrogChr:{%d}\n",str,have(CFrogChr*)->ch);
  } else if(ThingHasClass(have,"CFrogClass")) {
    DocPrint(doc,"-%d.%s.CFrogClass:{%s}\n",have,str,have(CFrogClass*)->name);
  } else if(ThingHasClass(have,"CFrogBlock")) {
    goto nil;
  } else if(ThingHasClass(have,"CFrogStr")) {
    cnt=have(CFrogStr*)->items->cnt;
    ptr=have(CFrogStr*)->items->body;
    DocPrint(doc,"-%d.%s.CFrogStr:{%d.\n",have,str,cnt);
    for(idx=0;idx!=cnt;idx++) {
      DocPrint(doc,"%d,",ptr[idx]);
    }
    DocPrint(doc,"}\n");
  } else if(ThingHasClass(have,"CFrogArray")) {
    cnt=have(CFrogArray*)->items->cnt;
    array_body=have(CFrogArray*)->items->body;
    DocPrint(doc,"-%d.%s.CFrogArray:{%d.\n",have,str,cnt);
    for(idx=0;idx!=cnt;idx++) {
      StrPrint(buf,"%d",idx);
      SaveDefacto0(doc,buf,array_body[idx],depth+1,save_list);
    }
    DocPrint(doc,"}\n");
  } else {
    as=CallScript("saveString",have);
    if(ThingHasClass(as,"CFrogStr")) {
      ptr=AsString(as);
      DocPrint(doc,"-0.%s.%s:{\n%s}\n",str,FrogThingClassName(have),ptr);
      Free(ptr);
    } else {
      DocPrint(doc,"-%d.%s.%s:{\n",have,str,FrogThingClassName(have));
      cls=HashFind(FrogThingClassName(have),frog_mem_task->hash_table,HTT_CLASS);
      MemSet(&dummy,0,sizeof CFrogThing);
      while(cls)  {
        if(!StrCmp("CFrogThing",cls->str))
	  break;
        mlst=cls->member_lst_and_root;
        while(mlst) {
	  if(mlst->member_class->ptr_stars_cnt==1) {
	    StrCpy(dummy.class_name,mlst->member_class[-1].str);
	    if(!MemberMetaFind("no_serialize",mlst)) {
	      force_ser=ToBool(MemberMetaFind("recur_serialize",mlst));
	      if(ThingHasClass(&dummy,"CFrogThing")) {
	        val=GetClassMemberValI64(have,mlst->str);
	        SaveDefacto0(doc,mlst->str,val,depth+force_ser,save_list);
	      }
	    }
	  } else if(!mlst->member_class->ptr_stars_cnt) {
	    SaveDefacto0(doc,mlst->str,FrogNumNew(GetClassMemberValF64(have,mlst->str)),depth+force_ser,save_list);
	  }
	  mlst=mlst->next;
        }
        cls=cls->base_class;
      }
      DocPrint(doc,"}\n");
    }
  } 
}
CFrogStr *SaveThing(CFrogThing *t,...) {
  CDoc *doc=DocNew();
  doc->flags|=DOCF_NO_CURSOR;
  U8 *as_txt;
  CI64Set *save_list=I64SetNew;
  SaveDefacto0(doc,"",t,,save_list);
  as_txt=DocSave(doc);
  I64SetDel(save_list);
  t=FrogStrNew(as_txt);
  Free(as_txt);
  DocDel(doc);
  return t;
}
CFrogStr *SaveThingToSaveFile(CFrogThing *t,...) {
  U8 *name=AsString(argv[0]);
  if(!name) return FROG_SMALL_NIL;
  U8 *in_dir=MStrPrint("/FrogSaves/%s.DD",name);
  if(!FileFind("/FrogSaves")) DirMk("/FrogSaves");
  CDoc *doc=DocNew(in_dir);
  Free(in_dir);
  doc->flags|=DOCF_NO_CURSOR;
  CI64Set *save_list=I64SetNew;
  SaveDefacto0(doc,"",t,,save_list);
  I64SetDel(save_list);
  DocWrite(doc);
  DocDel(doc);
  Free(name);
  return FROG_SMALL_NIL;
}
CFrogThing *RestoreThingFromSaveFile(CFrogStr *t,...) {
  U8 *name=AsString(t);
  if(!name) return FROG_SMALL_NIL;
  CFrogThing *ret=FROG_SMALL_NIL;
  U8 *in_dir=MStrPrint("/FrogSaves/%s.DD",name),*data,*d2;
  data=FileRead(in_dir);
  Free(name);
  Free(in_dir);
  if(data) {
    d2=data;
    ret=RestoreThing0(data);
  }
  Free(data);
  return ret;
}
AddMethod("CFrogThing","saveThingToSaveFile:",&SaveThingToSaveFile);
AddMethod("CFrogStr","restoreThingFromSaveFile",&RestoreThingFromSaveFile);
AddMethod("CFrogThing","saveThing",&SaveThing);
AddMethod("CFrogThing","basicSaveThing",&SaveThing);
//AddMethod("CFrogStr","restoreThing",&RestoreThing);