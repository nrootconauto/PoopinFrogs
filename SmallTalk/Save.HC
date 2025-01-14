#include "Studio.HC";
U64 SerReadU64(U8 **_ptr) {
  U64 r=(*_ptr)[0](U64);
  *_ptr+=8;
  return r;
}
U64 SerReadU8(U8 **_ptr) {
  U64 r=(*_ptr)[0];
  *_ptr+=1;
  return r;
}
U8 *SerReadStr(U8 *to,U8 **_ptr) {
  U8 *ptr=*_ptr;
  I64 l=StrLen(ptr);
  MemCpy(to,ptr,l+1);
  *_ptr=ptr+l+1;
  return ptr;
}
U0 SerWriteU64(CU8Set *s,U64 f) {
  U8SetAddBytes(s,&f,8); 
}
U0 SerWriteF64(CU8Set *s,F64 f) {
  U8SetAddBytes(s,&f,8); 
}
U0 SerWriteU8(CU8Set *s,U8 f) {
  U8SetAddBytes(s,&f,1); 
}
U0 SerWriteStr(CU8Set *s,U8 *str) {
  U8SetAddBytes(s,str,StrLen(str)+1);
}
CFrogThing *LoadThing0(U8 **_str,U8 *_member=NULL) {
  CFrogThing *ret=FROG_SMALL_NIL,*tmp;
  CI64Set *init_list=FramePtr("STInitList");
  U8 member[STR_LEN],cls[STR_LEN],dummy[STR_LEN];
  U8 *member_ptr=member,*cls_ptr=cls;
  F64 num;
  I64 inum,ch,ptr;
again:
  ch=SerReadU8(_str);
  if(ch=='^') {
    ptr=SerReadU64(_str);
    SerReadStr(member,_str);
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
    if(**_str=='.') _str[0]++;
    goto en;
  }
  if(ch=='-') {
    ptr=SerReadU64(_str);
    SerReadStr(member,_str);
    SerReadStr(cls,_str);
    if(_member) StrCpy(_member,member);
    if(!StrCmp(cls,"CFrogDictionary")) {
      ret=ConstructThing("CFrogDictionary");
      while(**_str!='.') {
        tmp=LoadThing0(_str,member);
        CallScript("at:put:",ret,FrogStrNew(member),tmp);
      }    
      StrPrint(dummy,"PTR.%d",ptr);
      FramePtrAdd(dummy,ret);
    } else if(!StrCmp(cls,"CFrogSymbol")&&member[0]=='#') {
      FrogSymbol(member+1)->value=LoadThing0(_str,dummy);
    } else if(!StrCmp(cls,"CFrogNum")) {
      inum=SerReadU64(_str);
      ret=FrogNumNew(inum(F64));
    } else if(!StrCmp(cls,"CFrogChr")) { 
      inum=SerReadU8(_str);
      ret=FrogChrNew(inum);
    } else if(!StrCmp(cls,"CFrogClass")) {
      SerReadStr(cls_ptr,_str);
      ret=FrogClassNew(NameToUniverseNumber(cls));
    } else if(!StrCmp(cls,"CFrogArray")) {
      inum=SerReadU64(_str);
      ret=FrogArrayNew;
      StrPrint(dummy,"PTR.%d",ptr);
      FramePtrAdd(dummy,ret);
      while(--inum>=0) {
        I64SetAdd(ret(CFrogArray*)->items,LoadThing0(_str));
      }
    } else if(!StrCmp(cls,"CFrogStr")) {
      ret=FrogStrNew("");
      StrPrint(dummy,"PTR.%d",ptr);
      FramePtrAdd(dummy,ret);
      inum=SerReadU64(_str);
      U8SetAddBytes(ret(CFrogStr*)->items,*_str,inum);
      *_str+=inum;
    } else {
      ret=ConstructThing(cls);
      StrPrint(dummy,"PTR.%d",ptr);
      FramePtrAdd(dummy,ret);
      if(ret) CallScript("beforeRestore",ret);
      while(**_str&&**_str!='.') {
        tmp=LoadThing0(_str,member);
        if(ret&&tmp) SetClassMemberVal(ret,member,tmp);
      }
    }
    if(**_str=='.') _str[0]++;
  } else if(**_str) {
  }
  I64SetAdd(init_list,ret);
en:
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
  gc_lock_cnt++;
  CFrogThing *r=LoadThing0(&s2); 
  gc_lock_cnt--;
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
U0 SaveDefacto0(CU8Set *doc,U8 *str,CFrogThing *have,I64 depth=1,CI64Set *save_list) {
  if(I64SetHas(save_list,have)) {
//Pointer
    SerWriteU8(doc,'^');
    SerWriteU64(doc,have);
    SerWriteStr(doc,str);
    SerWriteU8(doc,'.');
    return;
  }
  SerWriteU8(doc,'-');
  if(!(have&1)) //Dont save primtive types
    I64SetAdd(save_list,have);
  if(depth<=0) return;
  gc_lock_cnt++;
  I64 cnt,val,idx,force_ser;
  F64 fval;
  U8 *ptr,buf[STR_LEN];
  CHashClass *cls;
  CMemberLst *mlst;
  CHashTable *dtab;
  CHashGeneric *dtab_e;
  CFrogThing *as,**array_body,dummy;
  CallScript("beforeSave",have);
  if(ThingHasClass(have,"CFrogSymbol")) {
    SerWriteU64(doc,have);
    SerWriteU8(doc,'#');
    SerWriteStr(doc,have(CFrogSymbol*)->name);
    SerWriteStr(doc,"CFrogSymbol");
    SaveDefacto0(doc,"value",have(CFrogSymbol*)->value,depth+1,save_list);
    SerWriteU8(doc,'.');
  } else if(ThingHasClass(have,"CFrogNum")) {
    SerWriteU64(doc,0);
    SerWriteStr(doc,str);
    SerWriteStr(doc,"CFrogNum");
    SerWriteF64(doc,AsF64(have));
    SerWriteU8(doc,'.');
  } else if(ThingHasClass(have,"CFrogUndefined")) {
nil:
    SerWriteU64(doc,0);
    SerWriteStr(doc,str);
    SerWriteStr(doc,"CFrogUndefined");
    SerWriteU8(doc,'.');
  } else if(ThingHasClass(have,"CFrogChr")) {
    SerWriteU64(doc,0);
    SerWriteStr(doc,str);
    SerWriteStr(doc,"CFrogChr");
    SerWriteU8(doc,AsChar(have));
    SerWriteU8(doc,'.');
  } else if(ThingHasClass(have,"CFrogDictionary")) {
    dtab=have(CFrogDictionary*)->t;
    cnt=dtab->mask+1;
    SerWriteU64(doc,have);
    SerWriteStr(doc,str);
    SerWriteStr(doc,"CFrogDictionary");
    for(idx=0;idx!=cnt;idx++) {
      for(dtab_e=dtab->body[idx];dtab_e;dtab_e=dtab_e->next) {
        SaveDefacto0(doc,dtab_e->str,dtab_e->user_data1,depth+1,save_list);
      }
    }
    SerWriteU8(doc,'.');
  } else if(ThingHasClass(have,"CFrogClass")) {
    SerWriteU64(doc,have);
    SerWriteStr(doc,str);
    SerWriteStr(doc,"CFrogClass");
    SerWriteStr(doc,UniverseNumberToName(have>>16));
    SerWriteU8(doc,'.');
  } else if(ThingHasClass(have,"CFrogBlock")) {
    goto nil;
  } else if(ThingHasClass(have,"CFrogStr")) {
    SerWriteU64(doc,have);
    SerWriteStr(doc,str);
    SerWriteStr(doc,"CFrogStr");
    SerWriteU64(doc,have(CFrogStr*)->items->cnt);
    U8SetAddBytes(doc,have(CFrogStr*)->items->body,have(CFrogStr*)->items->cnt);
    SerWriteU8(doc,'.');
  } else if(ThingHasClass(have,"CFrogArray")) {
    SerWriteU64(doc,have);
    SerWriteStr(doc,str);
    SerWriteStr(doc,"CFrogArray");
    SerWriteU64(doc,have(CFrogArray*)->items->cnt);
    cnt=have(CFrogArray*)->items->cnt;
    array_body=have(CFrogArray*)->items->body;
    for(idx=0;idx!=cnt;idx++) {
      StrPrint(buf,"%X",idx);
      SaveDefacto0(doc,buf,array_body[idx],depth+1,save_list);
    }
    SerWriteU8(doc,'.');
  } else {
    SerWriteU64(doc,have);
    SerWriteStr(doc,str);
    SerWriteStr(doc,FrogThingClassName(have));
    cls=HashFind(FrogThingClassName(have),frog_mem_task->hash_table,HTT_CLASS);
    MemSet(&dummy,0,sizeof CFrogThing);
    while(cls)  {
      if(!StrCmp("CFrogThing",cls->str))
        break;
      mlst=cls->member_lst_and_root;
      while(mlst) {
        if(mlst->member_class->ptr_stars_cnt==1) {
          dummy.universe_class_idx=UniverseAddClass(mlst->member_class[-1].str);
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
    SerWriteU8(doc,'.');
  }
  gc_lock_cnt--;
}
CFrogStr *SaveThing(CFrogStr *t,I64 *argv,I64 argc) {
  CU8Set *set =U8SetNew(frog_mem_task);
  CI64Set *save_list=I64SetNew;
  SaveDefacto0(set,"",t,,save_list);
  I64SetDel(save_list);
  t=FrogStrNew("");
  U8SetDel(t->items);
  t->items=set;
  return t;
}
CFrogStr *SaveThingToSaveFile(CFrogThing *t,I64 *argv,I64 argc) {
  U8 *name=AsString(argv[0]);
  if(!name) return FROG_SMALL_NIL;
  U8 *in_dir=MStrPrint("/FrogSaves/%s.DD",name);
  if(!FileFind("/FrogSaves")) DirMk("/FrogSaves");
  CU8Set *doc=U8SetNew;
  CI64Set *save_list=I64SetNew;
  SaveDefacto0(doc,"",t,,save_list);
  I64SetDel(save_list);
  FileWrite(in_dir,doc->body,doc->cnt);
  Free(in_dir);
  U8SetDel(doc);
  Free(name);
  return FROG_SMALL_NIL;
}
CFrogThing *RestoreThingFromSaveFile(CFrogStr *t,I64 *argv,I64 argc) {
  U8 *name=AsString(t);
  if(!name) return FROG_SMALL_NIL;
  CFrogThing *ret=FROG_SMALL_NIL;
  U8 *in_dir=MStrPrint("/FrogSaves/%s.DD",name),*data,*d2;
  data=FileRead(in_dir);
  Free(name);
  Free(in_dir);
  if(data) {
    ret=RestoreThing0(data);
    Free(data);
  }
  return ret;
}
CFrogThing *RestoreThing(CFrogStr *t,I64 *argv,I64 argc) {
  return RestoreThing0(t->items->body);
}

AddMethod("CFrogThing","saveThingToSaveFile:",&SaveThingToSaveFile);
AddMethod("CFrogStr","restoreThingFromSaveFile",&RestoreThingFromSaveFile);
AddMethod("CFrogThing","saveThing",&SaveThing);
AddMethod("CFrogThing","basicSaveThing",&SaveThing);
AddMethod("CFrogStr","restoreThing",&RestoreThing);