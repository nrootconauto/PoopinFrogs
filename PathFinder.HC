#ifndef PATH_FINDER
#define PATH_FINDER "cpuwaster"
#include "SmallTalk/Set.HC";
I64 class CPFPoint {
  I16 x,y;
  I32 z; //Set to i32 to fill bits
};
F64 Hueristic(CPFPoint a,CPFPoint b) {
  return Sqr(a.x-b.x)+Sqr(a.y-b.y)+Sqr(a.z-b.z);
}
U0 AddPoint(CPFPoint p,CPFPoint from,F64 score) {
  U8 buf[STR_LEN];
  StrPrint(buf,"p.%X",p);
  HashGenericAdd(buf,HTT_FRAME_PTR,from,0,score);
}
//Returns CI64Set of CPFPoint
CI64Set *PathFinder(I64 x,I64 y,I64 z,I64 to_x,I64 to_y,I64 to_z,I64(*get_tile)(I64,I64,I64),I64 jump=1.1,I64 max=3) {
  U8 buf[STR_LEN];
  CHashTable *t=HashTableNew(0x10),*old=Fs->hash_table;
  CI64Set *visited=I64SetNew,*frontier=I64SetNew;
  CI64Set *result=I64SetNew;
  I64 off;
  I64 ox,oy,iter=0,iter2,best_idx;
  F64 best_val;
  CHashGeneric *tmpg;
  CPFPoint pt,pt_dst,pt2;
  Fs->hash_table=t;
  t->next=old;

  pt.x=x,pt.y=y,pt.z=z;
  pt_dst.x=to_x,pt_dst.y=to_y,pt_dst.z=to_z;
  I64SetAdd(visited,pt);
  AddPoint(pt,INVALID_PTR,Hueristic(pt,pt_dst));
  I64SetAdd(frontier,pt);
  while(frontier->cnt) {
    if(iter++>max)
      break;
    best_val=I32_MAX;
    best_idx=0;
    for(iter2=0;iter2!=frontier->cnt;iter2++) {
      pt=frontier->body[iter];
      if(best_val>Hueristic(pt_dst,pt)) {
        best_val=Hueristic(pt_dst,pt);
        best_idx=iter2;
      }
    }
    pt=frontier->body[best_idx];
    I64SetRem(frontier,pt);
    StrPrint(buf,"p.%X",pt);
    tmpg=HashSingleTableFind(buf,t,HTT_FRAME_PTR);
    for(ox=-1;ox!=2;ox++)
      for(oy=-1;oy!=2;oy++) {
        if(ox^^oy) {
	  for(off=1;off>=-1;off--) {
	    if(!(*get_tile)(pt.x+ox,pt.y+oy,pt.z+off)) {
	      pt2.x=pt.x+ox;
	      pt2.y=pt.y+oy;
	      pt2.z=pt.z+off;
	      if(!I64SetHas(visited,pt2)) {
	        I64SetAdd(visited,pt2);
	        StrPrint(buf,"p.%X",pt);
	        I64SetAdd(frontier,pt2);
	        AddPoint(pt2,pt,Hueristic(pt,pt_dst));
	        if(pt_dst==pt2) {
		  pt=pt2;
		  iter=0;
		  do {
		    I64SetAdd(result,0);
		    StrPrint(buf,"p.%X",pt);
		    tmpg=HashSingleTableFind(buf,t,HTT_FRAME_PTR);
		    if(!tmpg) throw('Path');
		    pt=tmpg->user_data0;
		    iter++;
		  } while(pt!=INVALID_PTR);
		  iter=0;
		  do {
		    result->body[result->cnt-++iter]=pt2;
		    StrPrint(buf,"p.%X",pt2);
		    tmpg=HashSingleTableFind(buf,t,HTT_FRAME_PTR);
		    if(!tmpg) throw('Path');
		    pt2=tmpg->user_data0;
		  } while(pt2!=INVALID_PTR);
		  goto fin;
	        }
	      } else
	        break;
	    }
	  }
        }
      }
  }
fin:
  Fs->hash_table=old;
  HashTableDel(t);
  I64SetDel(visited);
  I64SetDel(frontier);
  return result;
}
#endif