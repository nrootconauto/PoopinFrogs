#include "AnimDC.HC"
#include "BlobFile.HC";
#include "SmallTalk/Load.HC"
#include "Intersect.HC";
#define TEST_3D
#ifndef ENGINE_3D
#define ENGINE_3D 1
#define SCRN_TURN_MARGIN 100
#define SCRN_TURN_RATE (pi/30.)

//
// From LevelEditor.HC
//
class CFilePtrLen {
  I32 ptr;
  I32 len;
};
class CFileTexture {
  I64 idx;
  U8 blob_name[STR_LEN];
  U8 wall_blob_name[STR_LEN];
  U8 ceil_blob_name[STR_LEN];
};

class CFileThingTemplate {
  I16 idx;
  U8 name[STR_LEN];
  U8 data[STR_LEN];
  U8 blob_side_name[STR_LEN];
  U8 blob_front_name[STR_LEN];
  U8 blob_back_name[STR_LEN];
};
class CFileThing {
  U16 thing_template_idx;
//x/y are in tiles 
  F64 x,y,rot;
}
class CFileWorld {
  I64 w,h;
  I64 startx,starty;
  I16 *data;
  CFilePtrLen textures_where;
  CFilePtrLen thing_templates_where;
  CFilePtrLen things_where;
  CFilePtrLen heightmap;
  CFilePtrLen ceilmap;
  CFilePtrLen ceilmap2;
}; 


class CBlockedView {
  I16 start,end;
  I32 dist;
};

F64 cos_lookup_table[GR_WIDTH];
F64 cos2_lookup_table[GR_WIDTH];
F64 sin_lookup_table[GR_WIDTH];
F64 tan_lookup_table[GR_WIDTH];
U0 InitTables(F64 base,F64 fov) {
  F64 angle=base-fov/2,angle2=-fov/2;
  I64 idx;
  for(idx=0;idx!=GR_WIDTH;idx++) {
   cos2_lookup_table[idx]=Cos(angle2);
   cos_lookup_table[idx]=Cos(angle);
   sin_lookup_table[idx]=Sin(angle);
   tan_lookup_table[idx]=Tan(angle);
   angle2+=fov/GR_WIDTH;
   angle+=fov/GR_WIDTH;
  }
}

class C3DParticle:CQue {
  F64 x,y,z,born_at;
  F64 momx,momy,momz;
  I32 color,size;
};

#define GRID_SZ 128
#define THING_RADIUS (GRID_SZ/2)
#define DIST_SCALE (GR_HEIGHT*GRID_SZ)
#define EMPTY_SPACE 0
class C3DWorld {
   F64 fov,x,y,h,angle;
   I64 step_width,step_width_y;
   I64 world_width;
   I64 world_height;
   I16 *world_mat; //0 is for EMPTY_SPACE
   I8 *heightmap,*ceilmap,*ceilmap2;
   CDC *wall_textures[0x10000/2],*to_dc;
   CDC *floor_textures[0x10000/2];
   CDC *ceil_textures[0x10000/2];
   I64 mp_done,dc_lock;
   CQue _2d_thing_templates; 
   CI64Set *_2d_things;
   CI64Set *_wall_stains;
   CI64Set *_floor_stains;
   CTask *mem_task;
   F64 cam_height;
//Private
   F64 plane_dist;
   CBlockedView blocked_views[GR_WIDTH][0x80];
   I64 blocked_cnts[GR_WIDTH];
   CQue particles;
   I64 particle_cnt;
};
extern U0 Draw2DThing(C3DWorld *w,C2DThing *thing);
#define MAX_PARTICLES 64
U0 NewParticle(C3DWorld *w,I64 color,I64 sz,F64 x,F64 y,F64 z,F64 mx,F64 my,F64 mz) {
  C3DParticle *p;
  if(w->particle_cnt>=MAX_PARTICLES) {
    w->particle_cnt--;
    QueRem(p=w->particles.next);
    Free(p);
  }
  p=MAlloc(sizeof(C3DParticle),w->mem_task);
  p->color=color;
  p->size=sz;
  p->x=x;
  p->y=y;
  p->z=z;
  p->momx=mx;
  p->momy=my;
  p->momz=mz;
  p->born_at=tS;
  QueIns(p,w->particles.last);
  w->particle_cnt++;
}
#define THINGF_FACE_FORWARD 1
//These are defined in the blob header.
U0 C2DThingTemplateDel(C2DThingTemplate *t) {
  DCDel(t->front);
  DCDel(t->side);
  DCDel(t->back);
  Free(t);
}
U0 C3DWorldSetFov(C3DWorld *w,F64 fov=pi/4) {
  w->fov=fov;
  w->plane_dist=(GR_WIDTH/2)/(Tan(fov/2));
}
//Returns the first availbe y pixel for a distance(checks whats blocked),or returns input y if ok
I64 VisSkipTo(C3DWorld *w,I64 x,I64 y,I64 dist) {
  I64 cnt=w->blocked_cnts[x],idx;
  CBlockedView *blocked;
enter:
  for(idx=0;idx!=cnt;idx++) {
    blocked=&w->blocked_views[x][idx];
    if(blocked->dist<dist) {
      if(blocked->start<=y<blocked->end) {
	y=blocked->end;
        goto enter;
      }
    }
  }
  return y;
}
C3DWorld *LoadWorldFromFile(U8 *blob_file="ASS",U8 *filename,F64 fov=pi/4) {
  C3DWorld *ret=CAlloc(sizeof(C3DWorld));
  CFileWorld *world=BlobFileGetLump(blob_file,filename);
  F64 xoff,yoff;
  U8 *fptr=world,*to,*tmp;
  I64 idx;
  CDC *unscaled;
  C2DThingTemplate **templates=CAlloc(0x10000*8),*template;
  C2DThing *thing;
  C3DWorldManager *man;
  C3DWorldSetFov(ret,fov);
  QueInit(&ret->particles);
  ret->to_dc=DCNew(GR_WIDTH,GR_HEIGHT);
  DCDepthBufAlloc(ret->to_dc);
  ret->step_width=4;  
  ret->step_width_y=4;
  ret->world_width=world->w;
  ret->world_height=world->h;
  ret->world_mat=MAlloc(2*world->h*world->w);
  ret->heightmap=MAlloc(world->h*world->w);
  ret->ceilmap=MAlloc(world->h*world->w);
  ret->ceilmap2=MAlloc(world->h*world->w);
  xoff=GRID_SZ*world->startx;
  yoff=GRID_SZ*world->starty;
  QueInit(&ret->_2d_thing_templates);
  MemCpy(ret->world_mat,world+1,2*world->h*world->w);
  MemCpy(ret->heightmap,world(U8*)+world->heightmap.ptr,world->h*world->w);
  MemCpy(ret->ceilmap,world(U8*)+world->ceilmap.ptr,world->h*world->w);
  MemCpy(ret->ceilmap2,world(U8*)+world->ceilmap2.ptr,world->h*world->w);
  man=ConstructThing("C3DWorldManager","world_handle",ret);
  CallScript("init",man);
  ret->_wall_stains=man->wall_stains->items;
  ret->_floor_stains=man->floor_stains->items;
  ret->_2d_things=man->things->items;
  fptr=world(U8*)+world->textures_where.ptr;
  to=fptr+world->textures_where.len;
  while(fptr<to) {
    idx=fptr(CFileTexture*)->idx;
    tmp=BlobFileGetLump(blob_file,fptr(CFileTexture*)->blob_name);
    unscaled=AnimDCLoad(tmp);
    if(idx>0)
      ret->floor_textures[idx]=ScaleDC(unscaled,GRID_SZ,GRID_SZ);
    else
      ret->floor_textures[-idx]=ScaleDC(unscaled,GRID_SZ,GRID_SZ);
    AnimDCDel(unscaled);
    Free(tmp);
    tmp=BlobFileGetLump(blob_file,fptr(CFileTexture*)->wall_blob_name);
    unscaled=AnimDCLoad(tmp);
    if(idx>0)
      ret->wall_textures[idx]=ScaleDC(unscaled,GRID_SZ,GRID_SZ);
    else
      ret->wall_textures[-idx]=ScaleDC(unscaled,GRID_SZ,GRID_SZ);
    AnimDCDel(unscaled);
    Free(tmp);
    tmp=BlobFileGetLump(blob_file,fptr(CFileTexture*)->ceil_blob_name);
    if(tmp) {
      unscaled=AnimDCLoad(tmp);
      if(idx>0)
        ret->ceil_textures[idx]=ScaleDC(unscaled,GRID_SZ,GRID_SZ);
      else
        ret->ceil_textures[-idx]=ScaleDC(unscaled,GRID_SZ,GRID_SZ);
      AnimDCDel(unscaled);
      Free(tmp);
    }
    fptr(CFileTexture*)++;
  }
  fptr=world(U8*)+world->thing_templates_where.ptr;
  to=fptr+world->thing_templates_where.len;  
  while(fptr<to) {
    template=ConstructThing("C2DThingTemplate");
    idx=fptr(CFileThingTemplate*)->idx;
    templates[idx-I16_MIN]=template;
    tmp=BlobFileGetLump(blob_file,fptr(CFileThingTemplate*)->blob_front_name);
    if(tmp)
      template->front=AnimDCLoad(tmp);
    Free(tmp);
    tmp=BlobFileGetLump(blob_file,fptr(CFileThingTemplate*)->blob_back_name);
    if(tmp)
      template->back=AnimDCLoad(tmp);
    Free(tmp);
    tmp=BlobFileGetLump(blob_file,fptr(CFileThingTemplate*)->blob_side_name);
    if(tmp)
      template->side=AnimDCLoad(tmp);
    Free(tmp);
    CallScript("addThingTemplate:withName:",man,template,FrogStrNew(fptr(CFileThingTemplate*)->name));
    fptr(CFileThingTemplate*)++;
  }
  fptr=world(U8*)+world->things_where.ptr;
  to=fptr+world->things_where.len;
  while(fptr<to) {
    template=templates[fptr(CFileThing*)->thing_template_idx-I16_MIN];
    if(template) {
      tmp=AsString(template->name);
      if(thing=ConstructThing(tmp)) {
        if(ThingHasClass(thing,"C2DThing")) {
	  thing->x=fptr(CFileThing*)->x*GRID_SZ-xoff;
	  thing->y=fptr(CFileThing*)->y*GRID_SZ-yoff;
	  thing->angle=fptr(CFileThing*)->rot;
	  CallScript("init",thing);
	  I64SetAdd(ret->_2d_things,thing);
        } else
	  ThingDel(thing);
      }
      Free(tmp);
    }
    fptr(CFileThing*)++;
  }
  Free(world);
  Free(templates);
  return ret;
}


