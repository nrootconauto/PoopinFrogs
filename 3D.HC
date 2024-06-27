#include "AnimDC.HC"
#include "BlobFile.HC";
#include "SmallTalk/Load.HC"
#include "Intersect.HC";
#define TEST_3D
#ifndef ENGINE_3D
extern I64 *GetTilesInPath(U8 *w,F64 angle,F64 dist);
#define ENGINE_3D 1
#define SCRN_TURN_MARGIN 100
#define SCRN_TURN_RATE (pi/30.)
I64 cpu_job_cnts_lock=0;
I64 cpu_job_cnts[mp_cnt];
MemSetI64(cpu_job_cnts,0,mp_cnt);
class CCSPair {
  U8 *name;
  CFrogThing *thing;
  CHashTable *ht;
};
U0 JobCallScript(CCSPair *p) {
  CHashTable *t=Fs->hash_table;
  Fs->hash_table=p->ht;
  CallScript(p->name,p->thing);
  Free(p);
  while(LBts(&cpu_job_cnts_lock,Gs->num))
    Yield;
  cpu_job_cnts[Gs->num]--;
  LBtr(&cpu_job_cnts_lock,Gs->num);
  Fs->hash_table=t;
}
U0 QueCallScript(U8 *name,CFrogThing *t) {
  CallScript(name,t);
}
U0 WaitForJobsFinish() {
  I64 c=mp_cnt-1;
  while(c>=0) {
    while(LBts(&cpu_job_cnts_lock,c)) {
      Sleep(1);
    }
    if(!cpu_job_cnts[c]) {
      LBtr(&cpu_job_cnts_lock,c);
      c--;
    } else
      LBtr(&cpu_job_cnts_lock,c);
  }
}
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
};
#define DOORF_SMALL_KEY 1
#define DOORF_BIG_KEY 2
#define DOORF_TO_CEILING 4
#define DOORF_SIDE_DOOR 8
class CFileDoor {
  I64 x,y,act_as_wall;
  F64 height;
  I64 flags;
};
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
  CFilePtrLen wolrd_start;
  CFilePtrLen doors;
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
#define THING_RADIUS (GRID_SZ/3)
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
   CQue particles;
   I64 particle_cnt;
};
C3DWorld *w;
extern U0 Draw2DThing(C3DWorld *w,C3DThing *thing);
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
U0 C3DThingTemplateDel(C3DThingTemplate *t) {
  if(t->front) DCDel(t->front);
  if(t->side) DCDel(t->side);
  if(t->back) DCDel(t->back);
  Free(t);
}
U0 C3DWorldSetFov(C3DWorld *w,F64 fov=pi/4) {
  w->fov=fov;
}
C3DWorld *LoadWorldFromFile(U8 *blob_file="ASS",U8 *filename,F64 fov=pi/4) {
  C3DWorld *ret=CAlloc(sizeof(C3DWorld));
  CFileWorld *world=BlobFileGetLump(blob_file,filename);
  F64 xoff,yoff;
  U8 *fptr=world,*to,*tmp;
  I64 idx;
  CDC *unscaled;
  C3DThingTemplate **templates=CAlloc(0x10000*8),*template;
  C3DThing *thing;
  C3DWorldManager *man;
  C3DWorldSetFov(ret,fov);
  CDoor *door;
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
  w=ret;
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
    template=ConstructThing("C3DThingTemplate");
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
        if(ThingHasClass(thing,"C3DThing")) {
	  thing->x=fptr(CFileThing*)->x*GRID_SZ-xoff;
	  thing->y=fptr(CFileThing*)->y*GRID_SZ-yoff;
	  thing->angle=fptr(CFileThing*)->rot;
	  CallScript("init",thing);
//Things add themselves to the world
//	  I64SetAdd(ret->_2d_things,thing);
        }
      }
      Free(tmp);
    }
    fptr(CFileThing*)++;
  }
  fptr=world(U8*)+world->doors.ptr;
  to=fptr+world->doors.len;
  while(fptr<to) {
    door=ConstructThing("CDoor");
    CallScript("init",door);
    door->x=fptr(CFileDoor*)->x-world->startx;
    door->y=fptr(CFileDoor*)->y-world->starty;
    door->act_as_wall=fptr(CFileDoor*)->act_as_wall;
    door->height=fptr(CFileDoor*)->height;
    door->small_key=fptr(CFileDoor*)->flags&DOORF_SMALL_KEY;
    door->big_key=fptr(CFileDoor*)->flags&DOORF_BIG_KEY;
    door->rise_to_ceiling=fptr(CFileDoor*)->flags&DOORF_TO_CEILING;
    door->side_door=fptr(CFileDoor*)->flags&DOORF_SIDE_DOOR;
    fptr(CFileDoor*)++;
    CallScript("addDoor:",man,door);
  }
  Free(world);
  Free(templates);
  return ret;
}


