#include "AnimDC.HC"
#include "BlobFile.HC";
#include "SmallTalk/Load.HC"
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
   F64 fov,x,y,h,angle,step_width,step_width_y;
   I64 world_width;
   I64 world_height;
   I16 *world_mat; //0 is for EMPTY_SPACE
   I8 *heightmap;
   CDC *wall_textures[0x10000/2],*to_dc;
   CDC *floor_textures[0x10000/2];
   I64 mp_done,dc_lock;
   CQue _2d_thing_templates; 
   CI64Set *_2d_things;
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
U0 C3DWorldSetFov(C3DWorld *w,F64 fov=pi/4) {$IV,0$
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
  C2DThingTemplate **templates=CAlloc(0x10000*8),*template;
  C2DThing *thing;
  C3DWorldManager *man;
  C3DWorldSetFov(ret,fov);
  QueInit(&ret->particles);
  ret->step_width=4;  
  ret->step_width_y=4;
  ret->world_width=world->w;
  ret->world_height=world->h;
  ret->world_mat=MAlloc(2*world->h*world->w);
  ret->heightmap=MAlloc(world->h*world->w);
  xoff=GRID_SZ*world->startx;
  yoff=GRID_SZ*world->starty;
  QueInit(&ret->_2d_thing_templates);
  MemCpy(ret->world_mat,world+1,2*world->h*world->w);
  MemCpy(ret->heightmap,ToI64(world+1)+2*world->h*world->w,world->h*world->w);
  man=ConstructThing("C3DWorldManager","world_handle",ret);
  CallScript("init",man);
  ret->_2d_things=man->things->items;
  fptr=world(U8*)+world->textures_where.ptr;
  to=fptr+world->textures_where.len;
  while(fptr<to) {
    idx=fptr(CFileTexture*)->idx;
    tmp=BlobFileGetLump(blob_file,fptr(CFileTexture*)->blob_name);
    if(idx>0)
      ret->floor_textures[idx]=AnimDCLoad(tmp);
    else
      ret->floor_textures[-idx]=AnimDCLoad(tmp);
    Free(tmp);
    tmp=BlobFileGetLump(blob_file,fptr(CFileTexture*)->wall_blob_name);
    if(idx>0)
      ret->wall_textures[idx]=AnimDCLoad(tmp);
    else
      ret->wall_textures[-idx]=AnimDCLoad(tmp);
    Free(tmp);
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
	  thing->x=fptr(CFileThing*)->x*GRID_SZ+xoff;
	  thing->y=fptr(CFileThing*)->y*GRID_SZ+yoff;
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
    if(sin>0.) {
      if(dist) *dist=cy1-w->y;
      return cx1<=w->x<=cx2&&w->y<=cy1;
    }
    if(dist) *dist=w->y-cy2;
    return cx1<=w->x<=cx2&&w->y>=cy2;
  }
  if(sin==0.) {
    if(cos>0.) {
      if(dist) *dist=cx1-w->x;
      return cy1<=w->y<=cy2&&w->x<=cx1;
    }
    if(dist) *dist=w->x-cx2;
    return cy1<=w->y<=cy2&&w->x>=cx2;
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
    iy=force_tile/w->world_height;
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
    t1=(wall_x-w->x)/cos;
    t2=(wall_y-w->y)/sin;

    if(t1<t2) {
      x=t2*cos+w->x;
      y=wall_y;
      wall_x=x;
      if(side) *side=cos>0;
      if(segment) *segment=SegmentModulo(x,ix);
    } else{
      x=wall_x;
      y=t1*sin+w->y;
      wall_y=y;
      if(side) *side=2+(sin>0);
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
      case 0: //Left
	deflect_angle=pi;
	break;
      case 1: //Right
	deflect_angle=0;
	break;
      end:
        C3DWorldMoveWithCollision(w,deflect_angle,Abs(dist*Cos(angle)),x,y,FALSE,height);
	break;
      start:
      case 2://Top
	deflect_angle=2*pi-pi/2;
	break;
      case 3://Bottom
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
  return Clamp(per*(max-min)+min,min,max);
}
U0 DrawWallSegment(C3DWorld *w,I64 segment,I64 x,I64 start_y,CDC *texture,I64 height,I64 dist) {
  if(!texture||!height) return;
  U8 *dst=w->to_dc->body;
  I32 *depth_dst;
  I64 tmp,i,segment_y,width=w->to_dc->width_internal,anim_frame=ToI64(tS/ANIM_DELAY)%AnimDCCnt(texture);
  dst+=x+MaxI64(start_y,0)*width;
  if(w->to_dc->depth_buf)
    depth_dst=w->to_dc->depth_buf+x+MaxI64(start_y,0)*width;
  else
    depth_dst=NULL;

ent:
  for(i=0;i<=height;i+=4) {
    tmp=VisSkipTo(w,x,i+start_y,dist)-start_y;
    if(tmp) {
      i=tmp;
      dst=w->to_dc->body+(start_y+i)*width+x;
      if(w->to_dc->depth_buf)
	depth_dst=w->to_dc->depth_buf+(start_y+i)*width+x;
    }
    if(0<=i+start_y<GR_HEIGHT-4) {
      segment_y=height/(DIST_SCALE/ToF64(dist+1))*(i/ToF64(height))*texture->height;
      tmp=gr.to_8_colors[GrPeek0(
	    texture+anim_frame,
	    Lerp(segment/ToF64(GRID_SZ),0,texture->width-1),
	    segment_y%texture->height)];
      if(depth_dst[0]>dist) {
        dst(U32*)[0]=tmp;
        dst+=width;
        dst(U32*)[0]=tmp;
        dst+=width;
        dst(U32*)[0]=tmp;
        dst+=width;
        dst(U32*)[0]=tmp;
        dst+=width;

        if(depth_dst) {
	  depth_dst[0]=dist;
	  depth_dst[1]=dist;
	  depth_dst[2]=dist;
	  depth_dst[3]=dist;
	  depth_dst+=width;
	  depth_dst[0]=dist;
	  depth_dst[1]=dist;
	  depth_dst[2]=dist;
	  depth_dst[3]=dist;
	  depth_dst+=width;
	  depth_dst[0]=dist;
	  depth_dst[1]=dist;
	  depth_dst[2]=dist;
	  depth_dst[3]=dist;
	  depth_dst+=width;
	  depth_dst[0]=dist;
	  depth_dst[1]=dist;
	  depth_dst[2]=dist;
	  depth_dst[3]=dist;
	  depth_dst+=width;
        }
      } else  {
        depth_dst+=width*4;
	dst+=width*4;
      }
    } else if(i+start_y>=w->to_dc->height-4)
      break;
  }
}
I64 ColorFloor(C3DWorld *w,I64 view_x,I64 floor_height,I64 sy,I64 ey,CDC *texture) {
  CDC *dc=w->to_dc;
  F64 angley=0;
  F64 step;
  F64 dist;
  I64 y,fx,fy,anim_frame=ToI64(tS/ANIM_DELAY),idx,which;
  U64 colors,width=dc->width_internal,cnt;
  U8 *dst;
  I32 *db_z;
  U64 idist;
  ey=ClampI64(ey,0,w->to_dc->height-4);
  sy=ClampI64(sy,0,w->to_dc->height-4);
  for(y=sy;y<ey;y+=w->step_width_y) {
    if(y-GR_HEIGHT/2==0)
      dist=I16_MAX;
    else {
      dist=DIST_SCALE/((GR_HEIGHT/2-y)/(w->cam_height-floor_height+.001));
    }
    dist/=cos2_lookup_table[view_x];

    fx=w->x+cos_lookup_table[view_x]*dist;
    fy=w->y+sin_lookup_table[view_x]*dist;
      if(texture) {
        colors=gr.to_8_colors[GrPeek0(
	      texture+anim_frame%AnimDCCnt(texture),
	      (fx&(GRID_SZ-1))/ToF64(GRID_SZ)*texture->width,
	      (fy&(GRID_SZ-1))/ToF64(GRID_SZ)*texture->height)];
        if(0<=y<dc->height) {
	  dst=dc->body+(dc->height-y-4)*width+view_x;
	  db_z=dc->depth_buf+(dc->height-y-4)*width+view_x;
	  if(dist<*db_z) {
	    idist=dist;
	    //Make 64bit pair
	    idist=(idist&0xffFFffFF)|idist<<32;
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
	  }
        }
      }
    }
  return y;
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
U0 MPCastCol(C3DWorld *w) {
  F64 angle=w->angle-w->fov/2;
  I64 wall_segment_start,wall_segment_end;
  F64 dist,h,y,y2,dist2,h2;
  F64 s_angle1,s_angle2;
  I64 segment=0,idx,idx2,ptr,x=0,cap,side,side2,segment2,x0,y0,old_d,idx3,xoff,yoff;
  CBlockedView *block_view;
  I64 height_cap,adj_height,last_height,floor_y;
  I64 *tiles;
  idx=GR_WIDTH/mp_cnt*Gs->num;
  cap=GR_WIDTH/mp_cnt*(Gs->num+1);
  angle+=(w->fov/GR_WIDTH)*w->step_width*idx/w->step_width;
  for(x=idx;x<cap;angle+=(w->fov/GR_WIDTH)*w->step_width,x+=w->step_width) {
    idx2=0;
    dist=0;
    floor_y=0;
    last_height=I64_MIN;
    tiles=GetTilesInPath(w,angle,I16_MAX);
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
      idx2++;
//https://permadi.com/1996/05/ray-casting-tutorial-8/
      dist*=cos2_lookup_table[x];
      h=DIST_SCALE/dist;
//Color the floor tile
      if(height_cap<=w->cam_height) {
        FindRayWall(w,
	      tan_lookup_table[x],
	      cos_lookup_table[x],
	      sin_lookup_table[x],
	      &segment,
	      &dist2,
	      &side,
	      I8_MIN,
	      idx,
	      TRUE //Far side of tile
	      );
        dist2*=cos2_lookup_table[x];
        h2=DIST_SCALE/(dist2+1);
        y0=GR_HEIGHT-(GR_HEIGHT/2-h*(height_cap-w->cam_height));
        if(dist>2.&&dist2>2.) {
	  if(w->floor_textures[w->world_mat[idx]])
	     floor_y=ColorFloor(w,x,height_cap,
	        Max(y0,floor_y),
	        GR_HEIGHT-(GR_HEIGHT/2-h2*(height_cap-w->cam_height)),
	        w->floor_textures[w->world_mat[idx]]
	        );
	  else
	     floor_y=ColorFloor(w,x,height_cap,
	        Max(y0,floor_y),
	        GR_HEIGHT-(GR_HEIGHT/2-h2*(height_cap-w->cam_height)),
	        w->wall_textures[w->world_mat[idx]]
	        );
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
        goto ent;
      last_height=height_cap;
      if(dist<=2.)
        goto ent;
      if(adj_height>=height_cap)
        goto ent;
      y=GR_HEIGHT/2;
      y0=GR_HEIGHT/2-h*(height_cap-w->cam_height);

      for(idx3=w->step_width;--idx3>=0;) {
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
      for(idx3=0;idx3<AbsI64(height_cap-adj_height);idx3++)
        DrawWallSegment(w,segment,x,y0+h*idx3,w->wall_textures[w->world_mat[idx]],h,dist);
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
U0 LoadMapFromSprite(C3DWorld *world,U8 *sprite,I64 px_width=1) {
  CDC*map;
  I64 x1,y1,x2,y2,x,y,w,h;
  SpriteExtents(sprite,&x1,&x2,&y1,&y2);
  map=Sprite2DC(sprite);
  w=(x2-x1+1)/px_width;
  h=(y2-y1+1)/px_width;
  world->x=(w/2)*GRID_SZ;
  world->y=(h/2)*GRID_SZ;
  Free(world->world_mat);
  world->world_height=h,world->world_width=w;
  world->world_mat=CAlloc(w*h);
  for(x=0;x!=w;x++) {
    for(y=0;y!=h;y++) {
      world->world_mat[x+y*w]=
	GrPeek(map,x*px_width,y*px_width);
    } 
  }
  DCDel(map);
}
U0 LoadTextureFromSprite(C3DWorld *world,I64 color,U8 *sprite) {
  I64 x1,y1,x2,y2,w,h,x,y;
  F64 interp_x,interp_y;
  CDC *raw,*texture=DCNew(GRID_SZ,GRID_SZ);
  SpriteExtents(sprite,&x1,&x2,&y1,&y2);
  raw=Sprite2DC(sprite);
  w=(x2-x1+1);
  h=(y2-y1+1);
  for(x=0;x!=GRID_SZ;x++) {
    interp_x=ToF64(w)/GRID_SZ*x;
    for(y=0;y!=GRID_SZ;y++) {
      interp_y=ToF64(h)/GRID_SZ*y;
      texture->color=GrPeek(raw,interp_x,interp_y);
      GrPlot(texture,x,y);
    }
  }
  DCDel(raw);
  if(world->wall_textures[color])
    DCDel(world->wall_textures[color]);
  world->wall_textures[color]=texture;
}
U0 LoadFloorFromSprite(C3DWorld *world,I64 color,U8 *sprite) {
  I64 x1,y1,x2,y2,w,h,x,y;
  F64 interp_x,interp_y;
  CDC *raw,*texture=DCNew(GRID_SZ,GRID_SZ);
  SpriteExtents(sprite,&x1,&x2,&y1,&y2);
  raw=Sprite2DC(sprite);
  w=(x2-x1+1);
  h=(y2-y1+1);
  for(x=0;x!=GRID_SZ;x++) {
    interp_x=ToF64(w)/GRID_SZ*x;
    for(y=0;y!=GRID_SZ;y++) {
      interp_y=ToF64(h)/GRID_SZ*y;
      texture->color=GrPeek(raw,interp_x,interp_y);
      GrPlot(texture,x,y);
    }
  }
  DCDel(raw);
  if(world->floor_textures[color])
    DCDel(world->floor_textures[color]);
  world->floor_textures[color]=texture;
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
  y0=GR_HEIGHT/2-h*((1+p->z)-w->cam_height);
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
U0 Draw2DThing(C3DWorld *w,C2DThing *thing) {
  if(thing->no_draw) return;
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
  to_x=ClampI64(width+x0,0,GR_WIDTH-1);
  to_y=ClampI64(vis_h+y0,0,GR_HEIGHT-1);
  for(x=ToI64(cx)&~1;cx-4<=x<to_x;x+=2) {
    if(!flip) {
      col=(x-x0)/width*use_dc->width;
      src_ptr=y_line;
    } else {
      col=(width-(x-x0)-1)/width*use_dc->width;
    }
    if(0>col||col>=use_dc->width)
     goto skip2;
    for(y=ToI64(cy)&~1;cy-4<=y<to_y;y+=3) {
      line=ToI64((y-y0)/vis_h*use_dc->height);
      if(0<=line<use_dc->height) {
        y_line=use_dc->body+line*use_dc->width_internal;
        src_ptr=y_line+col;
        if(*src_ptr==TRANSPARENT) {
	  while(line<use_dc->height) {
	    if(*src_ptr!=TRANSPARENT)
	     break;
	    src_ptr+=use_dc->width_internal;
	    line++;
	  }
	  y=MaxI64(Lerp(ToF64(line)/use_dc->height,cy,to_y)-3,y);
	  goto skip;
	}
        dst=dc->body+ToI64(y)*dc->width_internal+ToI64(x);
        I32 *depth_dst=dc->depth_buf;
        if(depth_dst) {
	  depth_dst+=ToI64(y)*dc->width_internal+ToI64(x);
	  if(dist>*depth_dst) {
	    y=VisSkipTo(w,x,y,dist);
	    goto skip;
	  }
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
}
C3DWorld *w;
//
// SmallTalk Section
//
CFrogThing *WorldManagerNewParticle(C3DWorldManager *man,...) {
  F64 x=AsF64(argv[0]);
  F64 y=AsF64(argv[1]);
  F64 z=AsF64(argv[2]);
  F64 spread=AsF64(argv[3]);
  F64 color=AsF64(argv[4]);
  NewParticle(w,color,16,x,y,z,spread*(Rand-.5),spread*(Rand-.5),man->gravity);
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
  I64 tx,ty,c;
  C3DParticle *p,*head,*n;
  CHandItem *hand=FrogSymbol("hand_item")->value;
  dc=DCAlias(dc,t);
  w->to_dc=dc;
  DCDepthBufAlloc(dc);
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
  Free(w->to_dc->depth_buf);
  w->to_dc->depth_buf=NULL;
  if(ThingHasClass(hand,"CHandItem")) {
    hand->x=ms.pos.x;
    if(hand_gr=hand->gr) {
     GrBlot(dc,hand->x+hand->xoff-hand_gr->width/2,hand->y+hand->yoff-hand_gr->height/2,hand_gr);
    }
  }
  DrawUIRoot(t,dc);
  DCDel(dc);
}
U0 WalkAround() {
  I64 c,ch=0,sc=0,m1,m2,msg,jump=FALSE;
  I64 msx=GR_WIDTH/2,msy=GR_HEIGHT/2;
  F64 mouse_angle;
  F64 x=9*GRID_SZ,y=5*GRID_SZ;
  Bool up=FALSE,down=FALSE,right=FALSE,left=FALSE,cont=TRUE;
  CFrogSymbol *man=FrogSymbol("world");
  C2DThing *player=CallScript("getPlayer",man->value);
  CUIElem *ui_root=FrogSymbol("ui_root")->value;
  WinMax;
  WinBorder;
  Fs->draw_it=&DrawIt;
  w->x=x,w->y=y;
  w->cam_height=.8;
  w->angle=0;
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
      w->x=player->x;
      w->y=player->y;
      w->angle=player->angle+.001;
      w->cam_height=player->z+.6;
      w->angle%=2*pi;
      if(w->angle<0)
        w->angle+=2*pi;
      Refresh;
      FrogGarbageCollect;
    } catch PutExcept;
en:
  FlushMsgs;
  Refresh;
  Fs->draw_it=NULL;
}
WalkAround;
//Uf("Draw2DThing");
#endif
#endif        i               8      8   ßÿÿÿ   Ýÿÿÿ      	'   öÿÿÿ?   áÿÿÿ

'   ÷ÿÿÿ5   ÷ÿÿÿ
'   ÷ÿÿÿ(   ßÿÿÿ 