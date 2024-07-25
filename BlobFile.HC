#ifndef FROG_BLOB_HH
#define FROG_BLOB_HH "Blob"
#define DEVELOPMENT_MODE TRUE
#exe {Cd(__DIR__);;};
#exe{StreamPrint("#define DEVELOPMENT_DIR \"%Q/AssBlobDir\"\n",__DIR__);}
extern U0 UndumpBlobFile(U8 *filename,U8 *dir="/Tmp",Bool delete=FALSE);
extern U0 DumpBlobFile(U8 *filename,U8 *dir="/Tmp");
class CLumpHeader {
  U8 name[144];
  U64 type;
  I64 offset;
  I64 size;
};
class CBlobFileHeader {
  I64 lump_cnt;
  CLumpHeader lump_table[0];
};
class CBlobFileCache {
  CDate datetime;
  U8 *data;
  U8 *filename;
  CTask *mem_task;
  I64 sz;
} blob_file_cache={0,NULL,NULL,Fs,0};
CLumpHeader *BlobFileGetLumpInfo(CBlobFileHeader *hd,U8 *blob) {
  I64 cnt=hd->lump_cnt;
  CLumpHeader *ret;
  while(--cnt>=0) {
    ret=&hd->lump_table[cnt];
    if(!StrCmp(ret->name,blob))
      return ret;
  }
  return NULL;
}
//This consults the cache
//DO NOT FREE
U8 *GetBlobFileData(U8 *filename,I64 *len=NULL) {
  CDirEntry de;
  U8 *data=NULL;
//Dumb hack,seth_task(on differnt core) has different Fs->cur_dir so use the cached one.
  if(Gs->num) goto force_cache;

  if(FileFind(filename,&de)) {
    if(blob_file_cache.filename&&de.datetime<=blob_file_cache.datetime) {
      if(!StrCmp(blob_file_cache.filename,de.full_name)) {
        Free(de.full_name);
force_cache:;
	if(len) *len=blob_file_cache.sz;
        return blob_file_cache.data;
      }
    }
    Free(de.full_name);
regen:
    Free(blob_file_cache.filename);
    blob_file_cache.filename=StrNew(de.full_name,blob_file_cache.mem_task);
    data=FileRead(de.full_name,&blob_file_cache.sz);
    blob_file_cache.data=MAllocIdent(data,blob_file_cache.mem_task);
    blob_file_cache.datetime=de.datetime;
    if(len) *len=blob_file_cache.sz;
    Free(data);
    data=blob_file_cache.data;
  }
  return data;
}
U8 *BlobFileGetLump(U8 *filename,U8 *name,I64 *len=NULL,U64 *type=NULL) {
  CLumpHeader *lump;
  U8 *ret=NULL,*ftxt;
  filename=ExtDft(filename,"BLOB");
  if(ftxt=GetBlobFileData(filename)) {
found:
    lump=BlobFileGetLumpInfo(ftxt,name);
    if(lump) {
      ret=MAlloc(lump->size+1);
      MemCpy(ret,lump->offset+ftxt,lump->size);
      ret[lump->size]=0;
      if(len) *len=lump->size;
      if(type) *type=lump->type;
    }
  } 
#ifdef DEVELOPMENT_MODE
  else {
    UndumpBlobFile(filename,DEVELOPMENT_DIR);
    if (ftxt=GetBlobFileData(filename)) goto found;
  }
#endif    
  Free(filename);
  return ret;
}
I64 BlobLumpSort(CLumpHeader *a,CLumpHeader *b) {
  return StrCmp(a->name,b->name);
}
//dlen can be -1 for delete
U0 BlobFileAddLump(U8 *filename,U8 *name,U8 *data,I64 dlen,U64 type='DATA') {
  I64 ofsz,want_sz,idx,idx2;
  CLumpHeader *lump_hdr;
  CBlobFileHeader *ret,*oftxt;
  U8*write_to,*read_from;
  filename=ExtDft(filename,"BLOB");
  if(!(oftxt=GetBlobFileData(filename,&ofsz))) {
    oftxt=CAlloc(sizeof CBlobFileHeader);
    ofsz=sizeof CBlobFileHeader;
  }
  want_sz=ofsz;
  lump_hdr=BlobFileGetLumpInfo(oftxt,name);
  if(dlen>=0) {
    if(lump_hdr) {
      want_sz=want_sz-lump_hdr->size+dlen;
    } else {
      want_sz+=dlen;
      want_sz+=sizeof(CLumpHeader);
    }
  } else {
    if(lump_hdr) {
      want_sz=want_sz-lump_hdr->size;
    }
  }
  ret=CAlloc(want_sz);
  if(dlen>=0) {
    if(lump_hdr) {
      ret->lump_cnt=oftxt->lump_cnt; //A Lump already exists
    } else
      ret->lump_cnt=oftxt->lump_cnt+1; //Make a new lump
  } else {
    if(lump_hdr)
      ret->lump_cnt=oftxt->lump_cnt-1;
    else
      ret->lump_cnt=oftxt->lump_cnt;
  }
//Data appears after the lump table
  write_to=ret->lump_table+ret->lump_cnt;  
//Copy the lumps from the original to the new
  idx2=0;
  for(idx=0;idx!=oftxt->lump_cnt;idx++) {
    lump_hdr=&oftxt->lump_table[idx];
    if(StrCmp(lump_hdr->name,name)) {
      read_from=oftxt(U8*)+lump_hdr->offset;
      MemCpy(write_to,read_from,lump_hdr->size);
      StrCpy(ret->lump_table[idx2].name,lump_hdr->name);
      ret->lump_table[idx2].type=lump_hdr->type;
      ret->lump_table[idx2].size=lump_hdr->size;
      ret->lump_table[idx2++].offset=write_to-ret(U8*);
      write_to+=lump_hdr->size;
    }
  }
  if(dlen>=0) {
    lump_hdr=&ret->lump_table[ret->lump_cnt-1];
    lump_hdr->size=dlen;
    lump_hdr->offset=write_to-ret(U8*);
    lump_hdr->type=type;
    StrCpy(lump_hdr->name,name);
    MemCpy(write_to,data,dlen);
  }
  QSort(ret->lump_table,ret->lump_cnt,sizeof(CLumpHeader),&BlobLumpSort);
  FileWrite(filename,ret,want_sz);
#ifdef DEVELOPMENT_MODE
  DumpBlobFile(filename,DEVELOPMENT_DIR);
#endif
  Free(ret);
  if(blob_file_cache.filename) {
    ret=FileNameAbs(filename);
    if(!StrCmp(ret,blob_file_cache.filename)) {
      blob_file_cache.datetime=0;
    }
    Free(ret);
  }
  Free(filename);
}
U0 BlobFileDeleteLump(U8 *blob_file,U8 *path) {
  BlobFileAddLump(blob_file,path,"",-1);
}
U8 *_BlobFileSelectPath(U8 *lump_name) {
  U8 *tmp=NULL,*ret;
  if(!StrOcc(lump_name,'/')) {
    return StrNew("");
  }
  tmp=StrNew(lump_name);
  *StrLastOcc(tmp,"/")=0;
  ret=MStrPrint("%s",tmp);
  Free(tmp);
  return ret;
}
//Returns "blob filename"
U8 *BlobFileSelect(U8 *filename) {
loop:
  filename=ExtDft(filename,"BLOB");
  if(!FileFind(filename)) {
    Free(filename);
    return NULL;
  }
  I64 cnt;
  U8 *path_title,*tmp,*ret;
  CDocEntry *dent,*stat;
  CLumpHeader *hdr;
  CBlobFileHeader *fl=GetBlobFileData(filename);
  CDoc *dummy=DocNew();
  cnt=fl->lump_cnt;
  while(--cnt>=0) {
    hdr=&fl->lump_table[cnt];
    path_title=_BlobFileSelectPath(hdr->name);
    tmp=MStrPrint("%s/%s",filename,path_title);
again:
    if(DocTreeFind(dummy,tmp,,&dent)) {
      dummy->cur_entry=dent->next;
    } else {
      DocTreeMake(dummy,tmp);   
      DocTreeFind(dummy,tmp,,&dent);
      dummy->cur_entry=dent->next;
//I put the left_exp value in ->aux_str so it gets Free'd
      stat=DocPrint(dummy,"$$RED$$$$MU,\"New Here\",A=\"%Q/\",LE=0$$",path_title);
      stat->left_exp=stat->aux_str;
      DocPrint(dummy,"$$FD$$\n");
      goto again;
    }
    Free(tmp);
    Free(path_title);
    if(path_title=StrLastOcc(hdr->name,"/"))
      DocPrint(dummy,"$$BLUE$$$$MU,\"%Q\",LE=%d$$$$RED$$$$MU,\"(delete)\",LE=%d$$$$FD$$\n",path_title+1,hdr->name,hdr->name|1);
    else
//Header names are aligned to 8,so if bit 0 is set,mark for deletion
      DocPrint(dummy,"$$BLUE$$$$MU,\"%Q\",LE=%d$$$$RED$$$$MU,\"(delete)\",LE=%d$$$$FD$$\n",hdr->name,hdr->name,hdr->name|1);
  }
  DocBottom(dummy);
  DocPrint(dummy,"$$RED$$$$MU,\"New File\",LE=INVALID_PTR$$");
  ret=PopUpMenu(dummy);
  if(ret==INVALID_PTR)
    path_title=PopUpFileName("FOLDER/FILE");
  else if(ret==DOCM_CANCEL)
    path_title=NULL;
  else if(ret&1) {
//Bit 0 means marked for deletion
    tmp=MStrPrint("Delete File \"%Q\"",ret&~1);
    if(PopUpNoYes(tmp)) {
      BlobFileDeleteLump(filename,ret&~1);
    }
    Free(tmp);
    DocDel(dummy);
    Free(filename);
    goto loop;
  } else if(ret[StrLen(ret)-1]!='/'){
    path_title=StrNew(ret);
  } else if(ret[StrLen(ret)-1]=='/') {
    tmp=MStrPrint("%sNEW_FILE",ret); //ret ends with a '/'
    path_title=PopUpFileName(tmp);
    Free(tmp);
  } else 
    ret=NULL; //???
  DocDel(dummy);
  Free(filename);
  return path_title;
}
U0 DumpBlobFile(U8 *filename,U8 *dir="/Tmp") {
  CLumpHeader *hdr;
  CBlobFileHeader *blobh;
  U8 *tmp,*path_title,*last_slash;
  U8 *old_dir=DirCur;
  I64 idx,cnt;
  filename=ExtDft(filename,"BLOB");
  if(!FileFind(filename)) {
    Free(old_dir);
    Free(filename);
    return;
  }
  blobh=FileRead(filename);
  cnt=blobh->lump_cnt;
  for(idx=0;idx!=cnt;idx++) {
    hdr=&blobh->lump_table[idx];
    path_title=_BlobFileSelectPath(hdr->name);
    last_slash=hdr->name;
    if(StrOcc(last_slash,'/'))
      last_slash=StrLastOcc(last_slash,"/")+1;
    if(path_title[0]=='/')
      tmp=StrNew(dir);
    else
      tmp=MStrPrint("%s/%s",dir,path_title);
    if(!FileFind(tmp))
      Cd(tmp,TRUE);
    Cd(old_dir);
    Free(path_title);
    path_title=MStrPrint("%s/%s.%c",tmp,last_slash,hdr->type);
    FileWrite(path_title,blobh(U8*)+hdr->offset,hdr->size);
    Free(tmp);
    Free(path_title);
  }
  Free(old_dir);
  Free(blobh);
  Free(filename);
}
U0 UndumpBlobFile(U8 *filename,U8 *dir="/Tmp",Bool delete=FALSE) {
  CDate newer_than=0;
  CDirEntry de,*finds,*cur;
  U8 *tmp,*ext;
  I64 trim,len,idx,cnt;
  U64 ch;
  CBlobFileHeader *final;
  CLumpHeader *lump_hdr;
  I64 total;
  filename=ExtDft(filename,"BLOB");
  if(FileFind(filename,&de)) {
    newer_than=de.datetime;
  }
  if(!FileFind(dir,&de)) {
    Free(filename);
    return;
  }
  if(delete) Del(filename);
  trim=StrLen(de.full_name);
  Free(de.full_name);
  tmp=MStrPrint("%s/*",dir);
  finds=FilesFind(tmp,FUF_RECURSE|FUF_JUST_FILES|FUF_FLATTEN_TREE);
  Free(tmp);
  total=sizeof(CBlobFileHeader);
  for(cur=finds;cur;cur=cur->next) {
    total+=sizeof(CLumpHeader);
    total+=cur->size;
  }
  final=CAlloc(total);
  total=sizeof(CBlobFileHeader);
  for(cur=finds;cur;cur=cur->next) {
    total+=sizeof(CLumpHeader);
  }
  lump_hdr=final->lump_table;
  cnt=0;
  for(cur=finds;cur;cur=cur->next) {
    tmp=FileRead(cur->full_name,&len);
    MemCpy(final(U8*)+total,tmp,len);

    if(ext=StrLastOcc(cur->full_name,".")) {
      *ext=0;
      ch=0;
      for(idx=0;idx<8&&ext[1+idx];idx++)
	ch.u8[idx]=ext[1+idx];
      lump_hdr->type=ch;
      StrCpy(lump_hdr->name,cur->full_name+trim+1);
      lump_hdr->size=len;
      lump_hdr->offset=total;
      lump_hdr++;
      total+=len;
      cnt++;
    }
    Free(tmp);
  }
  final->lump_cnt=cnt;
  FileWrite(filename,final,total);
  Free(final);
  DirTreeDel(finds);
  Free(filename); 
}


/*Del("ASS2.BLOB.Z");
BlobFileAddLump("ASS2","abc","abc",3,'TEXT');
BlobFileAddLump("ASS2","abd","abcd",4,'TEXT');
BlobFileAddLump("ASS2","ab/d","FILE",4,'TEXT');
"%s\n",BlobFileGetLump("ASS2","abd");
"%s\n",BlobFileSelect("ASS2");
BlobFileDeleteLump("ASS2","abd");
"%s\n",BlobFileSelect("ASS2");
"%s\n",BlobFileGetLump("ASS2","abc");
"%s\n",BlobFileGetLump("ASS2","ab/d");*/


//
//$BK,1$Cache the ass blob$BK,0$
//
GetBlobFileData("ASS.BLOB");

#ifdef DEVELOPMENT_MODE
Del("ASS.BLOB*");
//DumpBlobFile("ASS.BLOB","AssBlobDir");
UndumpBlobFile(#exe {StreamPrint("\"%Q\"",__DIR__);} "/ASS.BLOB",DEVELOPMENT_DIR);
#endif
#endif