I64 WallForCord(C3DWorld *w,I64 x,I64 y,I64 h=I64_MIN) {
  I64 t,ch,cr;
  if(0<=x<w->world_width)
    if(0<=y<w->world_height) {
      t=w->world_mat[x+y*w->world_width];
//u8[0] is the floor tile
      if(w->wall_textures[t&0xff]&&w->heightmap[x+y*w->world_width]>h)
         return t;
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
      if(dist) {
        tmp=Sqrt(Sqr(cx1*GRID_SZ)+Sqr(tmp*GRID_SZ));
        smallest=Min(smallest,tmp);
        biggest=Max(biggest,tmp);
      }
      found=TRUE;
    }
  } else {
//Right side
    tmp=cx2*slope;
    if(cy1<=tmp<=cy2) {
      found=TRUE;
      if(dist) {
        tmp=Sqrt(Sqr(cx2*GRID_SZ)+Sqr(tmp*GRID_SZ));
        smallest=Min(smallest,tmp);
        biggest=Max(biggest,tmp);
      }
    }
  }
  if(sin>0.^^far_side) {
//top side
    tmp=cy1/slope;
    if(cx1<=tmp<=cx2) {
      if(dist) {
        tmp=Sqrt(Sqr(cy1*GRID_SZ)+Sqr(tmp*GRID_SZ));
        smallest=Min(smallest,tmp);
        biggest=Max(biggest,tmp);
      }
      found=TRUE;
    }
  } else {
//bottom side
    tmp=cy2/slope;
    if(cx1<=tmp<=cx2) {
      if(dist) {
        tmp=Sqrt(Sqr(cy2*GRID_SZ)+Sqr(tmp*GRID_SZ));
        smallest=Min(smallest,tmp);
        biggest=Max(biggest,tmp);
      }
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
class CPlatformCache {
  I64 x,y;
  F64 h;
} platform_cache[16][mp_cnt];
I64 platform_cache_ptr[mp_cnt];
MemSetI64(platform_cache_ptr,0,mp_cnt);
//Maybe a door raised
U0 ClearPlatformCache() {
  I64 c,cache;
  c=mp_cnt;
  while(--c>=0) {
    cache=16;
    while(--cache>=0) {
      platform_cache[cache][c].x=-1;
      platform_cache[cache][c].y=-1;
    }
  }
}
F64 GetPlatformHeight(C3DWorld *w,I64 ix,I64 iy) {
  I64 idx=iy*w->world_width+ix,cache;
  I64 c=Gs->num;
  for(cache=0;cache!=16;cache++) {
    if(platform_cache[cache][c].x==ix&&platform_cache[cache][c].y==iy) {
      return platform_cache[cache][c].h;
    }
  }
  F64 h=AsF64(CallScriptUniverse(
	#exe{StreamPrint("%d",NameToUniverseNumber("getPlatformHeightAtX:atY:"));},
          FrogSymbol0(#exe{StreamPrint("%d",NameToUniverseNumber("world"));})->value,
	  FrogNumNew(ix*GRID_SZ+GRID_SZ/2),
	  FrogNumNew(iy*GRID_SZ+GRID_SZ/2)
  ));
  cache=platform_cache_ptr[c]++&15;
  platform_cache[cache][c].x=ix;
  platform_cache[cache][c].y=iy;
  platform_cache[cache][c].h=h;
  return h;
}
Bool HeightImpossible(C3DWorld *w,I64 ix,I64 iy,F64 above,Bool allow_ceil,F64 tallness=.1,F64 wiggle_room=0) {
  I64 c,idx=iy*w->world_width+ix,cache;
  F64 h;
  if(0<=ix<w->world_width)
    if(0<=iy<w->world_height) {
      if(1) {
        h=GetPlatformHeight(w,ix,iy);
      } else
	h=w->heightmap[idx];
      if(above+wiggle_room<h) //wiigle_room for stepping over partlyy open doors
	return TRUE;
      c=w->ceilmap[idx];
      if(c!=I8_MAX)
        if(c<above<c+w->ceilmap2[idx]) {
	  return TRUE;
      }
    }
  return FALSE;
}

I64 FindRayWall(C3DWorld *w,F64 slope,F64 cos,F64 sin,I64 *segment=NULL,F64 *dist=NULL,I64 *side=NULL,F64 above=I8_MIN,I64 force_tile=INVALID_PTR,Bool far_side=FALSE,Bool allow_ceil=FALSE) {
  F64 x=w->x;
  F64 y=w->y;
  Bool found_hit=FALSE;
  I64 ix=x/GRID_SZ,iy=y/GRID_SZ,iy2,seg,ix2;
  F64 smallest=1e100;
  F64 hit_x=-1,hit_y=-12345,dist2=32*GRID_SZ,check_dist=0,t1,t2,wall_x,wall_y,res_dist;
  I64 sign_c=Sign(cos),sign_s=Sign(sin);
  static F64 step=GRID_SZ-1;
  if(dist) *dist=-1;
  if(force_tile!=INVALID_PTR) {
    ix=force_tile%w->world_width;
    iy=force_tile/w->world_width;
    if(!PassesThoughBlock(w,slope,ix,iy,&res_dist,cos,sin,far_side)) {
      if(dist) *dist=res_dist;
      goto undef;
    }
    smallest=res_dist;
    check_dist=res_dist;
    ix2=ix;
    iy2=iy;
    goto final;
  }
  while(check_dist<dist2) {
    check_dist+=step;
    x=w->x+check_dist*cos;
    y=w->y+check_dist*sin;
    ix=x/GRID_SZ,iy=y/GRID_SZ;
    if(HeightImpossible(w,ix,iy,above,allow_ceil)&&PassesThoughBlock(w,slope,ix,iy,&res_dist,cos,sin)) {
      found_hit=TRUE;
      if(res_dist<smallest) {
        smallest=res_dist;
        ix2=ix;
        iy2=iy;
      }
    }
    if(check_dist>ToF64(GRID_SZ)) {
      if(HeightImpossible(w,ix-sign_c,iy,above,allow_ceil)&&PassesThoughBlock(w,slope,ix-sign_c,iy,&res_dist,cos,sin)) {
        found_hit=TRUE;
        if(res_dist<smallest) {
	  smallest=res_dist;
	  ix2=ix-sign_c;
	  iy2=iy;
        }
      }
      if(HeightImpossible(w,ix,iy-sign_s,above,allow_ceil)&&PassesThoughBlock(w,slope,ix,iy-sign_s,&res_dist,cos,sin)) {
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
    if(!cos) t1=1000000;
    else t1=(wall_x-w->x)/cos;
    if(!sin) t2=1000000;
    else t2=(wall_y-w->y)/sin;

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
C3DThing *BumpsIntoThing(C3DThing *self,...) {
  C3DThing *who=argv[0];
  F64 radius=THING_RADIUS*THING_RADIUS;
  F64 x,y;
  x=who->x-self->x;
  y=who->y-self->y;
  if(radius>=x*x+y+y)
    return FrogNumNew(1);
  return FrogNumNew(0);
} 
AddMethod("C3DThing","hitsThing:",&BumpsIntoThing);
#define RADF_CEIL 1
#define RADF_FLOOR 2
#define RADF_DOOR 4
Bool RadiusHitsWall(C3DWorld *w,F64 angle,F64 *_x,F64 *_y,F64 height,F64 radius=THING_RADIUS,Bool adjust=FALSE,F64 tallness=.8,I64 flags=RADF_CEIL|RADF_FLOOR) {
  F64 x=*_x;
  F64 y=*_y;
  x/=GRID_SZ;
  y/=GRID_SZ;
  radius/=GRID_SZ;
  F64 by=1/4.;
  Bool ret=FALSE,hit=TRUE;
  I64 xoff,yoff,ch,cr,tile,i;
  F64 tx,ty,h;
  do {
    hit=FALSE;
  for(i=0;i!=4;i++)  {
    for(xoff=-1;xoff<2;xoff++)
      for(yoff=-1;yoff<2;yoff++) {
        if(xoff^^yoff) {
	  switch(xoff) {
	    case -1:
	      tx=Floor(x);
	      break;
	    case 0:
	      tx=x;
	      break;
	    case 1:
	      tx=Ceil(x);
	      break;
	  }
	  switch(yoff) {
	    case -1:
	      ty=Floor(y);
	      break;
	    case 0:
	      ty=y;
	      break;
	    case 1:
	      ty=Ceil(y);
	      break;
	  }
//ONLY CHECK FOR WALL WE ARE WALKING TOWARDS
          if(xoff) {
	    if(Sign(Cos(angle))!=xoff)
	      goto skip;
	  }
          if(yoff) {
	    if(Sign(Sin(angle))!=yoff)
	      goto skip;
	  }
	  tile=ToI64(x)+xoff+(ToI64(y)+yoff)*w->world_width;
	  if(0<=tile<w->world_height*w->world_width) {
	    if(flags&RADF_DOOR) {
	      h=GetPlatformHeight(w,x+xoff,y+yoff);
	    } else
	      h=w->heightmap[tile];
	    ch=w->ceilmap[tile];
	    cr=w->ceilmap2[tile];
//.2 for stepping over partly open doors
	    if(flags&RADF_FLOOR&&height+.2<h) {
check:
	        if(Abs(x-tx)<=radius&&xoff) {
	          if(adjust) {
		    x=tx+radius*1.05*-xoff;
		    hit=TRUE;
	          }
	          ret|=TRUE;
	        }
	        if(Abs(y-ty)<=radius&&yoff) {
	          if(adjust) {
		    y=ty+radius*1.05*-yoff;
		    hit=TRUE;
	          }
	          ret|=TRUE;
	        }
	    } else if(flags&RADF_CEIL&&ch<=height+tallness<ch+cr) {
	      goto check;
	    }
	  }
skip:;
        }
      }
  }
  } while(hit);
  if(adjust) {
    *_x=x*GRID_SZ;
    *_y=y*GRID_SZ;
  }
  return ret;
}
Bool C3DWorldMoveZWithCollision(C3DWorld *w,F64 dist,F64 x,F64 y,F64 *_height,F64 tallness=.8) {
  F64 height=*_height;
  F64 z=height;
  F64 o=height;
  F64 by=dist/8;
  Bool hit=FALSE;
  F64 h_offset=0;
  F64 h;
  I64 cnt=0,tile,best,ch,cr;
  z+=dist;
  tile=ToI64(x/GRID_SZ)+ToI64(y/GRID_SZ)*w->world_width;
  if(0<=tile<w->world_width*w->world_height) {
    if(HeightImpossible(w,x/GRID_SZ,y/GRID_SZ,z,TRUE,.8,)) {
      h=GetPlatformHeight(w,x/GRID_SZ,y/GRID_SZ);
      ch=w->ceilmap[tile];
      cr=w->ceilmap2[tile];
     if(ch<=z) {
        o=z;
        z=Max(z,ch+cr);
        hit|=o!=z;
      } else {
        o=z;
        z=Clamp(z,h,ch-tallness);
        hit|=o!=z;
      }
    }
  }
  *_height=z;
  return hit;
}
//Returns true on wall hit
Bool C3DWorldMoveWithCollision(C3DWorld *w,F64 angle,F64 dist,F64 *x,F64 *y,Bool walk_along_wall=TRUE,F64 height=0) {
  F64 dist2=0,boundary;
  Bool hit_wall=FALSE,force;
  F64 old_x=w->x,old_y=w->y,deflect_angle;
  w->x=*x,w->y=*y;
  I64 at_tile;
  if(dist<0.) angle+=pi,dist=-dist;
  I64 idx,idx2;
  I64 h,ch,cr;
    if(RadiusHitsWall(w,angle,x,y,height,THING_RADIUS,TRUE,,RADF_CEIL|RADF_FLOOR|RADF_DOOR)) {
      hit_wall=TRUE;
      goto fin;
    }
  while(dist2<dist) {
    for(idx=0;idx!=5;idx++) {
    dist2+=GRID_SZ/5.;
    if(dist2>=dist) dist2=dist;
    *x=w->x+Cos(angle)*dist2;
    *y=w->y+Sin(angle)*dist2;
    if(RadiusHitsWall(w,angle,x,y,height,THING_RADIUS,TRUE,,RADF_CEIL|RADF_FLOOR|RADF_DOOR)) {
      hit_wall=TRUE;
      goto fin;
    }
      if(HeightImpossible(w,*x/GRID_SZ,*y/GRID_SZ,height,TRUE,,.2)) {//.2 wiggle room for stepping over partly open doors
//Totally reject move,something when wrong
//     (would be placed on top of unreachable wall)
	*x=w->x;
	*y=w->y;
        hit_wall=TRUE;
        goto fin;
      }
    if(dist2>=dist)
      goto fin;
    }
  }
fin:
  w->x=old_x,w->y=old_y;
  return hit_wall;
}
Bool AdjustRadiusThing(C3DWorld *w,C3DThing *self,C3DThing *other,F64 angle) {
  F64 sr=THING_RADIUS;
  F64 or=THING_RADIUS;
  F64 dist,push_back;
  I64 attempt=0;
  Bool ret=FALSE;
again:
  dist=Sqrt(Sqr(other->x-self->x)+Sqr(other->y-self->y));
  if(dist<or+sr) {
    push_back=(sr+or-dist)*.1*1.4;
    C3DWorldMoveWithCollision(w,angle+pi,push_back,
	&self->x,
	&self->y,
	TRUE, //Slide along wall
	self->z);
    if(++attempt<15) goto again;
  }
  return ret;
}
U0 PhysicsOnThing(C3DWorld *w,C3DThing *t,C3DWorldManager *wm) {
  I64 wx=t->x/GRID_SZ,wy=t->y/GRID_SZ;
  if(!(0<=wx<w->world_width))
    return;
  if(!(0<=wy<w->world_height))
    return;
  F64 angle;
  I64 tile=wx+wy*w->world_width;
  I64 floor=w->heightmap[tile];
  I64 ceil=w->ceilmap[tile];
  I64 raise=w->ceilmap2[tile],idx;
  Bool i_am_moving=FALSE;
  CRocket *rocket=NULL;
  CFrogArray *in_radius;
  CDoor *to_open;
  CI64Set *set;
  if(ThingHasClass(t,"CRocket"))
    rocket=t;
  CallScript("removeFromGrid:",wm,FrogIncRefCnt(t));
  if(C3DWorldMoveZWithCollision(w,t->momz,t->x,t->y,&t->z)) {
    t->momz=0;
  } else if(!rocket)
      t->momz-=wm->gravity;
  if(t->momy+t->momy2||t->momx+t->momx2) {
    if(!rocket) {
      t->momx*=29/30.;
      t->momy*=29/30.;
    }
    if(Abs(t->momx)<2) t->momx=0;
    if(Abs(t->momy)<2) t->momy=0;
    angle=Arg(t->momx+t->momx2,t->momy+t->momy2);
    i_am_moving=TRUE;
    if(C3DWorldMoveWithCollision(w,angle,Sqrt(Sqr(t->momx+t->momx2)+Sqr(t->momy+t->momy2)),
	&t->x,
	&t->y,
	TRUE,
	t->z)) {
	
hit:
      if(rocket) {
explode:
        CallScript("explode",rocket);
        return;
      } else if(!ThingHasClass(t,"CPickup")) {
        to_open=CallScript("doorInRadius:atX:atY:atAngle:",
	  wm,FrogNumNew(THING_RADIUS),FrogNumNew(t->x),FrogNumNew(t->y),FrogNumNew(t->angle));
        if(ThingHasClass(to_open,"CDoor")) {
           CallScript("activateBy:",to_open,t);
        }
      }
    } 
  } else if(RadiusHitsWall(w,angle,&t->x,&t->y,t->z,THING_RADIUS,TRUE,,RADF_CEIL|RADF_FLOOR|RADF_DOOR))
    goto hit;
  if(rocket) {
    if(!(0.<=t->x<w->world_width*128))
      goto explode;
    if(!(0.<=t->y<w->world_height*128))
      goto explode;
    CallScript("checkExplode",rocket);
  }
//Only check for thing collision if we are the ones movin
  if(i_am_moving&&!rocket) {
    in_radius=CallScript("getObstaclesInRadiusForThing:inRadius:",wm,t,FrogNumNew(2*THING_RADIUS));
    set=in_radius->items;
    for(idx=0;idx!=set->cnt;idx++) {
      if(set->body[idx]!=t)
        AdjustRadiusThing(w,t,set->body[idx],angle);
    }  
  }
  CallScript("updateThingPos:",wm,FrogIncRefCnt(t));
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
U0 DrawWallSegment(C3DWorld *w,I64 segment,I64 x,I64 start_y,CDC *texture,I64 height,I64 dist,F64 z,I64 tile_idx,I64 side) {
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
    if(i+start_y<0) {
      i=-start_y;
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
CDC *FloorStain(C3DWorld *w,I64 tx,I64 ty,I64 *xoff,I64 *yoff,Bool ceil) {
  CFloorStain **body=w->_floor_stains->body,*f;
  I64 idx=w->_floor_stains->cnt;
  I64 adjx,adjy;
  while(--idx>=0) {
    f=body[idx];
//    if(ThingHasClass(f,"CFloorStain"))
    if(f->tile_x==tx&&f->tile_y==ty&&f->dc&&ceil==f->is_ceil) {
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
          if(f->tile_x==tx+adjx&&f->tile_y==ty+adjy&&f->dc&&ceil==f->is_ceil) {
  	    if(xoff) *xoff=f->x-f->center_x+adjx*GRID_SZ;
 	    if(yoff) *yoff=f->y-f->center_y+adjy*GRID_SZ;
            return f->dc;
          }
        }
  }
  return NULL;
}

I64 ColorFloor(C3DWorld *w,I64 view_x,F64 floor_height,I64 sy,I64 ey,CDC *texture,Bool ceil=FALSE) {
  if(!texture) return ey;
  CDC *dc=w->to_dc,*stain=NULL;
  F64 angley=0;
  F64 step;
  F64 dist,dist2;
  I64 y,fx,fy,anim_frame=ToI64(tS/ANIM_DELAY)%AnimDCCnt(texture),idx,which,tx,ty,y2;
  I64 old_tx=-1,old_ty=-1;
  U64 colors,width=dc->width_internal,cnt;
  U8 *dst;
  I32 *db_z;
  U64 idist;
  I64 poopx,poopy,dir;
  I64 idist32;
  ey=GR_HEIGHT-ey;
  sy=GR_HEIGHT-sy;
  ey=ClampI64(ey,0,w->to_dc->height-w->step_width);
  sy=ClampI64(sy,0,w->to_dc->height-w->step_width);
  if(ceil) {dir=-1;y=ey;}
  else dir=1,y=sy;
  for(;TRUE;y+=w->step_width*dir) {
ent:
    if(y-GR_HEIGHT/2==0)
      dist=I16_MAX;
    else {
      dist=DIST_SCALE/((GR_HEIGHT/2-y)/(w->cam_height-floor_height));
    }
    dist/=cos2_lookup_table[view_x];
    if(!(sy<=y<=ey))
      break;
    fx=w->x+cos_lookup_table[view_x]*dist;
    fy=w->y+sin_lookup_table[view_x]*dist;
    tx=fx/GRID_SZ;
    ty=fy/GRID_SZ;
//Floors stains from the camera can barley be seen when far away
    if(dist<16*128) {
      if(old_tx!=tx||old_ty!=ty) {
        stain=FloorStain(w,tx,ty,&poopx,&poopy,ceil);
        old_tx=tx;
        old_ty=ty;
      }
    } else
      stain=NULL;
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
        if(0<=y<dc->height-w->step_width) {
	  dst=dc->body+(dc->height-y-w->step_width)*width+view_x;
	  db_z=dc->depth_buf+(dc->height-y-w->step_width)*width+view_x;
	    idist=dist;
	    idist32=idist;
	    //Make 64bit pair
	    idist=(idist&0xffFFffFF)|idist<<32;
	    if(w->step_width==2){ 
	      if(*db_z>=idist32) {
	        dst(U16*)[0]=colors;
	        db_z[0](U64)=idist;
	      }
	      dst+=width;
	      db_z+=width;
	      if(*db_z>=idist32) {
	        dst(U16*)[0]=colors;
	        db_z[0](U64)=idist;
	      }
	    } else if(w->step_width==4) {
	      if(*db_z>=idist32) {
	        dst(U32*)[0]=colors;
	        db_z[0](U64)=idist;
	        db_z[2](U64)=idist;
	      }
	      dst+=width;
	      db_z+=width;
	      if(*db_z>=idist32) {
	        dst(U32*)[0]=colors;
	        db_z[0](U64)=idist;
	        db_z[2](U64)=idist;
	      }
	      dst+=width;
	      db_z+=width;
	      if(*db_z>=idist32) {
	        dst(U32*)[0]=colors;
	        db_z[0](U64)=idist;
	        db_z[2](U64)=idist;
	      }
	      dst+=width;
	      db_z+=width;
	      if(*db_z>=idist32) {
	        dst(U32*)[0]=colors;
	        db_z[0](U64)=idist;
	        db_z[2](U64)=idist;
	      }
	    }
        }
      }
    }
fin:
  return GR_HEIGHT-sy;
}
F64 FUMod(F64 v,F64 to) {
  if(v>0.) return v%to;
  if(v<0.) return -(v%to);
  return 0;
}
//-1 terminated
//https://en.wikipedia.org/wiki/Digital_differential_analyzer_(graphics_algorithm)
I64 *GetTilesInPath(C3DWorld *w,F64 angle,F64 dist) {
  CI64Set *t=I64SetNew;
  F64 x=w->x,y=w->y,ex,ey,dx,dy,step,i,by,slope,cos,sin,xdist,ydist;
  F64 res_dist;
  I64 tx=x/GRID_SZ,ty=y/GRID_SZ,idx,old_tx,old_ty,dirx,diry,ix,iy;
  Bool x_type;
  cos=Cos(angle);
  sin=Sin(angle);
  ex=x+cos*dist;
  ey=y+sin*dist;
  slope=Tan(angle);
  dx=ex-x;
  dy=ey-y;
  if(Abs(dx)>Abs(dy)) {
    step=Abs(dx);
  } else {
    step=Abs(dy);
  }
  dx/=step;
  dy/=step;
  idx=ty*w->world_width+tx;
  I64SetAdd(t,idx);
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
      if(xdist-x<1.) xdist+=GRID_SZ;
    } else if(cos<0.) {
      xdist=x-(GRID_SZ-FUMod(x,GRID_SZ));
      if(x-xdist<1.) xdist-=GRID_SZ;
    } else 
      xdist=x;
    if(sin>0.) {
      ydist=GRID_SZ-FUMod(y,GRID_SZ)+y;
      if(ydist-y<1.) ydist+=GRID_SZ;
    } else if(sin<0.) {
      ydist=y-(GRID_SZ-FUMod(y,GRID_SZ));
      if(y-ydist<1.) ydist-=GRID_SZ;
    } else 
      ydist=y;
    if(!dx) goto dy_type;
    if(!dy) goto dx_type;
    if(xdist-x>ydist-y) {
dx_type:
      x_type=TRUE;
      by=(xdist-x)/dx;
    } else {
dy_type:
      x_type=FALSE;
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
        if(t->body[t->cnt-1]!=idx) {
	  if(PassesThoughBlock(w,slope,ix,iy,&res_dist,cos,sin)) {
	    if(res_dist<dist)
	    I64SetAdd(t,idx);
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
    if(by<3.)
      by=3.;
    i+=by;
  }
fin:
  I64SetAdd(t,-1);
  I64 *tiles=t->body;
  Free(t);
  return tiles;
}
I64 mp_done=0;
F64 ScreenCordsToDist(C3DWorld *w,I64 x,I64 y,F64 max=GRID_SZ*128,F64 *height=NULL,Bool *hit_floor=FALSE) {
  F64 angle=w->angle+w->fov*((x-GR_WIDTH/2)/ToF64(GR_WIDTH));
  CDC *to_dc=w->to_dc;
  I32 have=I32_MAX;
  F64 wx,wy;
  F64 d=-1,dist,h,y0,dist2,h2,y1,hm;
  I64 tile2,tile;
//Check for floor from ZBuf
  if(0<=x<GR_WIDTH)
    if(0<=y<GR_HEIGHT) {
      have=to_dc->depth_buf[y*to_dc->width_internal+x];
    }
  I64 *tiles=GetTilesInPath(w,angle,max),idx;
  I64 total,xoff,yoff,adj_height,side;
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
	      TRUE, //Far side of tile
	      TRUE //allow ceil
	      );
	FindRayWall(w,
	      tan_lookup_table[x],
	      cos_lookup_table[x],
	      sin_lookup_table[x],
	      NULL,
	      &dist,
	      &side,
	      I8_MIN,
	      tile,
	      FALSE, //Near side of tile
	      TRUE //allow ceil
	      );
   adj_height=w->heightmap[tile];
    xoff=0;yoff=0;
    switch(side) {
       case 0:
	 xoff=-1;
	 break;
       case 1:
	 xoff=1;
	 break;
       case 2:
	 yoff=-1;
	 break;
       case 3:
	 yoff=1;
	 break;
    } 
    tile2=xoff+yoff*w->world_width+tile;
    if(0<=tile2<w->world_width*w->world_height&&(xoff^^yoff)) {
      adj_height=MinI64(adj_height,w->heightmap[tile2]);
    }
    hm=GetPlatformHeight(w,tile%w->world_width,tile/w->world_width);
    h=DIST_SCALE/(dist*cos2_lookup_table[x]);
    y0=GR_HEIGHT/2-h*(hm-w->cam_height);
    h2=DIST_SCALE/(dist2*cos2_lookup_table[x]);
    y1=GR_HEIGHT/2-h2*(hm-w->cam_height);    
    if(have<dist2) {
      if(y1-2<=y<=y0+2) {
	if(height) *height=hm;
	if(hit_floor) *hit_floor=TRUE;
	d=have;
	break;
      }
    }
    if(y0<=y<y0+h*(hm-adj_height)) {
//TODOtest floor intersection
      if(height) *height=Lerp((y-y0)/(h*(hm-adj_height)),hm,adj_height);
      d=dist;
      break;
    }
    if(w->ceilmap[tile]!=I8_MAX) {
      adj_height=w->ceilmap2[tile];
      total=w->ceilmap[tile];
      y0=GR_HEIGHT/2-h*(total+adj_height-w->cam_height);
      if(y0<=y<=y0+h*adj_height) {
        if(height) *height=Lerp((y-y0)/(h*adj_height),total+adj_height+1,total+1);
	d=dist;
	break;
      }
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
	  w->cam_height,
	  ,
	  ,
	  TRUE //allow ceil
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
  I64 height_cap,adj_height,last_height,floor_y,ceily,ceil,last_ceil;
  CDC *use_dc;
  I64 *tiles;
  I64 standing_at;
  I64 other,tile2; 
  Bool computed;
  idx=GR_WIDTH/mp_cnt*Gs->num;
  cap=GR_WIDTH/mp_cnt*(Gs->num+1);
  angle+=(w->fov/GR_WIDTH)*w->step_width*idx/w->step_width;
  for(x=idx;x<cap;angle+=(w->fov/GR_WIDTH)*w->step_width,x+=w->step_width) {
    idx2=0;
    dist=0;
    floor_y=GR_HEIGHT;
    ceily=0;
    last_height=I64_MIN;
    last_ceil=I64_MAX;
    tiles=GetTilesInPath(w,angle,64*GRID_SZ);
    if(tiles[0]==-1)
      goto fin;
ent:
    idx=tiles[idx2];
    if(idx!=-1) {
      idx2++;
      computed=FALSE;
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
//Compute far side
      PassesThoughBlock(w,
	tan_lookup_table[x],
	idx%w->world_width,
	idx/w->world_width,
	&dist2,
	cos_lookup_table[x],
	sin_lookup_table[x],
	TRUE //Far side
	);
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
//u8[0] is the flooro tile
	  if(w->floor_textures[w->world_mat[idx].u8[0]])
	    use_dc=w->floor_textures[w->world_mat[idx].u8[0]];
	  else
	    use_dc=w->wall_textures[w->world_mat[idx].u8[0]];
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
      adj_height=height_cap;
      xoff=0;yoff=0;
      switch(side) {
       case 0:
	 xoff=-1;
	 break;
       case 1:
	 xoff=1;
	 break;
       case 2:
	 yoff=-1;
	 break;
       case 3:
	 yoff=1;
	 break;
      } 
      tile2=xoff+yoff*w->world_width+idx;
      if(0<=tile2<w->world_width*w->world_height)
        adj_height=MinI64(adj_height,w->heightmap[tile2]);
//Dont straight lines on blocks with same height(hidden)
      if(last_height==height_cap)
        goto ceil2;
      last_height=height_cap;
      if(adj_height>=height_cap)
        goto ceil2;
      if(dist<=2.)
        goto ceil2;
      y=GR_HEIGHT/2;
      y0=GR_HEIGHT/2-h*(height_cap-w->cam_height);
      if(floor_y<y0)
        goto ceil2;
      for(idx3=0;idx3<AbsI64(height_cap-adj_height);idx3++) {
//.u8[0] is floor tile
        DrawWallSegment(w,segment,x,y0+h*idx3,w->wall_textures[w->world_mat[idx].u8[0]],h,dist,height_cap-1-idx3,idx,side);
      }
ceil2:      
      if(dist2<2.||dist<2.)
	goto ent;
      ceil=w->ceilmap[idx];
      adj_height=w->ceilmap2[idx];
      //Draw Ceil
      if(ceil!=I8_MAX&&ceil>w->cam_height) {
//.u8[1] is ceil tile
        if(use_dc=w->ceil_textures[w->world_mat[idx].u8[1]]) {
	  standing_at=ToI64(w->x)/GRID_SZ+ToI64(w->y)/GRID_SZ*w->world_width;
	  if(standing_at==idx) {
            ceily=ColorFloor(w,x,ceil,
              GR_HEIGHT/2-h2*(ceil-w->cam_height),
              0,
              use_dc,
	      TRUE
            );
	  } else
            ceily=MaxI64(ceily,ColorFloor(w,x,ceil,
              GR_HEIGHT/2-h2*(ceil-w->cam_height),
	      GR_HEIGHT/2-h*(ceil-w->cam_height),
              use_dc,
	      TRUE
            ));
	}
      } else if(ceil!=I8_MAX&&ceil<w->cam_height) {
          use_dc=w->floor_textures[w->world_mat[idx].u8[1]];
	  if(standing_at==idx&&use_dc&&0) {
	     ColorFloor(w,x,ceil+adj_height,
                GR_HEIGHT/2-h2*(adj_height+ceil-w->cam_height),
		0,
		use_dc
	        );
	  } else if(use_dc) {
	     ColorFloor(w,x,ceil+adj_height,
	        GR_HEIGHT/2-h*(adj_height+ceil-w->cam_height),
                GR_HEIGHT/2-h2*(adj_height+ceil-w->cam_height),
		use_dc
	        );
          }

      }
      if(ceil!=I8_MAX) {
//Find tallest adjacent ceiling
        adj_height=w->ceilmap2[idx];
        switch(side) {
         case 0:
	   xoff=-1;
	   break;
         case 1:
	   xoff=1;
	   break;
         case 2:
	   yoff=-1;
	   break;
         case 3:
	   yoff=1;
	   break;
        }
        tile2=xoff+yoff*w->world_width+idx;
        if(0<=tile2<w->world_width*w->world_height) {
	  other=w->ceilmap[tile2]+w->ceilmap2[tile2];
	  if(w->ceilmap[tile2]==ceil) {
            if(other>=ceil) {
	      if(other>=adj_height+ceil)
	        adj_height=0;
	      else
	        adj_height=(adj_height+ceil)-other;
	    }
	  }
        }
        y0=GR_HEIGHT/2-h*(ceil+w->ceilmap2[idx]-w->cam_height);
        for(idx3=0;idx3<adj_height;idx3++) {
//.u8[1] is ceil tile
          if(-GR_HEIGHT*2<=y0+h*idx3<=GR_HEIGHT*2)
            DrawWallSegment(w,segment,x,y0+h*idx3,w->wall_textures[w->world_mat[idx].u8[1]],h,dist,ceil+adj_height-idx3,idx,side);
        }
        last_ceil=ceil;
      }
      goto ent;
    }
fin:
    Free(tiles);
  }
  LBts(&mp_done,Gs->num);
}
U0 C3DWorldCastRays(C3DWorld *w) {
  I64 idx;
  lock mp_done=0;
  for(idx=mp_cnt-1;idx>=1;idx--) {
    JobQue(&MPCastCol,w,idx);
  }
  MPCastCol(w);
  for(idx=mp_cnt-1;idx>=1;idx--) {
    while(!Bt(&mp_done,idx))
      __Sleep(1);
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
Bool CanSee2DThing(C3DWorld *w,C3DThing *t) {
  Bool ret=TRUE;
  F64 dist=Sqrt(Sqr(t->x-w->x)+Sqr(t->y-w->y)),near,far,interp;
  F64 angle=Arg(t->x-w->x,t->y-w->y);
  I64 *ti=GetTilesInPath(w,angle,dist),idx;
  I64 at_tile=ToI64(w->x/GRID_SZ)+ToI64(w->y/GRID_SZ)*w->world_width;
  for(idx=0;ti[idx]!=-1;idx++) {
    if(ti[idx]==at_tile) {
    } else {
      FindRayWall(w,
	    Tan(angle),
	    Cos(angle),
	    Sin(angle),
	    NULL,
	    &near,
	    NULL,
	    I8_MIN,
	    ti[idx],
	    FALSE,
	    TRUE
      );
      FindRayWall(w,
	    Tan(angle),
	    Cos(angle),
	    Sin(angle),
	    NULL,
	    &far,
	    NULL,
	    I8_MIN,
	    ti[idx],
	    TRUE,//far sdie
	    TRUE
      );
      interp=Min((near+far)/2,dist)/dist*(t->z-w->cam_height)+w->cam_height;
      if(HeightImpossible(w,
	ti[idx]%w->world_width,
	ti[idx]/w->world_width,
	interp,
	TRUE)) {
         ret=FALSE;
         break;
      }
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
  F64 a_angle=Arg(a->x-w->x,a->y-w->y);
  F64 b_angle=Arg(b->x-w->x,b->y-w->y);
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
  left.x=cam.x+I16_MAX*Cos(w->fov/2+w->angle);
  left.y=cam.y+I16_MAX*Sin(w->fov/2+w->angle);
  right.x=cam.x+I16_MAX*Cos(-w->fov/2+w->angle);
  right.y=cam.y+I16_MAX*Sin(-w->fov/2+w->angle);
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
  if(in_view) return TRUE;
  if(Cos(a_angle-w->angle)<0&&Cos(b_angle-w->angle)<0)
    return FALSE;
  return TRUE;
//  return in_view||!IsLeftSide(&cam,&left,a)||!IsLeftSide(&cam,&left,b)
//	||IsLeftSide(&cam,&right,a)||IsLeftSide(&cam,&right,b);
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
  if(!ThingHasClass(t->from,"C3DThing"))
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
  if(cnt<1) {
    return;
  }
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
    if(ClipLineToCamera(w,&stp,&enp))
      Line3D(w,dc,&stp,&enp);
    last.x=links[idx]->x;
    last.y=links[idx]->y;
    last.z=links[idx]->z;
  }
}
U0 Draw2DThing(C3DWorld *w,C3DThing *thing) {
  if(thing->no_draw) goto fin;
  C3DThingTemplate *template=thing->template;
  if(!ThingHasClass(template,"C3DThingTemplate")) {
    return;
  }
  CDC *dc=w->to_dc;
  F64 x=thing->x-w->x,y=thing->y-w->y;
  F64 off=thing->angle-w->angle+pi,angle,diff,gap;
  F64 y0,h,width,x0,cx,cy,vis_h;
  I32 dist=Sqrt(Sqr(x)+Sqr(y));
  if(dist<2) return;
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
//ACos(.5) is about 60 degrees
  if(Cos(angle-w->angle)<.5)
    goto fin;
//https://permadi.com/1996/05/ray-casting-tutorial-8/
  dist*=Cos(angle-w->angle);
  if(dist<2.) goto fin;
//Draw Starting from bottom of wall
//
// The differnece between h an vis_h s vis_h is clamped to avoid massive sprites when up close
//
// I will use h for computing position,then vis_h for dimenisons of the drawn_sprite
//
  wall_height_ratio=(use_dc->height/ToF64(GR_HEIGHT));
  h=(DIST_SCALE/(5.+ToF64(dist)));
  vis_h=h*wall_height_ratio;
  y0=GR_HEIGHT/2-h*((wall_height_ratio+thing->z)-w->cam_height);
//I will now scale vis_h by 1.5 to look pretty,we will need to adjust y0 accordingly
  y0-=vis_h*1.5-vis_h;
  vis_h*=1.5;
  width=ToF64(vis_h)/use_dc->height*use_dc->width;
  angle=NormalizeAngle(angle);
  w->angle=NormalizeAngle(w->angle);
//Eeriler i scaled by 1.5,so do opositie
  x0=GR_WIDTH/2+Wrap(angle-w->angle)/((w->fov/GR_WIDTH))-width/1.5/2;
//clamp'ed x
  cx=ClampI64(x0,0,GR_WIDTH);
//ditto
  cy=ClampI64(y0,0,GR_HEIGHT);
  to_x=ClampI64(width+x0,0,GR_WIDTH-2);
  to_y=ClampI64(vis_h+y0,0,GR_HEIGHT-3);
  for(ix=ToI64(cx)&~1;cx-2<=ix<to_x;ix+=2) {
    if(!flip) {
      col=(ix-x0)/width*use_dc->width;
      src_ptr=y_line;
    } else {
      col=(width-(ix-x0)-2)/width*use_dc->width;
    }
    if(0>col||col>=use_dc->width)
     goto skip2;
    iy=ToI64(cy)&~1;
    dst=dc->body+ToI64(iy)*dc->width_internal+ToI64(ix);
    I32 *depth_dst=dc->depth_buf+ToI64(iy)*dc->width_internal+ToI64(ix);
    for(;cy-4<=iy<=to_y-3;iy+=3) {
      line=ToI64((iy-y0)/vis_h*use_dc->height);
      if(0<=line<use_dc->height-3) {
        dst=dc->body+ToI64(iy)*dc->width_internal+ToI64(ix);
        depth_dst=dc->depth_buf+ToI64(iy)*dc->width_internal+ToI64(ix);
	if(dist>*depth_dst) {
	  goto skip;
	}
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
  if(ThingHasClass(thing,"CZombie")) {
   DrawPissStream(w,thing(CZombie*)->piss_stream);
  }
}
U0 WallStainDel(CWallStain *s) {
  if(s->dc) AnimDCDel(s->dc);
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
  CDC *new=AnimDCNew(x2-x1+1,y2-y1+1);
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
CFrogThing *C3DThingMoveAtAngle(C3DThing *self,...) {
  CFrogThing *dist=argv[0];
  CFrogThing *angle=argv[1];
  Bool hit_wall=FALSE;
//
//
//Heres the deal,world update gets ran 10 fps,but physics is 30 fps
//I will "dumb" walk into a wall then set the momentum to "walk"
//
//
  F64 old_x=self->x;
  F64 old_y=self->y;
  hit_wall=C3DWorldMoveWithCollision(w,AsF64(angle),AsF64(dist),&self->x,&self->y,TRUE,self->z);
  self->x=old_x;
  self->y=old_y;
  self->momx2+=AsF64(dist)*Cos(AsF64(angle)); 
  self->momy2+=AsF64(dist)*Sin(AsF64(angle)); 
  return FrogNumNew(hit_wall);
}
AddMethod("C3DThing","move:atAngle:",&C3DThingMoveAtAngle);

CFrogThing *WorldManagerWidth(C3DWorldManager *self,...) {
  return FrogNumNew(w->world_width);
}
CFrogThing *WorldManagerHeight(C3DWorldManager *self,...) {
  return FrogNumNew(w->world_height);
}
AddMethod("C3DWorldManager","width",&WorldManagerWidth);
AddMethod("C3DWorldManager","height",&WorldManagerHeight);
CFrogThing *WorldManagerTileHeightAtXAtY(C3DWorldManager *self,...) {
  I64 x=AsF64(argv[0]);
  I64 y=AsF64(argv[1]);
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
  if(0<=x<w->world_width)
    if(0<=y<w->world_height) {
      return FrogNumNew(w->ceilmap[x+y*w->world_width]);
    }
  return FrogNumNew(I16_MAX);
}
AddMethod("C3DWorldManager","ceilHeightAtX:atY:",&WorldManagerCeilHeightAtXAtY);
CFrogThing *WorldManagerCeilRiseAtXAtY(C3DWorldManager *self,...) {
  I64 x=AsF64(argv[0]);
  I64 y=AsF64(argv[1]);
  if(0<=x<w->world_width)
    if(0<=y<w->world_height) {
      return FrogNumNew(w->ceilmap2[x+y*w->world_width]);
    }
  return FrogNumNew(I16_MAX);
}
AddMethod("C3DWorldManager","ceilRiseAtX:atY:",&WorldManagerCeilRiseAtXAtY);
CFrogThing *WorldManagerTileHeightAt(C3DWorldManager *self,...) {
  C2DPoint *p=argv[0];
  CFrogThing *ret=FrogNumNew(I16_MAX);
  if(0<=p->x<w->world_width)
    if(0<=p->y<w->world_height) {
      ret=FrogNumNew(w->heightmap[p->x+p->y*w->world_width]);
    }
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
	    force_tile,
	    FALSE,
	    TRUE //Allow ceilings
	    );
  w->x=oldx;
  w->y=oldy;
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
	    force_tile,
	    FALSE,
	    TRUE //Allow ceilings
	    );
  w->x=oldx;
  w->y=oldy;
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
	    ,
	    FALSE,
	    TRUE //Allow ceilings
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
  if(self->dc) AnimDCDel(self->dc);
  if(grl) {
    self->dc=AnimDCLoad(grl); 
  }
  Free(name),Free(grl); 
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
  self->gr_name=FrogStrNew(name);
  Free(name);
  return FROG_SMALL_NIL;
}
AddMethod("CHandItem","setGraphics:",&HandItemSetGr);
U0 HandItemDel(CHandItem *i) {
  if(i->gr) AnimDCDel(i->gr);
  Free(i);
}
CFrogThing *ThingCanSeeThing(C3DThing *self,...) {
  F64 old_x=w->x,old_y=w->y,old_z=w->cam_height;
  CFrogThing *ret;
  C3DThing *other=argv[0];
  if(other==FROG_SMALL_NIL) return FROG_SMALL_NIL;
  w->x=self->x;
  w->y=self->y;
  w->cam_height=self->z;
  ret=FrogNumNew(CanSee2DThing(w,other));
  w->x=old_x;
  w->y=old_y;
  w->cam_height=old_z;
  return ret;
}
AddMethod("C3DThing","canSeeThing:",&ThingCanSeeThing);


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
  DocClear;
#include "UI.HC"
LoadWorldFromFile(,"Untitled.WORLD");
I64 mp_thing_done=0;
U0 DrawDoor(CDoor *d) {
  CD3 points[4];
  F64 dist,h,y0,dist2,top,y1,h2;
  I64 segment;
  Bool in_view=FALSE;
  I64 xcords[4];
  I64 tile=d->y*w->world_width+d->x;
  I64 idx,minx=GR_WIDTH,maxx=0,idx2,side,ptr;
  points[0].x=d->x*GRID_SZ;
  points[0].y=d->y*GRID_SZ;
  points[1].x=(d->x+1)*GRID_SZ;
  points[1].y=d->y*GRID_SZ;
  points[2].x=(d->x+1)*GRID_SZ;
  points[2].y=(d->y+1)*GRID_SZ;
  points[3].x=d->x*GRID_SZ;
  points[3].y=(d->y+1)*GRID_SZ;
  in_view|=ClipLineToCamera(w,&points[0],&points[1]);
  in_view|=ClipLineToCamera(w,&points[2],&points[3]);
  if(!in_view)
    return;
  for(idx=0;idx!=4;idx++) {
//z isnt used
    PointToScrn(w,points[idx].x,points[idx].y,128,&points[idx]);
    maxx=MaxI64(points[idx].x,maxx);
    minx=MinI64(points[idx].x,minx);
  }
  minx=ClampI64(minx,0,GR_WIDTH-w->step_width);
  maxx=ClampI64(maxx,0,GR_WIDTH-w->step_width);
  while(minx<maxx) {
      if(-1==FindRayWall(w,
	    tan_lookup_table[minx],
	    cos_lookup_table[minx],
	    sin_lookup_table[minx],
	    &segment,
	    &dist,
	    &side,
	    I8_MIN,
	    tile
	    ))
	goto next;
      FindRayWall(w,
	    tan_lookup_table[minx],
	    cos_lookup_table[minx],
	    sin_lookup_table[minx],
	    NULL,
	    &dist2,
	    NULL,
	    I8_MIN,
	    tile,
	    TRUE
	    );
      if(d->percent>.03)
        top=d->height*d->percent+w->heightmap[tile];
      else
        top=d->height*.03+w->heightmap[tile];
      dist*=cos2_lookup_table[minx];
      h=DIST_SCALE/dist;
      y0=GR_HEIGHT/2-h*(top-w->cam_height);
      h2=DIST_SCALE/dist2;
      y1=GR_HEIGHT/2-h2*(top-w->cam_height);
//Horizon check
      if(top<w->cam_height)
        ColorFloor(w,minx,top,y0,y1,w->wall_textures[d->act_as_wall]);
      DrawWallSegment(w,segment,minx,y0,w->wall_textures[d->act_as_wall],h*d->percent*d->height,dist,w->heightmap[tile]-1+d->height,tile,side);
next:;
      minx+=w->step_width;
  }
}
U0 UpdateDrawBuffer() {
  WaitForJobsFinish; //MAke sure there world data is all ours all not belong to anyone else
  C3DWorldManager *man=FrogSymbol("world")->value;
  CDoor **doors;
  CPlayer *player=CallScript("getPlayer",man);
  CDC *hand_gr;
  I32 *odepth_buf;
  I64 tx,ty,c,f;
  CI64Set *s;
  C3DParticle *p,*head,*n;
  CShellCasing *shellc;
  CHandItem *hand=FrogSymbol("hand_item")->value;
  CDC *dc=w->to_dc;
  DCFill(dc,TRANSPARENT);
  DCDepthBufRst(dc);
  odepth_buf=dc->depth_buf;
  InitTables(w->angle,w->fov);
  C3DWorldCastRays(w);   
  mp_thing_done=0;
  CFrogThing ***body=w->_2d_things->body;
  I64 idx=w->_2d_things->cnt;
  while(--idx>=0)
    Draw2DThing(w,body[idx]);
  
  head=&w->particles;
  for(p=head->next;head!=p;p=n) {
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
    n=p->next;
    if(tS>1+p->born_at) {
      QueRem(p);
      Free(p);
      w->particle_cnt--;
    }
  }
  doors=man->doors->items->body;
  c=man->doors->items->cnt;
//Rely on wall commands to choose what part of door to draw
//Floors z-distance doesnt account for height
  while(--c>=0) {
    DrawDoor(doors[c]);
  }
  w->to_dc->depth_buf=NULL;

  
  Fs->user_data=0;
  if(ThingHasClass(player,"CPlayer")) {
    if(ThingHasClass(player->shell_casings,"CFrogArray")) {
      s=player->shell_casings->items;
      body=s->body;
      idx=s->cnt;
      while(--idx>=0) {
        shellc=body[idx];
	if(ThingHasClass(shellc,"CShellCasing")) {
	  if(shellc->dc)
	   AnimDCBlot(dc,shellc->x,shellc->y,shellc->dc);
	}
      }
   }
  } 

  if(ThingHasClass(hand,"CHandItem")) {
    hand->x=ms.pos.x;
    if(hand_gr=hand->gr) {
      c=AnimDCCnt(hand_gr);
      f=(tS-hand->anim_start_tS)/ANIM_DELAY;
      if(hand->anim_no_repeat) {
        if(f>=c)
	  f=c-1;
	else
          f%=c;
      } else 
        f%=c;
      GrBlot(dc,hand->x+hand->xoff-hand_gr->width/2,hand->y+hand->yoff-hand_gr->height/2,hand_gr+f);
    }
  }
fin:
  DrawUIRoot(Fs,dc);
  dc->depth_buf=odepth_buf;
}
U0 DrawIt(CTask *t,CDC *dc) {
  w->to_dc->flags|=DCF_NO_TRANSPARENTS;
  GrBlot(dc,0,0,w->to_dc);
}
U0 WalkAround(U8 *save_string=NULL) {
  I64 c,ch=0,sc=0,m1,m2,msg,jump=FALSE;
  I64 msx=GR_WIDTH/2,msy=GR_HEIGHT/2;
  F64 mouse_angle;
  F64 x=9*GRID_SZ,y=5*GRID_SZ;
  Bool up=FALSE,down=FALSE,right=FALSE,left=FALSE,cont=TRUE;
  CFrogSymbol *man=FrogSymbol("world");
  CShellCasing *shellc;
  C3DWorldManager *wm=man->value,*load_game;
  I64 every=0;
  if(save_string) {
     load_game=CallScript("restoreThing",FrogStrNew(save_string));
     if(ThingHasClass(load_game,"C3DWorldManager")) {
       man->value=load_game;
///Insherit old dictionaries
       load_game->thing_templates=wm->thing_templates;
       load_game->tile_templates=wm->tile_templates;
       wm=load_game;
       w->_2d_things=wm->things->items;
       w->_wall_stains=wm->wall_stains->items;
       w->_floor_stains=wm->floor_stains->items;
     }
  }
  CPlayer *player=CallScript("getPlayer",man->value);
  CUIElem *ui_root=FrogSymbol("ui_root")->value;
  WinMax;
  WinBorder;
  AutoComplete;
  Fs->draw_it=&DrawIt;
  w->x=x,w->y=y;
  w->cam_height=.8;
  w->angle=0;
  CFrogThing **body;
  I64 idx;
  try while (cont) {
     every++;
     if(every%3==0) QueCallScript("update",man->value);
     body=wm->doors->items->body;
     c=wm->doors->items->cnt;
     for(idx=0;idx<c;idx++)
       CallScript("update",body[idx]);
// Do physics after update
     c=w->_2d_things->cnt;
     body=w->_2d_things->body;
     for(idx=0;idx<c;idx++) {
       PhysicsOnThing(w,body[idx],wm);
       if(body[idx]==player) {
	  player->momx2=0;
	  player->momy2=0;
       }
       CallScript("animate",body[idx]);
     }
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
	        case CH_ESC:
	        case CH_SHIFT_ESC: {
		  //No jumping out of try block
		  //goto en;
		  cont=FALSE;
		  break;
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
      if(!player->main_inventory_active) {
        if (jump) {
           QueCallScript("jump",player);
           jump=FALSE;
        }
        if (up)
          C3DThingMoveAtAngle(player,
	      FrogNumNew(GRID_SZ/4),
	      FrogNumNew(player->angle));
        if (down)
          C3DThingMoveAtAngle(player,
	      FrogNumNew(-GRID_SZ/4),
	      FrogNumNew(player->angle));
        if (left) {
          C3DThingMoveAtAngle(player,
	      FrogNumNew(GRID_SZ/4),
	      FrogNumNew(player->angle-pi/2));
        }
        if (right)
          C3DThingMoveAtAngle(player,
	      FrogNumNew(GRID_SZ/4),
	      FrogNumNew(player->angle+pi/2));
        if(msx<SCRN_TURN_MARGIN) {
	  player->angle-=ToF64(SCRN_TURN_MARGIN-msx)/SCRN_TURN_MARGIN*SCRN_TURN_RATE;
        } else if(msx>GR_WIDTH-SCRN_TURN_MARGIN) {
	  player->angle+=ToF64(msx-(GR_WIDTH-SCRN_TURN_MARGIN))/SCRN_TURN_MARGIN*SCRN_TURN_RATE;
        }
        if (ms.lb&&20<msy<GR_HEIGHT-75) { // mouse input is best handled with ms, not ScanMsg
	  mouse_angle=(ms.pos.x-GR_WIDTH/2)*(w->fov/GR_WIDTH);
	  player->angle+=mouse_angle;
          QueCallScript("fire",FrogSymbol("hand_item")->value);
	  player->angle-=mouse_angle;
        }
      }
      wm->screen_x=msx;
      wm->screen_y=msy;
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
	    QueCallScript("update",shellc);
	  }
        }
     }
      QueCallScript("animate",FrogSymbol("hand_item")->value);
      UpdateDrawBuffer;
      ClearPlatformCache; //Clear the cache becuase of changeing doors
      Refresh;
      if(every&15==0) FrogGarbageCollect;
    } catch {PutExcept(TRUE);}
en:
  WaitForJobsFinish;
  CallScript("saveThing",wm);
  FlushMsgs;
  Fs->draw_it=NULL;
  Refresh;
/*  FrogNullifySymbols;
  FrogGarbageCollect;
  HeapWho(Fs);*/
}
if(FileFind("/STDebug.DD"))
  WalkAround(FileRead("/STDebug.DD"));
else
  WalkAround;
#endif
#endif        i               8      8   ßÿÿÿ   Ýÿÿÿ      	'   öÿÿÿ?   áÿÿÿ

'   ÷ÿÿÿ5   ÷ÿÿÿ
'   ÷ÿÿÿ(   ßÿÿÿ 