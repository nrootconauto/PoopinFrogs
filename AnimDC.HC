#ifndef ANIM_DC
#define ANIM_DC
#define ANIM_DELAY .25
U0 AnimDCDel(CDC *dc) {
  I64 idx=0;
  while(dc[idx].dc_signature==DCS_SIGNATURE_VAL) {
    dc[idx].dc_signature=0;
    Free(dc[idx].body);
    Free(dc[idx].r);
    Free(dc[idx].depth_buf);
    idx++;
  }
  Free(dc);
}
U8 *AnimDCSave(CDC *dc,I64 *_len=NULL) {
  I64 total_sz=8,cur_sz;
  I64 idx;
  U8 *ret,*tmp,*ptr;
  for(idx=0;dc[idx].dc_signature==DCS_SIGNATURE_VAL;idx++) {
     Free(DCSave(dc+idx,&cur_sz));
     total_sz+=cur_sz;
  }
  ptr=ret=CAlloc(total_sz);
  *ptr(I64*)++=idx;
  for(idx=0;dc[idx].dc_signature==DCS_SIGNATURE_VAL;idx++) {
    tmp=DCSave(dc+idx,&cur_sz);
    MemCpy(ptr,tmp,cur_sz);
    Free(tmp);
    ptr+=cur_sz;
  }
  if(_len) *_len=total_sz;
  return ret;
}
CDC *AnimDCLoad(U8 *ptr,I64 *_len=NULL,CTask *mem_task=NULL) {
  I64 cnt=*ptr(I64*);
  I64 len,cur_len,idx;
  CDC *ret=CAlloc((1+cnt)*sizeof(CDC),mem_task),*tmp;
  ptr+=8;
  len=8;
  for(idx=0;idx!=cnt;idx++) {
    tmp=DCLoad(ptr,&cur_len,mem_task);
    MemCpy(ret+idx,tmp,sizeof(CDC));
    len+=cur_len;
    ptr+=cur_len;
    Free(tmp);
  }
  if(_len) *_len=len;
  return ret;
}
U0 AnimDCBlot(CDC *dst,I64 x,I64 y,CDC *anim,I64 frame=I64_MAX) {
  I64 cnt=0;
  for(cnt=0;anim[cnt].dc_signature==DCS_SIGNATURE_VAL;cnt++);
  if(frame==I64_MAX)
    frame=ToI64(tS/ANIM_DELAY)%cnt;
  GrBlot(dst,x,y,anim+frame);
}
I64 AnimDCCnt(CDC *anim) {
  I64 cnt=0;
  for(cnt=0;anim[cnt].dc_signature==DCS_SIGNATURE_VAL;cnt++);
  return cnt;
}
CDC *AnimDCCopy(CDC *copy,CTask *mem_task,I64 exclude=-1) {
  I64 cnt=AnimDCCnt(copy),idx,ptr;
  CDC *ret=CAlloc(sizeof(CDC)*(cnt+1),mem_task),*tmp,*heap=CAlloc(sizeof(CDC));
  ptr=0;
  for(idx=0;idx<cnt;idx++) {
    if(exclude!=idx) {
      MemCpy(heap,copy+idx,sizeof(CDC));
//DCCopy wants MAllocIdent?
      MemCpy(ret+ptr++,tmp=DCCopy(heap,mem_task),sizeof(CDC));
      Free(tmp);
    }
  }
  Free(heap);
  return ret;
}
CDC *AnimDCResize(CDC *copy,I64 w,I64 h,I64 cx=0,I64 cy=0,CTask *mem_task=NULL) {
  I64 cnt=AnimDCCnt(copy);
  CDC *ret=CAlloc(sizeof(CDC)*(cnt+1),mem_task),*tmp,*heap=CAlloc(sizeof(CDC));
  while(--cnt>=0) {
    MemCpy(heap,copy+cnt,sizeof(CDC));
//DCCopy wants MAllocIdent?
    tmp=DCNew(w,h,mem_task);
    DCFill(tmp,TRANSPARENT);
    GrBlot(tmp,cx,cy,copy+cnt);
    MemCpy(ret+cnt,tmp,sizeof(CDC));
    Free(tmp);
  }
  Free(heap);
  return ret;
}
#endif