I64 WallForCord(C3DWorld *w,I64 x,I64 y,I64 h=I64_MIN) {
  I64 t;
  if(0<=x<w->world_width)
    if(0<=y<w->world_height) {
      t=w->world_mat[x+y*w->world_width];
      if(t<=0) return 0;
      if(w->wall_textures[t]&&w->heightmap[x+y*w->world_width]>h)
         return t;
      return 0;
    }
  return -1;
}
I64 FloorForCord(C3DWorld *w,I64 x,I64 y) {
  I64 t;
  if(0<=x<w->world_width)
    if(0<=y<w->world_height) {
      t=w->world_mat[x+y*w->world_width];
      if(t>=0) return 0;
      if(w->floor_textures[-t])
        return -t;
      return 0;
    }
  return -1;
}
I64 SegmentModulo(F64 f,I64 i) {
  I64 off=f+i*GRID_SZ;
  if(off>0) return off%GRID_SZ;
  if(off<0) return (GRID_SZ-off)%GRID_SZ;
  return 0;
}
I64 PassesThoughBlock(C3DWorld *w,F64 slope,I64 x,I64 y,F64 *dist,F64 cos,F64 sin,Bool far_side=FALSE) {
  switch(WallForCord(w,x,y)) {
    case -1:
    case 0:
      return FALSE;
  }
  I64 found=FALSE,found_side;
  F64 smallest=1e100,biggest=-1.;
  F64 cx1=x*GRID_SZ,cy1=y*GRID_SZ;
  F64 cx2=cx1+GRID_SZ,cy2=cy1+GRID_SZ;
  F64 tmp;
  cx1=(cx1-w->x)/GRID_SZ;
  cx2=(cx2-w->x)/GRID_SZ;
  cy1=(cy1-w->y)/GRID_SZ;
  cy2=(cy2-w->y)/GRID_SZ;
  if(cos==0.) {
    x=x*GRID_SZ;
    y=y*GRID_SZ;
    if(sin>0.) {
      if(dist) *dist=y*GRID_SZ-w->y;
      return x<=w->x<=x+GRID_SZ&&w->y<=y;
    }
    if(dist) *dist=w->y-(y+1)*GRID_SZ;
    return x<=w->x<=x+GRID_SZ&&w->y>=y+GRID_SZ;
  }
  if(sin==0.) {
    x=x*GRID_SZ;
    y=y*GRID_SZ;
    if(cos>0.) {
      if(dist) *dist=x*GRID_SZ-w->x;
      return y<=w->y<=y+GRID_SZ&&w->x<=x;
    }
    if(dist) *dist=w->x-(x+1)*GRID_SZ;
    return y<=w->y<=y+GRID_SZ&&w->x>=x+GRID_SZ;
  }
  if(cos>0.^^far_side) {
//Left side
    tmp=cx1*slope;
    if(cy1<=tmp<=cy2) {
      tmp=Sqrt(Sqr(cx1*GRID_SZ)+Sqr(tmp*GRID_SZ));
      smallest=Min(smallest,tmp);
      biggest=Max(biggest,tmp);
      found=TRUE;
    }
  } else {
//Right side
    tmp=cx2*slope;
    if(cy1<=tmp<=cy2) {
      found=TRUE;
      tmp=Sqrt(Sqr(cx2*GRID_SZ)+Sqr(tmp*GRID_SZ));
      smallest=Min(smallest,tmp);
      biggest=Max(biggest,tmp);
    }
  }
  if(sin>0.^^far_side) {
//top side
    tmp=cy1/slope;
    if(cx1<=tmp<=cx2) {
      tmp=Sqrt(Sqr(cy1*GRID_SZ)+Sqr(tmp*GRID_SZ));
      smallest=Min(smallest,tmp);
      biggest=Max(biggest,tmp);
      found=TRUE;
    }
  } else {
//bottom side
    tmp=cy2/slope;
    if(cx1<=tmp<=cx2) {
      tmp=Sqrt(Sqr(cy2*GRID_SZ)+Sqr(tmp*GRID_SZ));
      smallest=Min(smallest,tmp);
      biggest=Max(biggest,tmp);
      found=TRUE;
    }
  }
  if(dist) {
    if(!far_side)
      *dist=smallest;
    else
      *dist=biggest;
  }
  return found;
}
Bool HeightPasses(C3DWorld *w,I64 ix,I64 iy,I64 above) {
  if(0<=ix<w->world_width)
    if(0<=iy<w->world_height)
      return above<w->heightmap[iy*w->world_width+ix];
  return FALSE;
}
I64 FindRayWall(C3DWorld *w,F64 slope,F64 cos,F64 sin,I64 *segment=NULL,F64 *dist=NULL,I64 *side=NULL,I64 above=I8_MIN,I64 force_tile=INVALID_PTR,Bool far_side=FALSE) {
  F64 x=w->x;
  F64 y=w->y;
  Bool found_hit=FALSE;
  I64 ix=x/GRID_SZ,iy=y/GRID_SZ,iy2,seg,ix2;
  F64 smallest=1e100;
  F64 hit_x=-1,hit_y=-12345,dist2=32*GRID_SZ,check_dist=0,t1,t2,wall_x,wall_y,res_dist;
  I64 sign_c=Sign(cos),sign_s=Sign(sin);
  static F64 step=GRID_SZ-1;
  if(force_tile!=INVALID_PTR) {
    ix=force_tile%w->world_width;
    iy=force_tile/w->world_width;
    PassesThoughBlock(w,slope,ix,iy,&res_dist,cos,sin,far_side);
    smallest=res_dist;
    check_dist=res_dist;
    ix2=ix;
    iy2=iy;
    found_hit=TRUE;
    goto final;
  }
  while(check_dist<dist2) {
    check_dist+=step;
    x=w->x+check_dist*cos;
    y=w->y+check_dist*sin;
    ix=x/GRID_SZ,iy=y/GRID_SZ;
    if(HeightPasses(w,ix,iy,above)&&PassesThoughBlock(w,slope,ix,iy,&res_dist,cos,sin)) {
      found_hit=TRUE;
      if(res_dist<smallest) {
        smallest=res_dist;
        ix2=ix;
        iy2=iy;
      }
    }
    if(check_dist>ToF64(GRID_SZ)) {
      if(HeightPasses(w,ix-sign_c,iy,above)&&PassesThoughBlock(w,slope,ix-sign_c,iy,&res_dist,cos,sin)) {
        found_hit=TRUE;
        if(res_dist<smallest) {
	  smallest=res_dist;
	  ix2=ix-sign_c;
	  iy2=iy;
        }
      }
      if(HeightPasses(w,ix,iy-sign_s,above)&&PassesThoughBlock(w,slope,ix,iy-sign_s,&res_dist,cos,sin)) {
        found_hit=TRUE;
        if(res_dist<smallest) {
	  smallest=res_dist;
	  ix2=ix;
	  iy2=iy-sign_s;
        }
      }
    }
    if(found_hit) goto final;
skip:;
  }
  goto undef;
fin:
  if(dist) *dist=dist2;
  if(0<=ix<w->world_width&&0<=iy<w->world_height) {
    return ix+iy*w->world_width;
  }
undef:
  return -1;
final:
  ix=ix2,iy=iy2;
  check_dist=smallest;
  if(sin==0) {
    if(cos<0)
      dist2=(ix+1)*GRID_SZ-w->x; //We are checking the right side
    else
      dist2=ix*GRID_SZ-w->x;
  } else {
//We can check if we are next to the top/bottom wall if we are looking up(Sin(a)>0)
    // or down (Sin(a)<0).Same applies to left/right(using consign)

    //We will check if we are closert to the top/bottom wall
    // or the left/right wall.


    //side==0 if left side
    //side==1 if right side
    //side==2 if top side
    //side==3 if bottom side


    //Hits left or right side of wall
    if(cos<0) 
      wall_x=(ix+1)*GRID_SZ;
    else
      wall_x=ix*GRID_SZ;
//Hits top of bottom side of wall
    if(sin<0) 
      wall_y=(iy+1)*GRID_SZ;
    else
      wall_y=iy*GRID_SZ;
    t1=(wall_x-w->x)/(cos+.0001);
    t2=(wall_y-w->y)/(sin+.0001);

    if(t1<t2) {
      x=t2*cos+w->x;
      y=wall_y;
      wall_x=x;
      if(side) *side=2+(sin<0);
      if(segment) *segment=SegmentModulo(x,ix);
    } else{
      x=wall_x;
      y=t1*sin+w->y;
      wall_y=y;
      if(side) *side=cos<0;
      if(segment) *segment=SegmentModulo(y,iy);
    }
    dist2=check_dist;
  }
  goto fin;

}
C2DThing *BumpsIntoThing(C2DThing *self,...) {
  C2DThing *who=argv[0];
  F64 radius=THING_RADIUS*THING_RADIUS;
  F64 x,y;
  x=who->x-self->x;
  y=who->y-self->y;
  if(radius>=x*x+y+y)
    return FrogNumNew(1);
  return FrogNumNew(0);
} 
AddMethod("C2DThing","hitsThing:",&BumpsIntoThing);
//Returns true on wall hit
Bool C3DWorldMoveWithCollision(C3DWorld *w,F64 angle,F64 dist,F64 *x,F64 *y,Bool walk_along_wall=TRUE,I64 height=0) {
  F64 dist2;
  I64 side;
  Bool hit_wall=FALSE;
  F64 old_x=w->x,old_y=w->y,deflect_angle;
  w->x=*x,w->y=*y;
  if(dist<0) angle+=pi,dist=-dist;
  FindRayWall(w,Tan(angle),Cos(angle),Sin(angle),NULL,&dist2,&side,height);
  if(dist2-THING_RADIUS>dist) {
    *x+=Cos(angle)*dist;
    *y+=Sin(angle)*dist;
  } else if(walk_along_wall) {
    hit_wall=TRUE;
    switch(side) {
      start:
      case 2:
	deflect_angle=pi;
	break;
      case 3:
	deflect_angle=0;
	break;
      end:
        C3DWorldMoveWithCollision(w,deflect_angle,Abs(dist*Cos(angle)),x,y,FALSE,height);
	break;
      start:
      case 1:
	deflect_angle=2*pi-pi/2;
	break;
      case 0:
	deflect_angle=pi/2;
        break;
      end:
        C3DWorldMoveWithCollision(w,deflect_angle,Abs(dist*Sin(angle)),x,y,FALSE,height);
    }
  } else
    hit_wall=TRUE;
fin:
//Thing radius is actually a square
//If we are close to any wall,be sure to move back
  I64 wx=*x/GRID_SZ,wy=*y/GRID_SZ;
  if(WallForCord(w,(*x-THING_RADIUS)/GRID_SZ,wy,height)) {
    *x=wx*GRID_SZ+THING_RADIUS;
    hit_wall=TRUE;
  } else if(WallForCord(w,(*x+THING_RADIUS)/GRID_SZ,wy,height)) {
    *x=wx*GRID_SZ+THING_RADIUS;
    hit_wall=TRUE;
  }
  if(WallForCord(w,wx,(*y-THING_RADIUS)/GRID_SZ,height)) {
    *y=wy*GRID_SZ+THING_RADIUS;
    hit_wall=TRUE;
  } else if(WallForCord(w,wx,(*y+THING_RADIUS)/GRID_SZ,height)) {
    *y=wy*GRID_SZ+THING_RADIUS;
    hit_wall=TRUE;
  }
  w->x=old_x,w->y=old_y;
  return hit_wall;
}

