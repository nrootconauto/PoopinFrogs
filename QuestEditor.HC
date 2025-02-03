#include "BlobFile.HC";
#include "SmallTalk/Load.HC";;;
#exe{ Cd(__DIR__);;};
#define QUEST_DIR "Quests/"
#define QUESTCODE_EDIT 1 
#define QUESTCODE_DELETE 0b11 
#define QUESTCODE_CHOOSE 0b101 
#define QUESTCODE_SUB_QUEST 0b110 
#define QUESTCODE_META 0b111 
class CQuestEntry {
  U8 code_name[STR_LEN];
  U8 input[STR_LEN] format "$$DA-P,A=\"Input Keywords:%s\"$$\n";
  U8 first_output[STR_LEN] format "$$DA-P,A=\"First Output:%s\"$$\n";
  U8 again_output[STR_LEN] format "$$DA-P,A=\"Again Output:%s\"$$\n";
//Comma seperated
  U8 add_keywords[STR_LEN] format "$$DA-P,A=\"Add Keywords:%s\"$$\n";
//Comma seperated
  U8 remove_keywords[STR_LEN] format "$$DA-P,A=\"Remove Keywords:%s\"$$\n"; 
//Comma seperated
  U8 need_keywords[STR_LEN] format "$$DA-P,A=\"Need Keywords:%s\"$$\n"; 
//Remove item(SmallTalk ClassName).
  U8 remove_item[STR_LEN] format "$$DA-P,A=\"Remove Item:%s\"$$\n";
  I64 remove_item_cnt format"$$DA-TRM,A=\"RemoveCnt:%d\"$$\n"; //See above
//Give item
  U8 give_item[STR_LEN] format "$$DA-P,A=\"Add Item:%s\"$$\n";
  I64 give_item_cnt format "$$DA-TRM,A=\"Add Cnt:%d\"$$\n"; //See above
};
#define QUEST_INFO_NAME "QuestInfo"
class CQuestInfo {
//Inherit the reponses from this quest UNUSED
  U8 inherit_quest[STR_LEN] format "$$DA-P,A=\"Inherit Quest:%s\"$$\n";
  U8 hello[STR_LEN] format "$$DA-P,A=\"Hello:%s\"$$\n";
  U8 bye[STR_LEN] format "$$DA-P,A=\"Bye:%s\"$$\n";
};
//Displays sub entries
//nest_level==2 when /Quests/Name/entry
U0 DispQuestEntry(CDoc *d,CQuestEntry *entry,I64 idx,CBlobFileHeader *lumps,I64 nest_level=2) {
  CLumpHeader *hdr=&lumps->lump_table[idx],*sub;
  if(StrOcc(hdr->name,'/')!=nest_level) return;
  DocPrint(d,"$$TR-C,\"%Q\"$$",entry->code_name);
  DocPrint(d,"$$ID,2$$\n");
  DocPrint(d,"Input:\t$$LTBLUE$$%Q$$FD$$\n",entry->input);
  DocPrint(d,"First Output:\t$$LTBLUE$$%Q$$FD$$\n",entry->first_output);
  DocPrint(d,"Again Output:\t$$LTBLUE$$%Q$$FD$$\n",entry->again_output);
  DocPrint(d,"Add Keywords:\t$$LTBLUE$$%Q$$FD$$\n",entry->add_keywords);
  DocPrint(d,"Remove Keywords:\t$$LTBLUE$$%Q$$FD$$\n",entry->remove_keywords);
  DocPrint(d,"Need Keywords:\t$$LTBLUE$$%Q$$FD$$\n",entry->need_keywords);
  DocPrint(d,"Remove CHandItem:\t$$LTBLUE$$%Q$$FD$$\n",entry->remove_item);
  DocPrint(d,"Give CHandItem:\t$$LTBLUE$$%Q$$FD$$\n",entry->give_item);
  DocPrint(d,"\n$$RED$$");
  DocPrint(d,"$$MU,\"(Edit)\",LE=%d$$ ",idx<<3|QUESTCODE_EDIT);
  DocPrint(d,"$$MU,\"(Sub-Quest)\",LE=%d$$ ",idx<<3|QUESTCODE_SUB_QUEST);
  DocPrint(d,"$$MU,\"(Delete)\",LE=%d$$$$FD$$",idx<<3|QUESTCODE_DELETE);
  DocPrint(d,"\n");
//Display sub-quests
  idx=0;
  while(idx<lumps->lump_cnt) {
    sub=&lumps->lump_table[idx];
    if(!StrNCmp(hdr->name,sub->name,StrLen(hdr->name))) {
       DispQuestEntry(d,lumps(U8*)+sub->offset,idx,lumps,nest_level+1);
    }
    idx++;
  }
  DocPrint(d,"$$ID,-2$$\n");
  return;
}
CFrogArray *SplitItems(U8 *poo_poo) {
  U8 dummy[STR_LEN];
  CFrogArray *ret=FrogArrayNew;
  I64 cnt=1;
  StrCpy(dummy,poo_poo);
  StrUtil(dummy,SUF_REM_SPACES);
  while(StrOcc(dummy,',')) {
    *StrFirstOcc(dummy,",")=0;
    cnt++;
  }
  while(--cnt>=0)
  CallScript("add:",ret,FrogStrNew(LstSub(cnt,dummy)));
  return ret;
}
CEliza *LoadQuestChatBot(U8 *quest_name,U8 *ass_blob=NULL,I64 nest_level=2) {
  if(!ass_blob)
    ass_blob=blob_file_cache.filename;
  ass_blob=ExtDft(ass_blob,"BLOB");
  CBlobFileHeader *lumps=FileRead(ass_blob);
  CLumpHeader *hdr,*hdr2;
  I64 cnt=lumps->lump_cnt,code,idx,cnt2;
  U8 *wildcard=MStrPrint(QUEST_DIR"%s/*",quest_name);
  U8 *info_lump=MStrPrint(QUEST_DIR"%s/"QUEST_INFO_NAME,quest_name);
  U8 sep[STR_LEN];
  CEliza *e=ConstructThing("CEliza"),*inherit,*sub;
  CElizaReasm *r;
  CQuestEntry *ent;
  CQuestInfo *info_ent=NULL;
  CallScript("init",e);
  while(--cnt>=0) {
    hdr=&lumps->lump_table[cnt];
    if(!StrCmp(hdr->name,info_lump)) {
//Do it later
      info_ent=hdr->offset+lumps(U8*);
    } else if(WildMatch(hdr->name,wildcard)) {
      if(nest_level==StrOcc(hdr->name,'/')) {
        ent=lumps(U8*)+hdr->offset;
        r=ConstructThing("CElizaReasm");
        CallScript("init",r);
        CallScript("initFromString:",r,FrogStrNew(ent->input));
        r->first_result=FrogStrNew(ent->first_output);
        r->global_response_name=FrogStrNew(hdr->name);
        if(*ent->add_keywords)  r->add_flags=SplitItems(ent->add_keywords);
        if(*ent->remove_keywords) r->remove_flags=SplitItems(ent->remove_keywords);
        if(*ent->need_keywords) r->need_flags=SplitItems(ent->need_keywords);
        if(HashFind(ent->give_item,Fs->hash_table,HTT_CLASS))
	  r->give_item_class=FrogClassNew(UniverseAddClass(ent->give_item));
/*Check for sub responmses*/
        cnt2=lumps->lump_cnt;
        while(--cnt2>=0) {
	  hdr2=&lumps->lump_table[cnt2];
	  if(!StrNCmp(hdr->name,hdr2->name,StrLen(hdr->name))) {
	    if(hdr2->name[StrLen(hdr->name)]=='/') {
//Sub-response
//$BK,1$(IMPORTANT) Add StrLen(QUEST_DIR) to ignore /Quests/$BK,0$
	      sub=LoadQuestChatBot(hdr->name+StrLen(QUEST_DIR),ass_blob,nest_level+1);
//Set the hello message with the parent result
	      sub->hello=r->first_result;
//Parent result is now sub-reposne
	      r->first_result=sub;
	      break;
	    }
	  }
        }
        if(ent->again_output[0])
	  r->again_result=FrogStrNew(ent->again_output);
        else
	  r->again_result=r->first_result;
        CallScript("addReasm:",e,r);
      }
    }
  }
  if(info_ent) {
//Use FramePtr to avoid infinite recursion
    if(info_ent->inherit_quest[0]&&!FramePtr(info_ent->inherit_quest)) {
      FramePtrAdd(info_ent->inherit_quest);
      inherit=LoadQuestChatBot(info_ent->inherit_quest,ass_blob);
      CallScript("inheritOther:",e,inherit);
      FramePtrDel(info_ent->inherit_quest);
    }
    if(info_ent->hello[0])
      e->hello=FrogStrNew(info_ent->hello);
    if(info_ent->bye[0])
      e->quit=FrogStrNew(info_ent->bye);
  }
  Free(info_lump);
  Free(ass_blob);
  Free(lumps);
  Free(wildcard);
  return e;
}
Bool EditQuest(U8 *ass_blob,U8 *name) {
  U8 *tmp,*oname=name,*info_lump;
ent:
  CDoc *d=DocNew;
  DocClear(d);
  CBlobFileHeader *lumps=FileRead(ass_blob);
  CLumpHeader *hdr;
  I64 cnt=lumps->lump_cnt,code,idx;
  Bool continue=TRUE;
  CQuestEntry *ent,dummy;
  CQuestInfo *info_ent,info_dummy;
  name=MStrPrint(QUEST_DIR"%s/*",oname);
  info_lump=MStrPrint(QUEST_DIR"%s/"QUEST_INFO_NAME,oname);
  idx=0;
  while(idx<cnt) {
    hdr=&lumps->lump_table[idx];
    if(!StrCmp(info_lump,hdr->name)) {
    } else if(WildMatch(hdr->name,name)) {
      DispQuestEntry(d,hdr->offset+lumps(U8*),idx,lumps);
    }
    idx++;
  }

  DocPrint(d,"$$RED$$$$MU,\"New Entry\",LE=%d$$ ",-1<<3|QUESTCODE_EDIT);
  DocPrint(d,"$$MU,\"Edit Meta-Info\",LE=%d$$$$FD$$",QUESTCODE_META);

  code=PopUpMenu(d);
  if(code==DOCM_CANCEL) {
    continue=FALSE;
    goto fin;
  }
  idx=code>>3;
  hdr=&lumps->lump_table[idx];
  switch(code&0b111) {
    case QUESTCODE_META:
      MemSet(&info_dummy,0,sizeof(CQuestInfo));
      info_ent=BlobFileGetLump(ass_blob,info_lump);
      if(!info_ent)
	info_ent=&info_dummy;
      PopUpForm(info_ent,"CQuestInfo");
      BlobFileAddLump(ass_blob,info_lump,info_ent,sizeof(CQuestInfo));
      if(info_ent!=&info_dummy)
	Free(info_ent);
      break;
    case QUESTCODE_DELETE:
      BlobFileDeleteLump(ass_blob,hdr->name);
      break;
    case QUESTCODE_EDIT:
      MemSet(&dummy,0,sizeof(CQuestEntry));
      if(idx==-1) {
	tmp=PopUpGetStr("Codename for New Entry:");
	StrCpy(dummy.code_name,tmp);
	Free(tmp);
	ent=&dummy;
      } else {
        ent=hdr->offset+lumps(U8*);
      }
      PopUpForm(ent,"CQuestEntry");
      tmp=MStrPrint(QUEST_DIR"%s/%s",oname,ent->code_name);
      BlobFileAddLump(ass_blob,tmp,ent,sizeof(CQuestEntry));
      Free(tmp);
      break;
    case QUESTCODE_SUB_QUEST:
      MemSet(&dummy,0,sizeof(CQuestEntry));
      tmp=PopUpGetStr("Codename for New Sub-Entry:");
      StrPrint(dummy.code_name,"%s",tmp);
      Free(tmp);
      PopUpForm(&dummy,"CQuestEntry");
      tmp=MStrPrint("%s/%s",hdr->name,dummy.code_name);
      BlobFileAddLump(ass_blob,tmp,&dummy,sizeof(CQuestEntry));
      Free(tmp);
      break;
  }
fin:
  Free(info_lump);
  Free(lumps);
  Free(name);
  DocDel(d);
  if(continue)
   goto ent;
}

