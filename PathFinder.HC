#ifndef PATH_FINDER
#define PATH_FINDER "cpuwaster"
#include "SmallTalk/Set.HC";
//Ignores wave
#define POINT_MASK 0xFFffFFffFFff
I64 class CPFPoint {
  I16 x,y;
  I16 z;
  I16 wave;
};
F64 Hueristic(CPFPoint a,CPFPoint b) {
  return Sqr(a.x-b.x)+Sqr(a.y-b.y)+Sqr(a.z-b.z);
}
U0 AddPoint(CPFPoint p,CPFPoint from,I64 score) {
  U8 buf[STR_LEN];
  CHashGeneric *gen;
//Ignore last 16bits(score)
  StrPrint(buf,"p.%X",p&POINT_MASK);
  if(gen=HashFind(buf,Fs->hash_table,HTT_FRAME_PTR)) {
    if(gen->user_data2<score)
      return;
    gen->user_data2=score;
    gen->user_data0=from;
    return;
  }
  HashGenericAdd(buf,HTT_FRAME_PTR,from,0,score);
}
//Returns CI64Set of CPFPoint
CI64Set *PathFinder(I64 x,I64 y,I64 z,I64 to_x,I64 to_y,I64 to_z,I64(*valid_tile)(I64,I64,I64),I64 jump=1.1,I64 max=10) {
  max=max*max;
  U8 buf[STR_LEN];
  CHashTable *t=HashTableNew(0x10),*old=Fs->hash_table;
  CI64Set *visited=I64SetNew,*frontier=I64SetNew;
  CI64Set *result=I64SetNew;
  I64 off;
  I64 ox,oy,iter=0,iter2,best_idx,wave=0;
  F64 best_val;
  CHashGeneric *tmpg;
  CPFPoint pt,pt_dst,pt2,best_pt;
  Fs->hash_table=t;
  t->next=old;

  pt.x=x,pt.y=y,pt.z=z;
  pt.wave=0;
  pt_dst.x=to_x,pt_dst.y=to_y,pt_dst.z=to_z;
  pt_dst.wave=0;
  AddPoint(pt,INVALID_PTR,Hueristic(pt,pt_dst));
  I64SetAdd(frontier,pt);
  wave=0;
  if(pt_dst==pt)
   goto fin;
    while(frontier->cnt) {
      if(++wave>max)
        break;
      best_val=I64_MAX;
      for(iter=0;iter!=frontier->cnt;iter++) {
        pt=frontier->body[iter];
        off=Hueristic(pt,pt_dst);
        if(off<best_val) {
	  best_val=off;
	  best_pt=pt;
	}
      }
      pt=best_pt;
      I64SetRem(frontier,pt);
      for(ox=-1;ox!=2;ox++)
        for(oy=-1;oy!=2;oy++) {
	  if(ox^^oy) {
	    for(off=1;off>=-1;off--) {
	      if((*valid_tile)(pt.x+ox,pt.y+oy,pt.z+off)) {
	        pt2.x=pt.x+ox;
	        pt2.y=pt.y+oy;
	        pt2.z=pt.z+off;
	        pt2.wave=wave;
	        if(!I64SetHas(visited,pt2&POINT_MASK)) {
		  AddPoint(pt2,pt,wave);
		  I64SetAdd(visited,pt&POINT_MASK);
		  I64SetAdd(frontier,pt2);
		  if(pt_dst&POINT_MASK==pt2&POINT_MASK) {
		    pt=pt2;
back_track:
		    iter=0;
		    do {
		      I64SetAdd(result,0);
		      StrPrint(buf,"p.%X",pt&POINT_MASK);
		      tmpg=HashSingleTableFind(buf,t,HTT_FRAME_PTR);
		      if(!tmpg) throw('Path');
		      pt=tmpg->user_data0;
		      iter++;
		    } while(pt!=INVALID_PTR);
		    iter=0;
		    do {
		      result->body[result->cnt-++iter]=pt2;
		      StrPrint(buf,"p.%X",pt2&POINT_MASK);
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
/*//Did not find exact value,so backtrack
  pt2=pt=best_pt;
  goto back_track;*/
fin:
  Fs->hash_table=old;
  HashTableDel(t);
  I64SetDel(visited);
  I64SetDel(frontier);
  return result;
}
#endif