F64 Lerp(F64 per,F64 min,F64 max) {
  if(min<max)
    return Clamp(per*(max-min)+min,min,max);
  return Clamp(per*(max-min)+min,max,min);
}

CDC *WallStain(C3DWorld *w,I64 tile_idx,F64 h,I64 side,I64 *offx,I64 *offy) {
  CWallStain **body=w->_wall_stains->body,*stain;
  I64 idx=w->_wall_stains->cnt,dx,dy,tile_idx2,have;
  Bool changed=FALSE;
  while(--idx>=0) {
    stain=body[idx];
    if(!stain->dc) goto skip;
    if(stain->side==side)  {
      have=stain->tile->x+stain->tile->y*w->world_width;
      if(tile_idx==have) {
	*offx=stain->x-stain->center_x;
	*offy=stain->y+h*GRID_SZ-stain->center_y;
	return stain->dc;
      } else {
	switch(side) {
	  case 0 ... 1:
//Hits left/right,so check top/bottom tile
	    for(dx=-1;dx<2;dx++) {
	      tile_idx2=tile_idx+dx;
	      if(tile_idx2==have) {
		*offx=stain->x+dx*GRID_SZ-stain->center_x;
		*offy=stain->y+h*GRID_SZ-stain->center_y;
		return stain->dc;
	      }
	    }
	    break;
	  case 2 ... 3:
//Hits top/bottom,so check left/right tile
	    for(dy=-1;dy<2;dy++) {
	      tile_idx2=tile_idx+dy*w->world_width;
	      if(tile_idx2==have) {
		*offx=stain->x-stain->center_x+dy*GRID_SZ;
		*offy=stain->y+h*GRID_SZ-stain->center_y;
		return stain->dc;
	      }
	    }
	    break;
        }
      }
    }
skip:;
  }
en:;
  return NULL;
}
U0 DrawWallSegment(C3DWorld *w,I64 segment,I64 x,I64 start_y,CDC *texture,I64 height,I64 dist,I64 z,I64 tile_idx,I64 side) {
  I64 offx,offy,stain_color;
  CDC *stain=WallStain(w,tile_idx,z,side,&offx,&offy);
  if(!texture||!height) return;
  U8 *dst=w->to_dc->body;
  I32 *depth_dst,idist;
  I64 tmp,i,segment_y,width=w->to_dc->width_internal,anim_frame=ToI64(tS/ANIM_DELAY)%AnimDCCnt(texture),xp;
  dst+=x+MaxI64(start_y,0)*width;
  if(w->to_dc->depth_buf)
    depth_dst=w->to_dc->depth_buf+x+MaxI64(start_y,0)*width;
  else
    depth_dst=NULL;
  xp=Lerp(segment/ToF64(GRID_SZ),0,texture->width-1);
ent:
  for(i=0;i<=height;i+=w->step_width) {
    tmp=VisSkipTo(w,x,i+start_y,dist)-start_y;
    if(tmp) {
      i=tmp;
      dst=w->to_dc->body+(start_y+i)*width+x;
      if(w->to_dc->depth_buf)
	depth_dst=w->to_dc->depth_buf+(start_y+i)*width+x;
    }
    if(0<=i+start_y<GR_HEIGHT-w->step_width) {
      segment_y=height/(DIST_SCALE/ToF64(dist+1))*(i/ToF64(height))*texture->height;
      tmp=gr.to_8_colors[GrPeek0(
	    texture+anim_frame,
	    xp,
	    segment_y%texture->height)];
      if(stain) {
	if(0<=(stain_color=GrPeek(stain,xp-offx,segment_y-offy))) {
	  if(stain_color!=TRANSPARENT)
	    tmp=gr.to_8_colors[stain_color];
        }
      }
      idist=dist;
      if(w->step_width==2) {
        if(depth_dst[0]>=dist) {
          dst(U16*)[0]=tmp;
          dst+=width;
          dst(U16*)[0]=tmp;
          dst+=width;
          if(depth_dst) {
	    depth_dst[0]=idist;
	    depth_dst[1]=idist;
	    depth_dst+=width;
	    depth_dst[0]=idist;
	    depth_dst[1]=idist;
	    depth_dst+=width;
          }
        } else  {
          depth_dst+=width*2;
	  dst+=width*2;
        }
      } else if(w->step_width==4) {
        if(depth_dst[0]>=dist) {
          dst(U32*)[0]=tmp;
          dst+=width;
          dst(U32*)[0]=tmp;
          dst+=width;
          dst(U32*)[0]=tmp;
          dst+=width;
          dst(U32*)[0]=tmp;
          dst+=width;
          if(depth_dst) {
	    depth_dst[0]=idist;
	    depth_dst[1]=idist;
	    depth_dst[2]=idist;
	    depth_dst[3]=idist;
	    depth_dst+=width;
	    depth_dst[0]=idist;
	    depth_dst[1]=idist;
	    depth_dst[2]=idist;
	    depth_dst[3]=idist;
	    depth_dst+=width;
	    depth_dst[0]=idist;
	    depth_dst[1]=idist;
	    depth_dst[2]=idist;
	    depth_dst[3]=idist;
	    depth_dst+=width;
	    depth_dst[0]=idist;
	    depth_dst[1]=idist;
	    depth_dst[2]=idist;
	    depth_dst[3]=idist;
	    depth_dst+=width;
          }
        } else  {
          depth_dst+=width*4;
	  dst+=width*4;
        }
      }
    } else if(i+start_y>=w->to_dc->height-w->step_width)
      break;
  }
}
CDC *FloorStain(C3DWorld *w,I64 tx,I64 ty,I64 *xoff,I64 *yoff) {
  CFloorStain **body=w->_floor_stains->body,*f;
  I64 idx=w->_floor_stains->cnt;
  I64 adjx,adjy;
  while(--idx>=0) {
    f=body[idx];
//    if(ThingHasClass(f,"CFloorStain"))
    if(f->tile_x==tx&&f->tile_y==ty&&f->dc) {
      if(xoff) *xoff=f->x-f->center_x;
      if(yoff) *yoff=f->y-f->center_y;
      return f->dc;
    }
  }
//Check adjacents
  idx=w->_floor_stains->cnt;
  while(--idx>=0) {
      for(adjx=-1;adjx<=1;adjx+=1)
        for(adjy=-1;adjy<=1;adjy+=1) {
          if(f->tile_x==tx+adjx&&f->tile_y==ty+adjy&&f->dc) {
  	    if(xoff) *xoff=f->x-f->center_x+adjx*GRID_SZ;
 	    if(yoff) *yoff=f->y-f->center_y+adjy*GRID_SZ;
            return f->dc;
          }
        }
  }
  return NULL;
}