U0 DeleteQuest(U8 *ass_blob,U8 *name) {
  name=MStrPrint(QUEST_DIR"%s/*",name);
  CBlobFileHeader *lumps=FileRead(ass_blob);
  CLumpHeader *hdr;
  I64 cnt=lumps->lump_cnt;
  while(--cnt>=0) {
    hdr=&lumps->lump_table[cnt];
    if(WildMatch(hdr->name,name)) {
      BlobFileDeleteLump(ass_blob,hdr->name);
    }
  }
  Free(lumps);
  Free(name);
}

U0 QuestEditor(U8 *blob_file=NULL,U8 *write_quest_name_to=NULL) {
  Bool continue=TRUE;
  if(!blob_file)
    blob_file=blob_file_cache.filename;
ent:
  blob_file=ExtDft(blob_file,"BLOB");
  if(!FileFind(blob_file)) {
    PopUpOk("Cant Find Blob file!!!");
    Free(blob_file);
    return;
  }
  CDoc *menu=DocNew;
  CBlobFileHeader *lumps=FileRead(blob_file);
$IV,0$  CLumpHeader *hdr;
  I64 cnt=lumps->lump_cnt,idx;
  U8 *tmp,dummy[STR_LEN],*dummy_ptr;
  while(--cnt>=0) {
    hdr=&lumps->lump_table[cnt];
    if(!StrNCmp(hdr->name,QUEST_DIR,StrLen(QUEST_DIR))) {
      dummy_ptr=dummy;
      StrScan(hdr->name,QUEST_DIR"%s/",&dummy_ptr);
      tmp=MStrPrint("Quests/%s",dummy);
      if(write_quest_name_to) {
        DocTreeWrite(menu,tmp,FALSE,
          "$$RED$$$$MU,\"(Choose)\",LE=%d$$ $$MU,\"(Edit)\",LE=%d$$ $$MU,\"(Delete)\",LE=%d$$$$FD$$\n",
	  QUESTCODE_CHOOSE|cnt<<3,
	  QUESTCODE_EDIT|cnt<<3,
	  QUESTCODE_DELETE|cnt<<3
        );
      } else {
        DocTreeWrite(menu,tmp,FALSE,
          "$$RED$$$$MU,\"(Edit)\",LE=%d$$ $$MU,\"(Delete)\",LE=%d$$$$FD$$\n",
	  QUESTCODE_EDIT|cnt<<3,
	  QUESTCODE_DELETE|cnt<<3
        );
      }
      Free(tmp);
    }
  }
  DocBottom(menu);
  DocPrint(menu,"$$RED$$$$MU,\"(New Quest)\",LE=%d$$$$FD$$",-1<<3|QUESTCODE_EDIT);
  I64 code=PopUpMenu(menu);
  if(code==DOCM_CANCEL) {
    continue=FALSE;
    goto fin;
  }
  idx=code>>3;
  DocClear(menu);
  switch(code&0b111) {
    case QUESTCODE_EDIT:
    if(idx==-1)
      tmp=PopUpGetStr("New Quest Name:");
    else {
      tmp=StrNew(lumps->lump_table[idx].name+StrLen(QUEST_DIR));
// It has form quest_name/Entry(we only want the quest name)
      if(StrOcc(tmp,'/')) *StrFirstOcc(tmp,"/")=0;
    }
    EditQuest(blob_file,tmp);
    Free(tmp);
    break;
    case QUESTCODE_CHOOSE:
    tmp=StrNew(lumps->lump_table[idx].name+StrLen(QUEST_DIR));
// It has form quest_name/Entry(we only want the quest name)
    if(StrOcc(tmp,'/')) *StrFirstOcc(tmp,"/")=0;
    if(write_quest_name_to) StrCpy(write_quest_name_to,tmp);
    Free(tmp);
    continue=FALSE;
    break;
    case QUESTCODE_DELETE:
    if(PopUpNoYes("Are you sure?\n"))
      DeleteQuest(blob_file,lumps->lump_table[idx].name);
    break;
  }
fin:
  Free(lumps);
  Free(blob_file);
  DocDel(menu);
  if(continue) goto ent;
}
CEliza *ElizaNewFromBlob(CFrogClass *ul,I64 *argv,I64 *argc) {
  U8 *s=AsString(argv[0]);
  if(!s) return FROG_SMALL_NIL;
  CEliza *e=LoadQuestChatBot(s);
  Free(s);
  if(!e) return FROG_SMALL_NIL;
  return e;
}
AddClassMethod("CEliza","newFromBlob:",&ElizaNewFromBlob);
#if __CMD_LINE__
QuestEditor;
#define TEST_QUEST 1
#endif
#ifdef TEST_QUEST
CEliza *eliza=LoadQuestChatBot("Test123");
CFrogStr *poo_poo;
poo_poo=CallScript("message:",eliza,FrogStrNew("yes"));
"HELLO:%s\n",AsString(poo_poo);
poo_poo=CallScript("message:",eliza,FrogStrNew("I like video games"));
"I EAT *:%s\n",AsString(poo_poo);
poo_poo=CallScript("message:",eliza,FrogStrNew("blue"));
"CAN * HAVE * :%s\n",AsString(poo_poo);
poo_poo=CallScript("message:",eliza,FrogStrNew("YES"));
"* YES * :%s\n",AsString(poo_poo);
poo_poo=CallScript("message:",eliza,FrogStrNew("YES"));
"* YES * :%s\n",AsString(poo_poo);
#endif