I64 ColorFloor(C3DWorld *w,I64 view_x,I64 floor_height,I64 sy,I64 ey,CDC *texture) {
  CDC *dc=w->to_dc,*stain;
  F64 angley=0;
  F64 step;
  F64 dist;
  I64 y,fx,fy,anim_frame=ToI64(tS/ANIM_DELAY)%AnimDCCnt(texture),idx,which,tx,ty;
  I64 old_tx=-1,old_ty=-1;
  U64 colors,width=dc->width_internal,cnt;
  U8 *dst;
  I32 *db_z;
  U64 idist;
  I64 poopx,poopy;
  ey=GR_HEIGHT-ey;
  sy=GR_HEIGHT-sy;
  ey=ClampI64(ey,0,w->to_dc->height-2);
  sy=ClampI64(sy,0,w->to_dc->height-2);
  for(y=sy;y<ey;y+=w->step_width) {
    if(y-GR_HEIGHT/2==0)
      dist=I16_MAX;
    else {
      dist=DIST_SCALE/((GR_HEIGHT/2-y)/(w->cam_height-floor_height+.001));
    }
    dist/=cos2_lookup_table[view_x];

    fx=w->x+cos_lookup_table[view_x]*dist;
    fy=w->y+sin_lookup_table[view_x]*dist;
    tx=fx/GRID_SZ;
    ty=fy/GRID_SZ;
//TODOcache
    if(old_tx!=tx||old_ty!=ty) {
      stain=FloorStain(w,tx,ty,&poopx,&poopy);
      old_tx=tx;
      old_ty=ty;
    }
    if(texture) {
        colors=gr.to_8_colors[GrPeek0(
	      texture+anim_frame,
	      (fx&(GRID_SZ-1))/ToF64(GRID_SZ)*texture->width,
	      (fy&(GRID_SZ-1))/ToF64(GRID_SZ)*texture->height)];
	if(stain) {
	  which=GrPeek(stain,fx&(GRID_SZ-1)-poopx,fy&(GRID_SZ-1)-poopy);
	  if(TRANSPARENT!=which&&which>=0)
	    colors=gr.to_8_colors[which];
        }
        if(0<=y<dc->height) {
	  dst=dc->body+(dc->height-y-w->step_width)*width+view_x;
	  db_z=dc->depth_buf+(dc->height-y-w->step_width)*width+view_x;
	  if(dist<*db_z) {
	    idist=dist;
	    //Make 64bit pair
	    idist=(idist&0xffFFffFF)|idist<<32;
	    if(w->step_width==2){ 
	      dst(U16*)[0]=colors;
	      db_z[0](U64)=idist;
	      dst+=width;
	      db_z+=width;
	      dst(U16*)[0]=colors;
	      db_z[0](U64)=idist;
	      dst+=width;
	      db_z+=width;
	    } else if(w->step_width==4) {
	      dst(U32*)[0]=colors;
	      db_z[0](U64)=idist;
	      db_z[2](U64)=idist;
	      dst+=width;
	      db_z+=width;
	      dst(U32*)[0]=colors;
	      db_z[0](U64)=idist;
	      db_z[2](U64)=idist;
	      dst+=width;
	      db_z+=width;
	      dst(U32*)[0]=colors;
	      db_z[0](U64)=idist;
	      db_z[2](U64)=idist;
	      dst+=width;
	      db_z+=width;
	      dst(U32*)[0]=colors;
	      db_z[0](U64)=idist;
	      db_z[2](U64)=idist;
	      dst+=width;
	      db_z+=width;
	    }
	  }
        }
      }
    }
  return GR_HEIGHT-sy;
}
//-1 terminated
//https://en.wikipedia.org/wiki/Digital_differential_analyzer_(graphics_algorithm)
F64 FUMod(F64 v,F64 to) {
  if(v>0.) return v%to;
  if(v<0.) return -(v%to);
  return 0;
}
I64 *GetTilesInPath(C3DWorld *w,F64 angle,F64 dist) {
  I64 *tiles=MAlloc((dist/GRID_SZ+8)*4*8);
  I64 ptr=0;
  F64 x=w->x,y=w->y,ex,ey,dx,dy,step,i,by,slope,cos,sin,xdist,ydist;
  F64 res_dist;
  I64 tx=x/GRID_SZ,ty=y/GRID_SZ,idx,old_tx,old_ty,dirx,diry,ix,iy;
  Bool use_x;
  cos=Cos(angle);
  sin=Sin(angle);
  ex=x+cos*dist;
  ey=y+sin*dist;
  slope=Tan(angle);
  dx=ex-x;
  dy=ey-y;
  if(Abs(dx)>Abs(dy)) {
    use_x=TRUE;
    step=Abs(dx);
  } else {
    use_x=FALSE;
    step=Abs(dy);
  }
  dx/=step;
  dy/=step;
  idx=ty*w->world_width+tx;
  tiles[ptr++]=idx;
  i=0;
//
  // Ask Nroot how this works,it's his algoirthm
  //
  while(i<=step) {
    old_tx=tx;
    old_ty=ty;
//
    //
    //
    //
    //$SP,"<1>",BI=1$
    //Advance by the closest distance
    if(cos>0.) {
      xdist=GRID_SZ-FUMod(x,GRID_SZ)+x;
      if(xdist==x) xdist+=GRID_SZ;
    } else if(cos<0.) {
      xdist=x-(GRID_SZ-FUMod(x,GRID_SZ));
      if(xdist==x) xdist-=GRID_SZ;
    } else 
      xdist=x;
    if(sin>0.) {
      ydist=GRID_SZ-FUMod(y,GRID_SZ)+y;
      if(ydist==y) ydist+=GRID_SZ;
    } else if(sin<0.) {
      ydist=y-(GRID_SZ-FUMod(y,GRID_SZ));
      if(ydist==y) ydist-=GRID_SZ;
    } else 
      ydist=y;
    if(!dx) goto dy_type;
    if(!dy) goto dx_type;
    if(xdist-x<ydist-y) {
dx_type:
      by=(xdist-x)/dx;
    } else {
dy_type:
      by=(ydist-y)/dy;
    }
    x+=dx*by;
    y+=dy*by;
    tx=x/GRID_SZ,ty=y/GRID_SZ;
    tx=ClampI64(tx,0,w->world_width);
    ty=ClampI64(ty,0,w->world_height);
    dirx=SignI64(tx-old_tx);
    diry=SignI64(ty-old_ty);

    for(iy=old_ty;TRUE;iy+=diry) {
      for(ix=old_tx;TRUE;ix+=dirx) {
        idx=ix+iy*w->world_width;
        if(tiles[ptr-1]!=idx) {
	  if(PassesThoughBlock(w,slope,ix,iy,&res_dist,cos,sin)) {
	    if(res_dist<dist) {
	      tiles[ptr++]=idx;
	    }
	  }
        }
        if(ix==tx)
	  break;
      }
      if(iy==ty)
        break;
    }

    if(!tx||tx>=w->world_width)
      goto fin;
    if(!ty||ty>=w->world_height)
      goto fin;
    i+=by;
  }
fin:
  tiles[ptr++]=-1;
  return tiles;
}
I64 mp_done=0;
F64 ScreenCordsToDist(C3DWorld *w,I64 x,I64 y,F64 max=GRID_SZ*128,F64 *height=NULL,Bool *hit_floor=FALSE) {
  F64 angle=w->angle+w->fov*((x-GR_WIDTH/2)/ToF64(GR_WIDTH));
  CDC *to_dc=w->to_dc;
  I32 have=I32_MAX;
  F64 wx,wy;
  F64 d=-1,dist,h,y0,dist2,h2,y1;
  I64 tile2,tile;
//Check for floor from ZBuf
  if(0<=x<GR_WIDTH)
    if(0<=y<GR_HEIGHT) {
      have=to_dc->depth_buf[y*to_dc->width_internal+x];
    }
  I64 *tiles=GetTilesInPath(w,angle,max),idx;
  I64 total,xoff,yoff,adj_height;
  if(height) *height=w->cam_height;
  if(hit_floor) *hit_floor=FALSE;
  for(idx=0;tiles[idx]!=-1;idx++) {
    tile=tiles[idx];
    wx=(w->x+have*cos_lookup_table[x])/GRID_SZ;
    wy=(w->y+have*sin_lookup_table[x])/GRID_SZ;
	FindRayWall(w,
	      tan_lookup_table[x],
	      cos_lookup_table[x],
	      sin_lookup_table[x],
	      NULL,
	      &dist2,
	      NULL,
	      I8_MIN,
	      tile,
	      TRUE //Far side of tile
	      );
	FindRayWall(w,
	      tan_lookup_table[x],
	      cos_lookup_table[x],
	      sin_lookup_table[x],
	      NULL,
	      &dist,
	      NULL,
	      I8_MIN,
	      tile,
	      FALSE //Near side of tile
	      );
    adj_height=w->heightmap[tile];
    for(xoff=-1;xoff<=1;xoff++)
      for(yoff=-1;yoff<=1;yoff++) {
	tile2=xoff+yoff*w->world_width+tile;
	if(0<=tile2<w->world_width*w->world_height&&(xoff^^yoff)) {
	  adj_height=MinI64(adj_height,w->heightmap[tile2]);
	}
      }
    h=DIST_SCALE/(dist*cos2_lookup_table[x]);
    y0=GR_HEIGHT/2-h*(w->heightmap[tile]-w->cam_height);
    h2=DIST_SCALE/(dist2*cos2_lookup_table[x]);
    y1=GR_HEIGHT/2-h2*(w->heightmap[tile]-w->cam_height);    
    if(have<dist2) {
      if(y1-2<=y<=y0+2) {
	if(height) *height=w->heightmap[tile];
	if(hit_floor) *hit_floor=TRUE;
	d=have;
	break;
      }
    }
    if(y0<=y<y0+h*(w->heightmap[tile]-adj_height)) {
//TODOtest floor intersection
      if(height) *height=Lerp((y-y0)/(h*(w->heightmap[tile]-adj_height)),w->heightmap[tile],adj_height);
      d=dist;
      break;
    }
  }
  if(d<0) {
    FindRayWall(w,
	  tan_lookup_table[x],
	  cos_lookup_table[x],
	  sin_lookup_table[x],
	  NULL,
	  &d,
	  NULL,
	  w->cam_height
	  );
  }
  Free(tiles);
  return d;
}

U0 MPCastCol(C3DWorld *w) {
  F64 angle=w->angle-w->fov/2;
  I64 wall_segment_start,wall_segment_end;
  F64 dist,h,y,y2,dist2,h2;
  F64 s_angle1,s_angle2;
  I64 segment=0,idx,idx2,ptr,x=0,cap,side,side2,segment2,x0,y0,old_d,idx3,xoff,yoff;
  CBlockedView *block_view;
  I64 height_cap,adj_height,last_height,floor_y,ceily,ceil,last_ceil;
  CDC *use_dc;
  I64 *tiles;
  I64 standing_at;
  idx=GR_WIDTH/mp_cnt*Gs->num;
  cap=GR_WIDTH/mp_cnt*(Gs->num+1);
  angle+=(w->fov/GR_WIDTH)*w->step_width*idx/w->step_width;
  for(x=idx;x<cap;angle+=(w->fov/GR_WIDTH)*w->step_width,x+=w->step_width) {
    idx2=0;
    dist=0;
    floor_y=GR_HEIGHT;
    ceily=GR_HEIGHT;
    last_height=I64_MIN;
    last_ceil=I64_MAX;
    tiles=GetTilesInPath(w,angle,128*GRID_SZ);
    if(tiles[0]==-1)
      goto fin;
ent:
    idx=tiles[idx2];
    if(idx!=-1) {
      height_cap=w->heightmap[idx];
      FindRayWall(w,
	    tan_lookup_table[x],
	    cos_lookup_table[x],
	    sin_lookup_table[x],
	    &segment,
	    &dist,
	    &side,
	    I8_MIN,
	    idx
	    );
        FindRayWall(w,
	      tan_lookup_table[x],
	      cos_lookup_table[x],
	      sin_lookup_table[x],
	      NULL,
	      &dist2,
	      NULL,
	      I8_MIN,
	      idx,
	      TRUE //Far side of tile
	      );
      idx2++;
//https://permadi.com/1996/05/ray-casting-tutorial-8/
      dist*=cos2_lookup_table[x];
      h=DIST_SCALE/dist;
      dist2*=cos2_lookup_table[x];
      h2=DIST_SCALE/(dist2+1);
//Dont straight lines on blocks with same height(hidden)
      if(last_height>w->cam_height)
        if(last_height>height_cap)
          goto ceil2;
//Color the floor tile
      if(height_cap<w->cam_height) {
        y0=GR_HEIGHT/2-h*(height_cap-w->cam_height);
        if(dist>.2&&dist2>.2) {
	  standing_at=ToI64(w->x)/GRID_SZ+ToI64(w->y)/GRID_SZ*w->world_width;
	  if(w->floor_textures[w->world_mat[idx]])
	    use_dc=w->floor_textures[w->world_mat[idx]];
	  else
	    use_dc=w->wall_textures[w->world_mat[idx]];
	  if(standing_at==idx) {
	     floor_y=ColorFloor(w,x,height_cap,
	        GR_HEIGHT,
	        GR_HEIGHT/2-h2*(height_cap-w->cam_height),
	        use_dc,
	        );
	  } else {
	     floor_y=ColorFloor(w,x,height_cap,
	        MinI64(y0,floor_y),
	        GR_HEIGHT/2-h2*(height_cap-w->cam_height),
		use_dc
	        );
          }
	}
      }
      adj_height=I64_MAX;
      for(xoff=-1;xoff<=1;xoff++)
        for(yoff=-1;yoff<=1;yoff++) {
	  idx3=xoff+yoff*w->world_width+idx;
	  if(0<=idx3<w->world_width*w->world_height&&(xoff^^yoff)) {
	    adj_height=MinI64(adj_height,w->heightmap[idx3]);
	  }
        }
//Dont straight lines on blocks with same height(hidden)
      if(last_height==height_cap)
        goto ceil2;
      last_height=height_cap;
      if(dist<=2.)
        goto ceil2;
      if(adj_height>=height_cap)
        goto ceil2;
      y=GR_HEIGHT/2;
      y0=GR_HEIGHT/2-h*(height_cap-w->cam_height);

      for(idx3=2;--idx3>=0;) {
        if(0<=x+idx3<w->to_dc->width) {
	  ptr=w->blocked_cnts[x+idx3];
	  if(ptr<0x80) {
	    w->blocked_cnts[x+idx3]=ptr+1;
	    block_view=&w->blocked_views[x+idx3][ptr];
	    block_view->start=y0;
	    block_view->end=y0+h*AbsI64(height_cap-adj_height);
	    block_view->dist=dist;
	  }
        }
      }
      for(idx3=0;idx3<AbsI64(height_cap-adj_height);idx3++) {
        DrawWallSegment(w,segment,x,y0+h*idx3,w->wall_textures[w->world_mat[idx]],h,dist,height_cap-1-idx3,idx,side);
      }
ceil2:      
      ceil=w->ceilmap[idx];
      adj_height=w->ceilmap2[idx];
      //Draw Ceil
      if(ceil!=I8_MAX&&ceil>w->cam_height) {
        if(use_dc=w->ceil_textures[w->world_mat[idx]]) {
	  standing_at=ToI64(w->x)/GRID_SZ+ToI64(w->y)/GRID_SZ*w->world_width;
	  if(standing_at==idx) {
            ColorFloor(w,x,ceil,
              GR_HEIGHT/2-h2*(ceil-w->cam_height),
              0,
              use_dc
            );
	  } else
            ColorFloor(w,x,ceil,
              GR_HEIGHT/2-h2*(ceil-w->cam_height),
              GR_HEIGHT/2-h*(ceil-w->cam_height),
              use_dc
            );
	}
      } else if(ceil!=I8_MAX&&ceil+adj_height<w->cam_height) {
         use_dc=w->wall_textures[w->world_mat[idx]];
	 if(use_dc)
          ColorFloor(w,x,ceil+adj_height,
            GR_HEIGHT/2-h*(ceil+adj_height-w->cam_height),
            GR_HEIGHT/2-h2*(ceil+adj_height-w->cam_height),
            use_dc
          );
      }

//      if(ceil!=I8_MAX&&last_ceil!=ceil) {
        y0=GR_HEIGHT/2-h*(ceil+adj_height-w->cam_height);
        for(idx3=0;idx3<adj_height;idx3++) {
          DrawWallSegment(w,segment,x,y0+h*idx3,w->wall_textures[w->world_mat[idx]],h,dist,height_cap-1-idx3,idx,side);
        }
        last_ceil=ceil;
//      }
      goto ent;
    }
fin:
    Free(tiles);
  }
  LBts(&mp_done,Gs->num);
}
U0 C3DWorldCastRays(C3DWorld *w) {
  I64 idx;
  mp_done=0;
  for(idx=GR_WIDTH;--idx>=0;) {
    w->blocked_cnts[idx]=0;
  }
  for(idx=mp_cnt-1;idx>=1;idx--) {
    JobQue(&MPCastCol,w,idx);
  }
  MPCastCol(w);
  for(idx=mp_cnt-1;idx>=1;idx--) {
    while(!Bt(&mp_done,idx))
      Sleep(1);
  }
}
F64 AngleBetween(F64 a,F64 b) {
//https://stackoverflow.com/questions/1878907/how-can-i-find-the-smallest-difference-between-two-angles-around-a-point
  a%=2.*pi;
  b%=2.*pi;
  if(a<0) a+=2.*pi;
  if(b<0) b+=2.*pi;
  return Min(2*pi-Abs(b-a),Abs(a-b));
}
F64 NormalizeAngle(F64 a) {
  a%=2*pi;
  if(a<0) a+=2*pi;
  return a;
}
Bool CanSee2DThing(C3DWorld *w,C2DThing *t) {
  Bool ret=TRUE;
  F64 dist=Sqrt(Sqr(t->x-w->x)+Sqr(t->y-w->y)),rd;
  F64 angle=Arg(t->x-w->x,t->y-w->y);
  I64 *ti=GetTilesInPath(w,angle,dist),idx;
  for(idx=0;ti[idx]!=-1;idx++) {
/*TODO*/
    if(w->heightmap[ti[idx]]>w->cam_height) {
      ret=FALSE;
      break;
    }
  }
  Free(ti);
  return ret;
}
U0 DrawParticle(C3DWorld *w,C3DParticle *p) {
  I32 dist=Sqrt(Sqr(w->x-p->x)+Sqr(w->y-p->y));
  I64 x0,y0;
  F64 h=DIST_SCALE/(1+dist),angle=Arg(p->x-w->x,p->y-w->y);
  y0=GR_HEIGHT/2-h*((p->z)-w->cam_height);
  if(Sin(angle-w->angle)>0.) {
    angle=AngleBetween(angle,w->angle);
    x0=GR_WIDTH/2+angle/((w->fov/GR_WIDTH));
  } else {
    angle=AngleBetween(angle,w->angle);
    x0=GR_WIDTH/2-angle/((w->fov/GR_WIDTH));
  }
  h=h/GRID_SZ*p->size;
  w->to_dc->thick=h;
  w->to_dc->color=p->color;
  if(h>=1.)
    GrPlot3(w->to_dc,x0,y0,dist);
}
#define THING_DRAW_CUTOFF GRID_SZ/2
U0 PointToScrn(C3DWorld *w,F64 x,F64 y,F64 z,CD3 *res) {
  F64 angle;
  F64 dist=Sqrt(Sqr(x-w->x)+Sqr(y-w->y));
  angle=Arg(x-w->x,y-w->y);
//https://permadi.com/1996/05/ray-casting-tutorial-8/
//Check direction
  angle=NormalizeAngle(angle);
  if(Sin(angle-w->angle)>0.) {
    angle=AngleBetween(angle,w->angle);
    res->x=GR_WIDTH/2+angle/((w->fov/GR_WIDTH));
  } else {
    angle=AngleBetween(angle,w->angle);
    res->x=GR_WIDTH/2-angle/((w->fov/GR_WIDTH));
  }
  dist*=cos2_lookup_table[ClampI64(res->x,0,GR_WIDTH-1)];
  F64 h=DIST_SCALE/(dist+1);
  res->y=GR_HEIGHT/2-h*(z-w->cam_height+.01);
  res->z=dist;
}
Bool IsLeftSide(CD2 *a,CD2 *b,CD2 *c) {
  return (b->x-a->x)*(c->y-a->y)-(b->y-a->y)*(c->x-a->x)>=0.;
}
Bool ClipLineToCamera(C3DWorld *w,CD3 *a,CD3 *b) {
  CD2 cam,left,right;
  CD2 dst;
  CD3 oa,ob;
  F64 a_angle=Arg(a->x-cam.x,a->y-cam.y);
  F64 b_angle=Arg(b->x-cam.x,b->y-cam.y);
  F64 aa=Sin(AngleBetween(a_angle,w->angle));
  F64 ba=Sin(AngleBetween(b_angle,w->angle));
  F64 dist=Sqrt(Sqr(b->x-a->x)+Sqr(b->y-a->y));
  Bool in_view=FALSE;
  oa.x=a->x;
  oa.y=a->y;
  oa.z=a->z;
  ob.x=b->x;
  ob.y=b->y;
  ob.z=b->z;
  cam.x=w->x;
  cam.y=w->y;
  left.x=cam.x+I16_MAX*Cos(w->fov+w->angle);
  left.y=cam.y+I16_MAX*Sin(w->fov+w->angle);
  right.x=cam.x+I16_MAX*Cos(-w->fov+w->angle);
  right.y=cam.y+I16_MAX*Sin(-w->fov+w->angle);
  if(PlaneIntersect(&dst,a,b,&cam,&left)) {
     if(aa>0.) {
       a->z=Lerp(Sqrt(Sqr(dst.x-oa.x)+Sqr(dst.y-oa.y))/dist,oa.z,ob.z);
       a->x=dst.x;
       a->y=dst.y;
     } else if(ba>0.){
       b->x=dst.x;
       b->y=dst.y;
       b->z=Lerp(Sqrt(Sqr(dst.x-oa.x)+Sqr(dst.y-oa.y))/dist,oa.z,ob.z);
     }
    in_view=TRUE;
  }
  if(PlaneIntersect(&dst,a,b,&cam,&right)) {
     if(aa<0.) {
       a->x=dst.x;
       a->y=dst.y;
       a->z=Lerp(Sqrt(Sqr(dst.x-oa.x)+Sqr(dst.y-oa.y))/dist,oa.z,ob.z);
     } else if(ba<0.){
       b->x=dst.x;
       b->y=dst.y;
       b->z=Lerp(Sqrt(Sqr(dst.x-oa.x)+Sqr(dst.y-oa.y))/dist,oa.z,ob.z);
     }
    in_view=TRUE;
  }
  if(Cos(a_angle)<0&&Cos(b_angle)<0)
    return FALSE;
  return in_view||!IsLeftSide(&cam,&left,a)||!IsLeftSide(&cam,&left,b)
	||IsLeftSide(&cam,&right,a)||IsLeftSide(&cam,&right,b);
}
U0 Line3D(C3DWorld *w,CDC *dc,CD3 *st,CD3 *en) {
  CD3 res,res2;
  PointToScrn(w,st->x,st->y,st->z,&res);
  PointToScrn(w,en->x,en->y,en->z,&res2);
  GrLine3(dc,res.x,res.y,res.z,res2.x,res2.y,res2.z);
}

U0 DrawFrogTongue(C3DWorld *w,CFrogTongue *t) {
  if(!ThingHasClass(t,"CFrogTongue"))
    return;
  if(!ThingHasClass(t->from,"C2DThing"))
    return;
  CD3 stp,enp;
  CDC *dc=w->to_dc;
  F64 stz,enz;
  stp.x=t->x;
  stp.y=t->y;
  stp.z=t->z;
  enp.x=t->from->x;
  enp.y=t->from->y;
  enp.z=t->from->z+.8;
  if(ClipLineToCamera(w,&stp,&enp)){
    dc->color=LTRED;
    dc->thick=4;   
    Line3D(w,dc,&stp,&enp);
  }
}
U0 DrawPissStream(C3DWorld *w,CPissStream *ps) {
  CDC *dc=w->to_dc;
  CD3 stp,enp,last;
  CPissLink **links=ps->links(CFrogArray*)->items->body;
  I64 idx,cnt=ps->links(CFrogArray*)->items->cnt;
  if(cnt<1) return;
  last.x=links[0]->x;
  last.y=links[0]->y;
  last.z=links[0]->z;
//Massive piss
  dc->color=YELLOW;
  dc->thick=4;
  for(idx=1;idx!=cnt;idx++) {
    stp.x=last.x;
    stp.y=last.y;
    stp.z=last.z;
    enp.x=links[idx]->x;
    enp.y=links[idx]->y;
    enp.z=links[idx]->z;
    ClipLineToCamera(w,&stp,&enp);
    Line3D(w,dc,&stp,&enp);
    last.x=links[idx]->x;
    last.y=links[idx]->y;
    last.z=links[idx]->z;
  }
}
U0 Draw2DThing(C3DWorld *w,C2DThing *thing) {
  if(thing->no_draw) goto fin;
  C2DThingTemplate *template=thing->template;
  if(!ThingHasClass(template,"C2DThingTemplate"))
    return;
  CDC *dc=w->to_dc;
  F64 x=thing->x-w->x,y=thing->y-w->y;
  F64 off=thing->angle-w->angle+pi,angle,diff,gap;
  F64 y0,h,width,x0,cx,cy,vis_h;
  I32 dist=Sqrt(Sqr(x)+Sqr(y));
  CDC *use_dc;
  I64 dc_w=dc->width,frame=ToI64((tS-thing->animation_start_tS)/ANIM_DELAY);
  I64 to_x,to_y;
  I64 line,col,face,cnt;
  I64 ix,iy;
  F64 wall_height_ratio;
  U8 *src_ptr,*y_line;
  U16 *dst;

  Bool flip=FALSE;
  off=off%(2*pi);
  if(template->flags&THINGF_FACE_FORWARD) {
    use_dc=template->front;
    goto draw;
  }
  face=1;
  for(gap=0.;gap<2*pi;gap+=2.*pi/4.) {
    diff=(off-gap+3*pi)%(2*pi)-pi;
//https://stackoverflow.com/questions/12234574/calculating-if-an-angle-is-between-two-angles
    if(-2*pi/4./2<=diff<=2*pi/4./2)
      break;
    face++;
  }
  switch(face) {
    default:
    case 1:
      use_dc=template->front;     
      break;
    case 2:
      use_dc=template->side;
      flip=TRUE;
      break;
    case 3:
      use_dc=template->back;
      break;
    case 4:
      use_dc=template->side;
      break;
  }
  if(!use_dc) return;
draw:
  if(thing->animation_no_repeat) 
     use_dc+=MinI64(frame,AnimDCCnt(use_dc)-1);
  else
    use_dc+=frame%AnimDCCnt(use_dc);
  angle=Arg(x,y);
//https://permadi.com/1996/05/ray-casting-tutorial-8/
  if(angle<w->angle)
    dist*=Cos(w->angle-angle);
  else
    dist*=Cos(angle-w->angle);
//Draw Starting from bottom of wall
//
// The differnece between h an vis_h s vis_h is clamped to avoid massive sprites when up close
//
// I will use h for computing position,then vis_h for dimenisons of the drawn_sprite
//
  wall_height_ratio=(use_dc->height/ToF64(GR_HEIGHT));
  vis_h=Clamp(h=DIST_SCALE/(5.+ToF64(dist)),1,GR_HEIGHT*.75)*wall_height_ratio;
  y0=GR_HEIGHT/2-h*((wall_height_ratio+thing->z)-w->cam_height);
//I will now scale vis_h by 1.5 to look pretty,we will need to adjust y0 accordingly
  y0-=vis_h*1.5-vis_h;
  vis_h*=1.5;
  width=ToF64(vis_h)/use_dc->height*use_dc->width;
  angle=NormalizeAngle(angle);
  w->angle=NormalizeAngle(w->angle);
//Check direction
  if(Sin(angle-w->angle)>0.) {
    angle=AngleBetween(angle,w->angle);
    x0=GR_WIDTH/2+angle/((w->fov/GR_WIDTH))-width/2;
  } else {
    angle=AngleBetween(angle,w->angle);
    x0=GR_WIDTH/2-angle/((w->fov/GR_WIDTH))-width/2;
  }

//clamp'ed x
  cx=ClampI64(x0,0,GR_WIDTH);
//ditto
  cy=ClampI64(y0,0,GR_HEIGHT);
  to_x=ClampI64(width+x0,0,GR_WIDTH-2);
  to_y=ClampI64(vis_h+y0,0,GR_HEIGHT-3);
  for(ix=ToI64(cx)&~1;cx-4<=ix<to_x;ix+=2) {
    if(!flip) {
      col=(ix-x0)/width*use_dc->width;
      src_ptr=y_line;
    } else {
      col=(width-(ix-x0)-1)/width*use_dc->width;
    }
    if(0>col||col>=use_dc->width)
     goto skip2;
    iy=ToI64(cy)&~1;
    dst=dc->body+ToI64(iy)*dc->width_internal+ToI64(ix);
    I32 *depth_dst=dc->depth_buf+ToI64(iy)*dc->width_internal+ToI64(ix);
    for(;cy-4<=iy<to_y;iy+=3) {
      line=ToI64((iy-y0)/vis_h*use_dc->height);
      if(0<=line<use_dc->height-3) {
        y_line=use_dc->body+line*use_dc->width_internal;
        src_ptr=y_line+col;
        if(*src_ptr==TRANSPARENT) {
	  while(line<use_dc->height) {
	    if(*src_ptr!=TRANSPARENT)
	     break;
	    src_ptr+=use_dc->width_internal;
	    line++;
	  }
	  iy=MaxI64(Lerp(ToF64(line)/use_dc->height,cy,to_y)-3,iy);
          dst=dc->body+ToI64(iy)*dc->width_internal+ToI64(ix);
	  depth_dst=dc->depth_buf+ToI64(iy)*dc->width_internal+ToI64(ix);
	  goto skip;
	}
	if(dist>*depth_dst) {
	  cnt=VisSkipTo(w,ix,iy,dist)-iy;
	  iy+=cnt;
	  dst=dst(U8*)+dc->width_internal*cnt;
	  depth_dst+=dc->width_internal*cnt;  
	  goto skip;
	}
	for(cnt=3;--cnt>=0;) {
          *dst=gr.to_8_colors[*src_ptr];
	  depth_dst[0]=dist;
	  depth_dst[1]=dist;
	  dst=dst(U8*)+dc->width_internal;
	  depth_dst+=dc->width_internal;
	}
skip:;
      }
skip2:;
    }
  }
fin:
  if(ThingHasClass(thing,"CFrogNPC")) {
    DrawFrogTongue(w,thing(CFrogNPC*)->tongue);
  }
  if(ThingHasClass(thing,"CPlayer")) {
    DrawPissStream(w,thing(CPlayer*)->piss_stream);
  }
}
C3DWorld *w;
U0 WallStainDel(CWallStain *s) {
  AnimDCDel(s->dc);
  Free(s);
}
//
// SmallTalk Section
//
CFrogThing *FloorStainSetGr(CFloorStain *self,...) {
  CFrogStr *str=argv[0];
  F64 angle=AsF64(argv[1]);
  U8 *name=AsString(str),*raw=BlobFileGetLump("ASS",name);
  CDC *orig,*rotated;
  if(raw) {
    if(self->dc) AnimDCDel(self->dc);
    orig=AnimDCLoad(raw);
    rotated=AnimDCNew(orig->width*1.4,orig->height*1.4);
    self->dc=rotated;
    rotated->flags|=DCF_TRANSFORMATION;
    DCFill(rotated,TRANSPARENT);
    Mat4x4IdentEqu(rotated->r);
    Mat4x4TranslationAdd(rotated->r,-orig->width/2,-orig->height/2,0);
    Mat4x4RotZ(rotated->r,angle);
    Mat4x4TranslationAdd(rotated->r,orig->width/2,orig->height/2,0);
    GrBlot3(rotated,0,0,0,orig);
    self->center_x=self->dc->width/2;
    self->center_y=self->dc->height/2;
    AnimDCDel(orig);
    Free(raw);
  }
  Free(name);
  ThingDel(str);
  return FROG_SMALL_NIL;
}
AddMethod("CFloorStain","setGraphics:atAngle:",&FloorStainSetGr);
CFrogThing *FloorStainMerge(CFloorStain *self,...) {
  CFloorStain *other=argv[0];
  CFloorStain *ret=FROG_SMALL_NIL;
  if(!ThingHasClass(other,"CFloorStain"))
    goto fin;
  if(!self->dc||!other->dc)
   goto fin;
  I64 x1=0,y1=0,x2=0,y2=0,
	xoff=GRID_SZ*(other->tile_x-self->tile_x),
	yoff=GRID_SZ*(other->tile_y-self->tile_y);
  x1=MinI64(self->x-self->center_x,xoff+other->x-other->center_x);
  x2=MaxI64(self->x-self->center_x+self->dc->width,xoff+other->x-other->center_x+other->dc->width);
  y1=MinI64(self->y-self->center_y,yoff+other->y-other->center_y);
  y2=MaxI64(self->y-self->center_y+self->dc->height,yoff+other->y-other->center_y+other->dc->height);
  CDC *new=AnimDCNew(x2-x1+1,y2-y1+1);
  ret=ConstructThing("CFloorStain");
  ret->dc=new;
  ret->x=x1;
  ret->y=y1;
  ret->center_x=0;
  ret->center_y=0;
  ret->tile_x=self->tile_x;
  ret->tile_y=self->tile_y;
  DCFill(new,TRANSPARENT);
  if(self->dc)
    GrBlot(new,self->x-self->center_x-x1,self->y-self->center_y-y1,self->dc);
  if(other->dc)
    GrBlot(new,xoff+other->x-other->center_x-x1,yoff+other->y-other->center_y-y1,other->dc);
fin:;
  ThingDel(other);
  return ret;
}
AddMethod("CFloorStain","mergeWith:",&FloorStainMerge);
U0 FloorStainDel(CFloorStain *s) {
  if(s->dc) AnimDCDel(s->dc);
  Free(s);
}




CFrogThing *WallStainSetGr(CWallStain *self,...) {
  CFrogStr *str=argv[0];
  U8 *name=AsString(str),*raw=BlobFileGetLump("ASS",name);
  if(raw) {
    if(self->dc) AnimDCDel(self->dc);
    self->dc=AnimDCLoad(raw);
    self->center_x=self->dc->width/2;
    self->center_y=self->dc->height/2;
    Free(raw);
  }
  Free(name);
  ThingDel(str);
  return FROG_SMALL_NIL;
}
AddMethod("CWallStain","setGraphics:",&WallStainSetGr);
CFrogThing *WallStainMerge(CWallStain *self,...) {
  CWallStain *other=argv[0];
  CWallStain *ret=FROG_SMALL_NIL;
  if(!ThingHasClass(other,"CWallStain"))
    goto fin;
  if(!other->dc||!self->dc)
    goto fin;
  I64 x1=0,y1=0,x2=0,y2=0;
  x1=MinI64(self->x-self->center_x,other->x-other->center_x);
  x2=MaxI64(self->x-self->center_x+self->dc->width,other->x-other->center_x+other->dc->width);
  y1=MinI64(self->y-self->center_y,other->y-other->center_y);
  y2=MaxI64(self->y-self->center_y+self->dc->height,other->y-other->center_y+other->dc->height);
  CDC *new=DCNew(x2-x1+1,y2-y1+1);
  ret=ConstructThing("CWallStain");
  ret->dc=new;
  ret->x=x1;
  ret->y=y1;
  ret->side=self->side;
  ret->tile=ConstructThing("C2DPoint");
  ret->tile->x=self->tile->x;
  ret->tile->y=self->tile->y;
  DCFill(new,TRANSPARENT);
  GrBlot(new,self->x-self->center_x-x1,self->y-self->center_y-y1,self->dc);
  GrBlot(new,other->x-other->center_x-x1,other->y-other->center_y-y1,other->dc);
fin:;
  ThingDel(other);
  return ret;
}
AddMethod("CWallStain","mergeWith:",&WallStainMerge);


CFrogThing *WorldManagerNewParticle(C3DWorldManager *man,...) {
  F64 x=AsF64(argv[0]);
  F64 y=AsF64(argv[1]);
  F64 z=AsF64(argv[2]);
  F64 spread=AsF64(argv[3]);
  F64 color=AsF64(argv[4]);
  NewParticle(w,color,16,x,y,z,spread*(Rand-.5),spread*(Rand-.5),man->gravity*3);
  return FROG_SMALL_NIL;
}
AddMethod("C3DWorldManager","newParticleAtX:atY:atZ:withSpread:withColor:",&WorldManagerNewParticle);

//Returns 1. if COLLISION,else 0
CFrogThing *C2DThingMoveAtAngle(C2DThing *self,...) {
  CFrogThing *dist=argv[0];
  CFrogThing *angle=argv[1];
  Bool hit_wall=FALSE;
  hit_wall=C3DWorldMoveWithCollision(w,AsF64(angle),AsF64(dist),&self->x,&self->y,TRUE,self->z);
fin:
  ThingDel(dist);
  ThingDel(angle);
  return FrogNumNew(hit_wall);
}
AddMethod("C2DThing","move:atAngle:",&C2DThingMoveAtAngle);

CFrogThing *WorldManagerWidth(C3DWorldManager *self,...) {
  return FrogNumNew(self->world_handle(C3DWorld*)->world_width);
}
CFrogThing *WorldManagerHeight(C3DWorldManager *self,...) {
  return FrogNumNew(self->world_handle(C3DWorld*)->world_height);
}
AddMethod("C3DWorldManager","width",&WorldManagerWidth);
AddMethod("C3DWorldManager","height",&WorldManagerHeight);
CFrogThing *WorldManagerTileHeightAtXAtY(C3DWorldManager *self,...) {
  I64 x=AsF64(argv[0]);
  I64 y=AsF64(argv[1]);
  C3DWorld *w=self->world_handle;
  if(0<=x<w->world_width)
    if(0<=y<w->world_height) {
      return FrogNumNew(w->heightmap[x+y*w->world_width]);
    }
  return FrogNumNew(I16_MAX);
}
AddMethod("C3DWorldManager","tileHeightAtX:atY:",&WorldManagerTileHeightAtXAtY);
CFrogThing *WorldManagerCeilHeightAtXAtY(C3DWorldManager *self,...) {
  I64 x=AsF64(argv[0]);
  I64 y=AsF64(argv[1]);
  C3DWorld *w=self->world_handle;
  if(0<=x<w->world_width)
    if(0<=y<w->world_height) {
      return FrogNumNew(w->ceilmap[x+y*w->world_width]);
    }
  return FrogNumNew(I16_MAX);
}
AddMethod("C3DWorldManager","ceilHeightAtX:atY:",&WorldManagerCeilHeightAtXAtY);
CFrogThing *WorldManagerTileHeightAt(C3DWorldManager *self,...) {
  C2DPoint *p=argv[0];
  CFrogThing *ret=FrogNumNew(I16_MAX);
  C3DWorld *w=self->world_handle;
  if(0<=p->x<w->world_width)
    if(0<=p->y<w->world_height) {
      ret=FrogNumNew(w->heightmap[p->x+p->y*w->world_width]);
    }
  ThingDel(p);
  return ret;
}
AddMethod("C3DWorldManager","tileHeightAt:",&WorldManagerTileHeightAt);


CFrogThing *WorldManagerRaySideForTile(C3DWorldManager *self,...) {
  F64 x=AsF64(argv[0]);
  F64 y=AsF64(argv[1]);
  F64 a=AsF64(argv[2]);
  F64 h=AsF64(argv[3]);
  C2DPoint *p=argv[4];
  I64 force_tile=p->x+p->y*w->world_width;
  F64 oldx=w->x,oldy=w->y;
  I64 side;
  w->x=x;
  w->y=y;
  FindRayWall(w,
	    Tan(a),
	    Cos(a),
	    Sin(a),
	    NULL,
	    NULL,
	    &side,
	    h,
	    force_tile
	    );
  w->x=oldx;
  w->y=oldy;
  ThingDel(p);
  return FrogNumNew(side);
}
AddMethod("C3DWorldManager","raySideAtX:atY:atAngle:atHeight:forTile:",&WorldManagerRaySideForTile);

CFrogThing *WorldManagerRaySegmentForTile(C3DWorldManager *self,...) {
  F64 x=AsF64(argv[0]);
  F64 y=AsF64(argv[1]);
  F64 a=AsF64(argv[2]);
  F64 h=AsF64(argv[3]);
  F64 oldx=w->x,oldy=w->y;
  C2DPoint *p=argv[4];
  I64 force_tile=p->x+p->y*w->world_width;
  I64 segment;
  w->x=x;
  w->y=y;
  FindRayWall(w,
	    Tan(a),
	    Cos(a),
	    Sin(a),
	    &segment,
	    NULL,
	    NULL,
	    h,
	    force_tile
	    );
  w->x=oldx;
  w->y=oldy;
  ThingDel(p);
  return FrogNumNew(segment);
}
AddMethod("C3DWorldManager","raySegmentAtX:atY:atAngle:atHeight:forTile:",&WorldManagerRaySegmentForTile);


CFrogThing *WorldManagerRayTile(C3DWorldManager *self,...) {
  F64 x=AsF64(argv[0]);
  F64 y=AsF64(argv[1]);
  F64 a=AsF64(argv[2]);
  F64 h=AsF64(argv[3]);
  F64 oldx=w->x,oldy=w->y;
  I64 tile;
  w->x=x;
  w->y=y;
  tile=FindRayWall(w,
	    Tan(a),
	    Cos(a),
	    Sin(a),
	    NULL,
	    NULL,
	    NULL,
	    Floor(h),
	    );
  w->x=oldx;
  w->y=oldy;
  C2DPoint *p=ConstructThing("C2DPoint");
  p->x=tile%w->world_width;
  p->y=tile/w->world_width;
  return p;
}
AddMethod("C3DWorldManager","rayTileAtX:atY:atAngle:atHeight:",&WorldManagerRayTile);

CFrogThing *ShellCasingSetGr(CShellCasing *self,...) {
  U8 *name=AsString(argv[0]);
  U8 *grl=BlobFileGetLump("ASS.BLOB",name);
  if(grl) {
    if(self->dc) AnimDCDel(self->dc);
    self->dc=AnimDCLoad(grl); 
  }
  Free(name),Free(grl); 
  ThingDel(argv[0]);
  return FROG_SMALL_NIL;
}
AddMethod("CShellCasing","setGraphics:",&ShellCasingSetGr);
U0 ShellCasingDel(CShellCasing *c) {
  if(c->dc) AnimDCDel(c->dc);
  Free(c);
}
CFrogThing *HandItemSetGr(CHandItem *self,...) {
  U8 *name=AsString(argv[0]);
  U8 *grl=BlobFileGetLump("ASS.BLOB",name);
  if(grl) {
    if(self->gr)
      AnimDCDel(self->gr);
    self->gr=AnimDCLoad(grl);
    Free(grl);
  }
  ThingDel(argv[0]);
  Free(name);
  return FROG_SMALL_NIL;
}
AddMethod("CHandItem","setGraphics:",&HandItemSetGr);
U0 HandItemDel(CHandItem *i) {
  if(i->gr) AnimDCDel(i->gr);
  Free(i);
}
CFrogThing *ThingCanSeeThing(C2DThing *self,...) {
  F64 old_x=w->x,old_y=w->y,old_z=w->cam_height;
  CFrogThing *ret;
  C2DThing *other=argv[0];
  w->x=self->x;
  w->y=self->y;
  w->cam_height=self->z;
  ret=FrogNumNew(CanSee2DThing(w,other));
  w->x=old_x;
  w->y=old_y;
  w->cam_height=old_z;
  ThingDel(other);
  return ret;
}
AddMethod("C2DThing","canSeeThing:",&ThingCanSeeThing);


CFrogThing *ScreenCoordToDist(C3DWorldManager *self,...) {
  return FrogNumNew(ScreenCordsToDist(w,self->screen_x,self->screen_y));
}
AddMethod("C3DWorldManager","screenCoordToDist",&ScreenCoordToDist);
CFrogThing *ScreenCoordToX(C3DWorldManager *self,...) {
  I64 x=self->screen_x;
  F64 angle=w->angle+w->fov/2*((x-GR_WIDTH/2)/ToF64(GR_WIDTH)),dist;
  dist=ScreenCordsToDist(w,self->screen_x,self->screen_y);
  return FrogNumNew(w->x+dist*Cos(angle));
}
AddMethod("C3DWorldManager","screenCoordToX",&ScreenCoordToX);
CFrogThing *ScreenCoordToY(C3DWorldManager *self,...) {
  I64 x=self->screen_x;
  F64 angle=w->angle+w->fov/2*((x-GR_WIDTH/2)/ToF64(GR_WIDTH)),dist;
  dist=ScreenCordsToDist(w,self->screen_x,self->screen_y);
  return FrogNumNew(w->y+dist*Sin(angle));
}
AddMethod("C3DWorldManager","screenCoordToY",&ScreenCoordToY);
CFrogThing *ScreenCoordToZ(C3DWorldManager *self,...) {
  F64 h;
  ScreenCordsToDist(w,self->screen_x,self->screen_y,,&h);
  return FrogNumNew(h);
}
AddMethod("C3DWorldManager","screenCoordToZ",&ScreenCoordToZ);
CFrogThing *ScreenCoordOnFloor(C3DWorldManager *self,...) {
  Bool of=1;
  ScreenCordsToDist(w,self->screen_x,self->screen_y,,,&of);
  return FrogNumNew(of);
}
AddMethod("C3DWorldManager","screenCoordIsOnFloor",&ScreenCoordOnFloor);
//
// Test section
//
#ifdef TEST_3D
#include "UI.HC"
DocClear;
w=LoadWorldFromFile(,"Untitled.WORLD");
I64 mp_thing_done=0;
/*U0 MPDrawThings(C3DWorld *w) {
 I64 mpc=mp_cnt-1,idx=w->_2d_things->cnt;
  C2DThing *t,**body=w->_2d_things->body;
  LBtr(&mp_thing_done,Gs->num);
  while(--idx>=0) {
    if(idx%mpc==Gs->num) {
      Draw2DThing(w,body[idx]);
    }
  }
  LBts(&mp_thing_done,Gs->num);
}*/
U0 DrawIt(CTask *t,CDC *dc) {
  CDC *hand_gr;
  CDC *odc=dc;
  I32 *odepth_buf;
  I64 tx,ty,c;
  CI64Set *s;
  C3DParticle *p,*head,*n;
  CShellCasing *shellc;
  CPlayer *player;
  CFrogSymbol *man=FrogSymbol("world");
  CHandItem *hand=FrogSymbol("hand_item")->value;

  dc=w->to_dc;
  DCFill(dc,TRANSPARENT);
  DCDepthBufRst(dc);
  odepth_buf=dc->depth_buf;
  InitTables(w->angle,w->fov);
  C3DWorldCastRays(w);   
  mp_thing_done=0;
/*  for(c=1;c!=mp_cnt;c++) {
    JobQue(&MPDrawThings,w,c);
  }
  for(c=0;c!=mp_cnt;c++) { 
    while(!Bt(&mp_thing_done,c))
      Sleep(1);
  }*/
  CFrogThing ***body=w->_2d_things->body;
  I64 idx=w->_2d_things->cnt;
  while(--idx>=0)
    Draw2DThing(w,body[idx]);
  
  head=&w->particles;
  for(p=head->next;head!=p;p=p->next) {
    p->x+=p->momx;
    p->y+=p->momy;
    p->z+=p->momz;
    p->momx*=20/30.;
    p->momy*=20/30.;
    p->momz-=.2;
    tx=p->x/GRID_SZ;
    ty=p->y/GRID_SZ;
    if(0<=tx<w->world_width)
      if(0<=ty<w->world_height) {
	p->z=Max(w->heightmap[tx+ty*w->world_width]-1,p->z);
      }
    DrawParticle(w,p);
    if(tS>1+p->born_at) {
      n=p->next;
      QueRem(p);
      Free(p);
      w->particle_cnt--;
    }
  }
  w->to_dc->depth_buf=NULL;

  
  Fs->user_data=0;
  player=CallScript("getPlayer",man->value);
  if(ThingHasClass(player,"CPlayer")) {
    if(ThingHasClass(player->shell_casings,"CFrogArray")) {
      s=player->shell_casings->items;
      body=s->body;
      idx=s->cnt;
      while(--idx>=0) {
        shellc=body[idx];
	if(ThingHasClass(shellc,"CShellCasing")) {
	  if(shellc->dc)
	   GrBlot(dc,shellc->x,shellc->y,shellc->dc);
	}
      }
   }
  } 

  if(ThingHasClass(hand,"CHandItem")) {
    hand->x=ms.pos.x;
    if(hand_gr=hand->gr) {
      GrBlot(dc,hand->x+hand->xoff-hand_gr->width/2,hand->y+hand->yoff-hand_gr->height/2,hand_gr);
    }
  }
  DrawUIRoot(t,dc);
  DCBlotColor8(odc,dc);
  dc->depth_buf=odepth_buf;
}
U0 WalkAround() {
  I64 c,ch=0,sc=0,m1,m2,msg,jump=FALSE;
  I64 msx=GR_WIDTH/2,msy=GR_HEIGHT/2;
  F64 mouse_angle;
  F64 x=9*GRID_SZ,y=5*GRID_SZ;
  Bool up=FALSE,down=FALSE,right=FALSE,left=FALSE,cont=TRUE;
  CFrogSymbol *man=FrogSymbol("world");
  CPlayer *player=CallScript("getPlayer",man->value);
  CUIElem *ui_root=FrogSymbol("ui_root")->value;
  CShellCasing *shellc;
  C3DWorldManager *wm=man->value;
  WinMax;
  WinBorder;
  AutoComplete;
  Fs->draw_it=&DrawIt;
  w->x=x,w->y=y;
  w->cam_height=.8;
  w->angle=0;
  CFrogThing **body;
  I64 idx;
//  Prof(10);
  try while (cont) {
      CallScript("update",man->value);
//if (ThingHasClass(player,"CPlayer")) {
      // set vars for multikey input
      while(msg=ScanMsg(&m1,&m2)) {        
	if(ThingHasClass(ui_root,"CUIElem"))
	  if(UpdateUI(ui_root,msg,m1,m2)) {
//Dont move during UI
	    up=FALSE;
	    down=FALSE;
	    left=FALSE;
	    right=FALSE;
	    goto next;
	  }
        switch (msg) {
	    break;case MSG_MS_L_DOWN:
	      msx=m1,msy=m2;
	    break;case MSG_MS_MOVE:
	      msx=m1,msy=m2;
	    break;case MSG_KEY_DOWN:
	    ch=m1,sc=m2;
	    if (!ch) switch (sc.u8[0]) {
	        case SC_CURSOR_RIGHT: right=TRUE; break;
	        case SC_CURSOR_LEFT: left=TRUE; break;
	        case SC_CURSOR_UP: up=TRUE; break;
	        case SC_CURSOR_DOWN: down=TRUE; break;
	      } else switch (ToUpper(ch)) {
	        case '\n':
	        case CH_ESC:
	        case CH_SHIFT_ESC: {
		  //No jumping out of try block
		  //goto en;
		  cont=FALSE;
		}
		case ' ': jump=TRUE; break;
	        case 'W': up=TRUE; break;
	        case 'A': left=TRUE; break;
	        case 'S': down=TRUE; break;
	        case 'D': right=TRUE; break;
	      }
	    break;case MSG_KEY_UP:
	    ch=m1,sc=m2;
	    if (!ch) switch (sc.u8[0]) {
	        start:
		  case SC_CURSOR_RIGHT: right=FALSE; break;
		  case SC_CURSOR_LEFT: left=FALSE; break;
		  case SC_CURSOR_UP: up=FALSE;break;
		  case SC_CURSOR_DOWN: down=FALSE; break;
	        end: sc=0;
	      } else switch (ToUpper(ch)) {
	        case 'W': up=FALSE; break;
	        case 'A': left=FALSE; break;
	        case 'S': down=FALSE; break;
	        case 'D': right=FALSE; break;
	      }
        }
next:;
      }
      if (jump) {
         CallScript("jump",player);
         jump=FALSE;
      }
      if (up)
        C2DThingMoveAtAngle(player,
	      FrogNumNew(GRID_SZ/4),
	      FrogNumNew(player->angle));
      if (down)
        C2DThingMoveAtAngle(player,
	      FrogNumNew(-GRID_SZ/4),
	      FrogNumNew(player->angle));
      if (left) {
        C2DThingMoveAtAngle(player,
	      FrogNumNew(GRID_SZ/4),
	      FrogNumNew(player->angle-pi/2));
      }
      if (right)
        C2DThingMoveAtAngle(player,
	      FrogNumNew(GRID_SZ/4),
	      FrogNumNew(player->angle+pi/2));
      if(msx<SCRN_TURN_MARGIN) {
	player->angle-=ToF64(SCRN_TURN_MARGIN-msx)/SCRN_TURN_MARGIN*SCRN_TURN_RATE;
      } else if(msx>GR_WIDTH-SCRN_TURN_MARGIN) {
	player->angle+=ToF64(msx-(GR_WIDTH-SCRN_TURN_MARGIN))/SCRN_TURN_MARGIN*SCRN_TURN_RATE;
      }
      if (ms.lb&&msy<GR_HEIGHT-75) { // mouse input is best handled with ms, not ScanMsg
	mouse_angle=(ms.pos.x-GR_WIDTH/2)*(w->fov/GR_WIDTH);
	player->angle+=mouse_angle;
        CallScript("fire",FrogSymbol("hand_item")->value);
	player->angle-=mouse_angle;
      }
      wm->screen_x=ms.pos.x;
      wm->screen_y=ms.pos.y;
      w->x=player->x;
      w->y=player->y;
      w->angle=player->angle+.001;
      w->cam_height=player->z+.6;
      w->angle%=2*pi;
      if(w->angle<0)
        w->angle+=2*pi;
      if(ThingHasClass(player->shell_casings,"CFrogArray")) {
        body=player->shell_casings->items->body;
        idx=player->shell_casings->items->cnt;
        while(--idx>=0) {
          shellc=body[idx];
	  if(ThingHasClass(shellc,"CShellCasing")) {
	    CallScript("update",shellc);
	  }
        }
     }
      Refresh;
      FrogGarbageCollect;
    } catch PutExcept(TRUE);
en:
//  ProfRep;
  FlushMsgs;
  Refresh;
  Fs->draw_it=NULL;
}
WalkAround;
#endif
#endif        i               8      8   ßÿÿÿ   Ýÿÿÿ      	'   öÿÿÿ?   áÿÿÿ

'   ÷ÿÿÿ5   ÷ÿÿÿ
'   ÷ÿÿÿ(   ßÿÿÿ 