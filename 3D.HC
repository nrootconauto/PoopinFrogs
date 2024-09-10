#include "AnimDC.HC"
#include "BlobFile.HC"
#include "SmallTalk/Load.HC"
#include "Intersect.HC"
#include "QuestEditor.HC";
#include "PathFinder.HC";
#define TEST_3D
#ifndef ENGINE_3D
#include "SSE.HC";
#define VIEW_DIST 32
#define FOG0_DIST 8
#define FOG1_DIST 16
#define FOG2_DIST 20
U64 fog0_table[0x10];
U64 fog1_table[0x10];
U64 fog2_table[0x10];
U0 ErectFogTable(U64 *table,I64 fog_color,F64 ratio) {
  CBGR48 palette[COLORS_NUM];
  I64 idx,which;
  F64 r,g,b,dist,best_dist;
  F64 r2,g2,b2;
  U16 best_color,dither;
  GrPaletteGet(palette);
  for(idx=0;idx!=COLORS_NUM;idx++) {
    r=palette[idx].r*ratio+palette[fog_color].r*(1.-ratio);
    g=palette[idx].g*ratio+palette[fog_color].g*(1.-ratio);
    b=palette[idx].b*ratio+palette[fog_color].b*(1.-ratio);
    best_dist=1e100;
    for(dither=0;dither!=0xff;dither++) {
      r2=(palette[dither&0xf].r+palette[dither>>4].r)/2.;
      g2=(palette[dither&0xf].g+palette[dither>>4].g)/2.;
      b2=(palette[dither&0xf].b+palette[dither>>4].b)/2.;
      dist=Sqrt(Sqr(r-r2)+Sqr(g-g2)+Sqr(b-b2));
      if(dist<best_dist) {
	best_color=dither;
	best_dist=dist;
      }
    }
    table[idx].u8[0]=best_color&0xf;
    table[idx].u8[2]=best_color&0xf;
    table[idx].u8[4]=best_color&0xf;
    table[idx].u8[6]=best_color&0xf;

    table[idx].u8[1]=best_color>>4;
    table[idx].u8[3]=best_color>>4;
    table[idx].u8[5]=best_color>>4;
    table[idx].u8[7]=best_color>>4;
  }
}

ErectFogTable(fog0_table,BLACK,.75);
ErectFogTable(fog1_table,BLACK,.5);
ErectFogTable(fog2_table,BLACK,.25);
U0 FrogImgBlank(CFrogImg *img) {
  img->dc=DCNew(1,1,frog_mem_task);
  img->name=FrogStrNew("");
}
U0 FrogImgSetGraphics(CFrogImg *img,...) {
  U8 *lunk=AsString(argv[0]),*data,*symbol_name;
  if(img->dc)
    AnimDCDel(img->dc);
  img->dc=AnimDCNew(1,1,frog_mem_task);
  if(lunk) {
    if(data=BlobFileGetLump(,lunk)) {
      AnimDCDel(img->dc);
      img->dc=AnimDCLoad(data,,frog_mem_task);
      img->name=FrogStrNew(lunk);
      Free(data);
    }
    Free(lunk);
  }
  return FROG_SMALL_NIL;
}
AddMethod("CFrogImg","setGraphics:",&FrogImgSetGraphics);
#include "TextureEditor";
CFrogImg *FrogImgNewFromEditor(CFrogImg *img,...) {
  U8 *lump;
  lump=TextureEdit(dft_blob_path);
  CFrogImg *ret=FROG_SMALL_NIL;
  if(lump) {
    ret=CallScript("get:",img,FrogStrNew(lump)); //Get an existing name/replace
    CallScript("setGraphics:",ret,FrogStrNew(lump));
    Free(lump);
  }
  return ret;
}
AddClassMethod("CFrogImg","newFromEditor",&FrogImgNewFromEditor);

U0 FrogImgDel(CFrogImg *img) {
  AnimDCDel(img->dc);
  Free(img);
}

CFrogStr *FrogImgToString(CFrogImg *img,...) {
  CFrogStr *s=ConstructThing("CFrogStr");
  I64 len;
  U8 *a=AnimDCSave(img->dc,&len);
  U8SetAddBytes(s->items,a,len);
  Free(a);
  return s;
}
//AddClassMethod("CFrogImg","asString",&FrogImgToString);
CFrogStr *FrogImgFromString(CFrogImg *img,...) {
  CFrogStr *s=AsString(argv[0]);
  CDC *d=NULL;
  if(s) {
    d=AnimDCLoad(s->items->body,,frog_mem_task);
    Free(s);
    AnimDCDel(img->dc);
    img->dc=d;
  }
  return FROG_SMALL_NIL;
}
//AddClassMethod("CFrogImg","setGraphicsFromString:",&FrogImgFromString);


U64 Fog(I64 color,I64 dist) {
  dist>>=7; //GRID_SZ is 128(7 bits)
  if(dist<=FOG0_DIST)
    return gr.to_8_colors[color];
  if(dist<=FOG1_DIST)
    return fog0_table[color];
  if(dist<=FOG2_DIST)
    return fog1_table[color];
  return fog2_table[color];
}

Bool IsLiquidTile(I64 t) {
  switch(t) {
    case 6: //water
    case 10: //lava
      return TRUE;
  }
  return FALSE;
}

F64 Frog_tS() {
  return tS+frog_time_offset;
}
extern I64 *GetTilesInPath(U8 *w,F64 angle,F64 dist);
#define ENGINE_3D 1
#define SCRN_TURN_MARGIN 100
#define SCRN_TURN_RATE (pi/30./7)
//This will delegate calls to other cores
class CCSPair {
  U8 *name;
  CFrogThing *thing;
  CHashTable *ht;
};
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
  U8 chat_bot_name[32];
  U8 drop_item_name[32];
  U8 activate_tag[32];
  U8 pad[32];
};
#define DOORF_SMALL_KEY 1
#define DOORF_BIG_KEY 2
#define DOORF_TO_CEILING 4
#define DOORF_SIDE_DOOR 8
class CFileDoor {
  I64 x,y,act_as_wall;
  F64 height;
  I32 flags;
  I32 tag;
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

I64 class CWallCommand {
  I16 start,end;
  I32 dist;
};

#define GRID_SZ 128
#define THING_RADIUS (GRID_SZ/3)
#define THING_HEIGHT 1.
#define DIST_SCALE (GR_HEIGHT*GRID_SZ)
#define EMPTY_SPACE 0
class C3DWorld {
   F64 fov,x,y,h,angle;
   F64 angle2;
   I64 step_width,step_width_y;
   I64 world_width;
   I64 world_height;
   I8 *world_blocks; //x*y*256
   I8 *heightmap,*ceilmap,*ceilmap2;
   CDC *wall_textures[0x10000/2],*to_dc;
   CDC *floor_textures[0x10000/2];
   CDC *floor_textures1616[0x10000/2];
   CDC *ceil_textures[0x10000/2];
   C3DThingTemplate *thing_templates[0x10000];
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
   CD3 to_point[GR_WIDTH/4][GR_HEIGHT/4];
   CI64Set *things_around_camera[VIEW_DIST*2][VIEW_DIST*2];
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
  p->born_at=Frog_tS;
  QueIns(p,w->particles.last);
  w->particle_cnt++;
}
#define THINGF_FACE_FORWARD 1
U0 C3DWorldSetFov(C3DWorld *w,F64 fov=pi/2) {
  w->fov=fov;
}

#define BLOB_THINGS_ROOT "Level/Things"
#define BLOB_TILES_ROOT "Level/Tiles"

CFrogThing *ThingTemplateSave(C3DThingTemplate *t,...) {
  CFileThingTemplate f_template;
  U8 *name,*name2=NULL;
  if(ThingHasClass(t,"C3DThingTemplate")) {
    MemSet(&f_template,0,sizeof CFileThingTemplate);
    if(name=AsString(t->name)){
      name2=MStrPrint(BLOB_THINGS_ROOT"/%s",name);
      StrCpy(f_template.name,name);
      Free(name);
    }
    if(ThingHasClass(t->front,"CFrogImg"))
       if(name=AsString(t->front->name)){
        StrCpy(f_template.blob_front_name,name);
        Free(name);
      }
    if(ThingHasClass(t->back,"CFrogImg"))
      if(name=AsString(t->back->name)){
        StrCpy(f_template.blob_back_name,name);
        Free(name);
      }
    if(ThingHasClass(t->side,"CFrogImg"))
      if(name=AsString(t->side->name)){
        StrCpy(f_template.blob_side_name,name);
        Free(name);
      }
    if(name2) BlobFileAddLump(,name2,&f_template,sizeof(CFileThingTemplate));
    Free(name2);
  }
  return FROG_SMALL_NIL;
}
AddMethod("C3DThingTemplate","save",&ThingTemplateSave);


CFrogThing *TileTemplateSave(CTileTemplate *t,...) {
  CFileTexture f_template;
  U8 *name;
  if(ThingHasClass(t,"CTileTemplate")) {
    MemSet(&f_template,0,sizeof CFileTexture);
    f_template.idx=t->tile_idx;
    if(ThingHasClass(t->floor_texture,"CFrogImg"))
      if(name=AsString(t->floor_texture->name)){
        StrCpy(f_template.blob_name,name);
        Free(name);
      }
    if(ThingHasClass(t->wall_texture,"CFrogImg"))
      if(name=AsString(t->wall_texture->name)){
        StrCpy(f_template.wall_blob_name,name);
        Free(name);
      }
    if(ThingHasClass(t->ceil_texture,"CFrogImg"))
      if(name=AsString(t->ceil_texture->name)){
        StrCpy(f_template.ceil_blob_name,name);
        Free(name);
      }
    name=MStrPrint(BLOB_TILES_ROOT"/%d",t->tile_idx);
    BlobFileAddLump(,name,&f_template,sizeof(CFileTexture));
    Free(name);
  }
  return FROG_SMALL_NIL;
}
AddMethod("CTileTemplate","save",&TileTemplateSave);
C3DWorld *InitWorld(U8 *blob_file="ASS",F64 fov=pi/2) {
  C3DWorld *ret=CAlloc(sizeof(C3DWorld));
  F64 xoff,yoff;
  U8 *tmp;
  I64 idx,tile,stop_at;
  CDC *unscaled;
  U16 *world_mat;
  C3DThingTemplate **templates=ret->thing_templates,*template;
  C3DThing *thing;
  C3DWorldManager *man;
  C3DWorldSetFov(ret,fov);
  CTileTemplate *tile_template;
  CDoor *door;
  QueInit(&ret->particles);
  ret->step_width=4; 
  ret->step_width_y=4;
  ret->world_width=100;
  ret->world_height=100;
  ret->world_blocks=CAlloc(ret->world_width*ret->world_height*256);
  w=ret;
  QueInit(&ret->_2d_thing_templates);

  man=ConstructThing("C3DWorldManager","world_handle",ret);
  CallScript("init",man);
  ret->_wall_stains=man->wall_stains->items;
  ret->_floor_stains=man->floor_stains->items;
  ret->_2d_things=man->things->items;

  CBlobFileHeader *bf_data=GetBlobFileData(blob_file); //Dont Free
  CLumpHeader *bf_lump=bf_data->lump_table;
  CFileThingTemplate *f_template;
  idx=bf_data->lump_cnt;
  while(--idx>=0) {
    if(!StrNCmp(bf_lump->name,BLOB_THINGS_ROOT,StrLen(BLOB_THINGS_ROOT))) {
      f_template=bf_data(U8*)+bf_lump->offset;
      tile=f_template->idx;
      if(I16_MIN<=tile<=I16_MAX) {
        template=ConstructThing("C3DThingTemplate");
        templates[f_template->idx-I16_MIN]=template;
        CallScript("setFront:",template,FrogStrNew(f_template->blob_front_name));
        CallScript("setBack:",template,FrogStrNew(f_template->blob_back_name));
        CallScript("setSide:",template,FrogStrNew(f_template->blob_side_name));
        CallScript("addThingTemplate:withName:",man,template,FrogStrNew(f_template->name));
      }
    }
    bf_lump++;
  }
  CFileTexture *ftxtr;
  bf_lump=bf_data->lump_table;
  idx=bf_data->lump_cnt;
  while(--idx>=0) {
    if(!StrNCmp(bf_lump->name,BLOB_TILES_ROOT,StrLen(BLOB_TILES_ROOT))) {
      ftxtr=bf_data(U8*)+bf_lump->offset;
      tile=AbsI64(ftxtr->idx);
      if(0<=tile<U8_MAX) {
        tile_template=ConstructThing("CTileTemplate");
	tile_template->tile_idx=tile;
        CallScript("setWall:",tile_template,FrogStrNew(ftxtr->wall_blob_name));
        CallScript("setFloor:",tile_template,FrogStrNew(ftxtr->blob_name));
        CallScript("setCeil:",tile_template,FrogStrNew(ftxtr->ceil_blob_name));

        if(ThingHasClass(tile_template->wall_texture,"CFrogImg")) {
	  ret->wall_textures[tile]=ScaleDC(tile_template->wall_texture->dc,GRID_SZ,GRID_SZ);
        }
        if(ThingHasClass(tile_template->floor_texture,"CFrogImg")) {
	  ret->floor_textures[tile]=ScaleDC(tile_template->floor_texture->dc,GRID_SZ,GRID_SZ);
        }
        if(ThingHasClass(tile_template->ceil_texture,"CFrogImg")) {
	  ret->ceil_textures[tile]=ScaleDC(tile_template->ceil_texture->dc,GRID_SZ,GRID_SZ);
        }
        CallScript("addTileTemplate:",man,tile_template);
      }
    }
    bf_lump++;
  }
  return ret;
}


I64 SegmentModulo(F64 f,I64 i) {
  I64 off=f+i*GRID_SZ;
  if(off>0) return off%GRID_SZ;
  if(off<0) return (GRID_SZ-off)%GRID_SZ;
  return 0;
}
I64 PassesThoughBlock(C3DWorld *w,F64 slope,I64 x,I64 y,F64 *dist,F64 cos,F64 sin,Bool far_side=FALSE) {
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
        tmp=Sqr(cx1*GRID_SZ)+Sqr(tmp*GRID_SZ);
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
        tmp=Sqr(cx2*GRID_SZ)+Sqr(tmp*GRID_SZ);
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
        tmp=Sqr(cy1*GRID_SZ)+Sqr(tmp*GRID_SZ);
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
        tmp=Sqr(cy2*GRID_SZ)+Sqr(tmp*GRID_SZ);
        smallest=Min(smallest,tmp);
        biggest=Max(biggest,tmp);
      }
      found=TRUE;
    }
  }
  if(dist) {
    if(!far_side)
      *dist=Sqrt(smallest);
    else
      *dist=Sqrt(biggest);
  }
  return found;
}
I64 BlockAtXYZ(I64 x,I64 y,I64 z) {
  I64 tile=x+y*w->world_width;
  if(0<=tile<w->world_height*w->world_width) {
    if(I8_MIN<=z<=I8_MAX) {
      return w->world_blocks[tile*256+z-I8_MIN];
    }
  }
  return -1;
}

Bool HeightImpossible(C3DWorld *w,I64 ix,I64 iy,F64 above,Bool allow_ceil,F64 tallness=.1,F64 wiggle_room=0) {
  I64 iz=Floor(above);
  I64 c,idx2;
  F64 h;
  if(BlockAtXYZ(ix,iy,iz)) {
     return TRUE;
  }
  for(idx2=0;idx2<tallness;idx2++) {
    idx2++;
    if(BlockAtXYZ(ix,iy,iz+idx2))
      return TRUE;
  }
  return FALSE;
}

I64 FindRayWall(C3DWorld *w,F64 slope,F64 cos,F64 sin,I64 *segment=NULL,F64 *dist=NULL,I64 *side=NULL,F64 above=I8_MIN,I64 tix,I64 tiy,Bool far_side=FALSE,Bool allow_ceil=FALSE) {
  F64 x=w->x;
  F64 y=w->y;
  Bool found_hit=FALSE;
  I64 ix=x/GRID_SZ,iy=y/GRID_SZ,iy2,seg,ix2;
  F64 smallest=1e100;
  F64 hit_x=-1,hit_y=-12345,dist2=VIEW_DIST*GRID_SZ,check_dist=0,t1,t2,wall_x,wall_y,res_dist;
  I64 sign_c=Sign(cos),sign_s=Sign(sin);
  static F64 step=GRID_SZ-1;
  if(dist) *dist=-1;
  ix=tix;
  iy=tiy;
  if(!PassesThoughBlock(w,slope,ix,iy,&res_dist,cos,sin,far_side)) {
    if(dist) *dist=res_dist;
    goto undef;
  }
  smallest=res_dist;
  check_dist=res_dist;
  ix2=ix;
  iy2=iy;
  goto final;
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
  if(Max(self->z,who->z)
     <=Min(self->z+THING_HEIGHT,who->z+THING_HEIGHT))
      if(radius>=x*x+y*y)
       return FrogNumNew(1);
  return FrogNumNew(0);
} 
AddMethod("C3DThing","hitsThing:",&BumpsIntoThing);
CFrogNum *C3DThingPathFindWalkTowardsThing(C3DThing *self,...) {
  CPFPoint pt;
  C3DThing *thing=argv[0];
  if(!ThingHasClass(thing,"C3DThing")) return FROG_SMALL_NIL;
  CI64Set *path=PathFinder(self->x/128,self->y/128,Floor(self->z),thing->x/128,thing->y/128,Floor(thing->z),&BlockAtXYZ,AsF64(argv[1]));
  if(path->cnt<2) {
    I64SetDel(path);
    return FrogNumNew(Arg(thing->x-self->x,thing->y-self->y));
  }
//TODO account for large same direction
  pt=path->body[1];
  I64SetDel(path);
  return FrogNumNew(Arg(pt.x+.5-self->x/128,pt.y+.5-self->y/128));
}
AddMethod("C3DThing","pathFinderAngleTowardsThing:withJump:",&C3DThingPathFindWalkTowardsThing);
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
	  if(HeightImpossible(w,x+xoff,y+yoff,height,TRUE,tallness)) {
//.2 for stepping over partly open doors
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
  F64 h,delta;
  I64 cnt=0,tile,best,ch,cr;
  F64 dir=Sign(dist);
  F64 oz=z;
//Wut
  if(dir==0) return FALSE;
  for(cnt=0;Abs(dist)>1/256.;cnt++) {
     if(dir<0)
       delta=Max(dist,-1);
     else
       delta=Min(dist,1);
     dist-=delta;
     if(HeightImpossible(w,x/128,y/128,z+delta,TRUE,tallness)) {
       hit=TRUE;
       goto fix;
     }
     z+=delta;
  }
fix:;
  while(HeightImpossible(w,x/GRID_SZ,y/GRID_SZ,z,TRUE,tallness)) {
    hit=TRUE;
    z-=dir/128.;
    if(dir>0&&z<oz) {
      z=oz;
      break;
    } if(dir<0&&z>oz) {
      z=oz;
      break;
    }
  }
  if(hit)
    if(Abs(z-Floor(z))<=2*dir/128.)
      z=Floor(z);
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
    ret=TRUE;
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

Bool IsOnWaterTile(C3DThing *t) {
  return 5==BlockAtXYZ(t->x/GRID_SZ,t->y/GRID_SZ,Floor(t->z)-1);
}
Bool IsOnLavaTile(C3DThing *t) {
  return 10==BlockAtXYZ(t->x/GRID_SZ,t->y/GRID_SZ,Floor(t->z)-1);
}
CFrogNum *WorldManagerRemoveFromGrid(C3DWorldManager *wm,...) {
  C3DThing *t=argv[0];
  if(!ThingHasClass(t,"C3DThing")) return FROG_SMALL_NIL;
  CFrogArray *arr=wm->grid;
  I64 atx=t->x/GRID_SZ/16.;
  I64 aty=t->y/GRID_SZ/16.;
  if(atx<0||aty<0) return FROG_SMALL_NIL;
  if(atx>=w->world_width/16+1) return FROG_SMALL_NIL;
  if(aty>=w->world_height/16+1) return FROG_SMALL_NIL;
  arr=arr->items->body[atx];
  arr=arr->items->body[aty];
  if(I64SetHas(arr->items,t)) {
    I64SetRem(arr->items,t);
  } else {
    for(atx=0;atx<w->world_width/16+1;atx++) {
      for(aty=0;aty<w->world_height/16+1;aty++) {
        arr=wm->grid;
        arr=arr->items->body[atx];
        arr=arr->items->body[aty];
        I64SetRem(arr->items,t);
      }
    }
  }
  return FROG_SMALL_NIL;
}
AddMethod("C3DWorldManager","removeFromGrid:",&WorldManagerRemoveFromGrid);
CFrogNum *WorldManagerUpdateThingPos(C3DWorldManager *wm,...) {
  C3DThing *t=argv[0];
  if(!ThingHasClass(t,"C3DThing")) return FROG_SMALL_NIL;
  CFrogArray *arr=wm->grid;
  I64 atx=t->x/GRID_SZ/16.;
  I64 aty=t->y/GRID_SZ/16.;
  if(atx<0||aty<0) return FROG_SMALL_NIL;
  if(atx>=w->world_width/16+1) return FROG_SMALL_NIL;
  if(aty>=w->world_height/16+1) return FROG_SMALL_NIL;
  arr=arr->items->body[atx];
  arr=arr->items->body[aty];
  if(!I64SetHas(arr->items,t))
    I64SetAdd(arr->items,t);
  return FROG_SMALL_NIL;
}
AddMethod("C3DWorldManager","updateThingPos:",&WorldManagerUpdateThingPos);
CFrogArray *WorldManagerThingsInRadius(C3DWorldManager *wm,...) {
  CFrogArray *arr=wm->grid,*ret=FrogArrayNew;
  C3DThing *t,**body;
  F64 x=AsF64(argv[0]),y=AsF64(argv[1]);
  I64 b_atx=x/GRID_SZ/16.,atx;
  I64 b_aty=y/GRID_SZ/16.,aty;
  I64 ox,oy,cnt;
  F64 r=AsF64(argv[2]);
  for(ox=-1;ox!=2;ox++)
    for(oy=-1;oy!=2;oy++) {
      atx=ox+b_atx;
      aty=oy+b_aty;
      if(atx<0||aty<0) goto next;
      if(atx>=w->world_width/16+1) goto next;
      if(aty>=w->world_height/16+1) goto next;
      arr=wm->grid;
      arr=arr->items->body[atx];
      arr=arr->items->body[aty];
      cnt=arr->items->cnt;
      body=arr->items->body;
      while(--cnt>=0) {
	t=body[cnt];
	  if(r*r>=Sqr(t->x-x)+Sqr(t->y-y)) {
            I64SetAdd(ret->items,t);
	  }
      }
next:;
    }
  return ret;
}
AddMethod("C3DWorldManager","getThingsInRadiusFromX:fromY:withRadius:",&WorldManagerThingsInRadius);
U0 PhysicsOnThing(C3DWorld *w,C3DThing *t,C3DWorldManager *wm,F64 last_tS) {
  I64 wx=t->x/GRID_SZ,wy=t->y/GRID_SZ,idx;
  if(!(0<=wx<w->world_width))
    return;
  if(!(0<=wy<w->world_height))
    return;
//Iget about 20 fps on my aspire 5920(add 5 fps)
  F64 weight=1.;
  F64 angle,dist,ox,oy;
  I64 tile=wx+wy*w->world_width;
  Bool i_am_moving=FALSE,on_ground;
  CRocket *rocket=NULL;
  CFrogArray *in_radius;
  CDoor *to_open;
  C3DThing *other;
  CI64Set *set;
  if(ThingHasClass(t,"CRocket"))
    rocket=t;
  WorldManagerRemoveFromGrid(wm,t);
  if(C3DWorldMoveZWithCollision(w,t->momz*weight,t->x,t->y,&t->z)) {
    if(!rocket)  //Explode later(computer hitting floor after we move x/y)
      t->momz=0;
  } else if(!rocket&&!t->floating)
      t->momz-=wm->gravity*weight;
  ox=t->x;
  oy=t->y;
  if(t->momy+t->momy2||t->momx+t->momx2) {
    if(!rocket) {
      t->momx*=29/30.*weight;
      t->momy*=29/30.*weight;
      if(Sign(t->momx)==-Sign(t->momx2))
	t->momx+=t->momx2*weight;
      if(Sign(t->momy)==-Sign(t->momy2))
	t->momy+=t->momy2*weight;
      if(Abs(t->momx)<2) t->momx=0;
      if(Abs(t->momy)<2) t->momy=0;
    }
//Handle slow
    if(ThingHasClass(t,"CPlayer")) {
      t->friction=0.;
      if(IsOnWaterTile(t)) {
        t->friction=.25;
      } else if(IsOnLavaTile(t)) {
        t->friction=.5;
      } 
    }
    angle=Arg(t->momx+t->momx2,t->momy+t->momy2);
    i_am_moving=TRUE;
    dist=Sqrt(Sqr(t->momx+t->momx2)+Sqr(t->momy+t->momy2))*(1.-t->friction);
    on_ground=AsF64(CallScript("`isOnGround",t));
    if(C3DWorldMoveWithCollision(w,angle,dist*weight,
	&t->x,
	&t->y,
	TRUE,
	t->z)) {
	
hit:
      t->momx=0.;
      t->momy=0.;
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
    if(t->no_fall_off_edge&&on_ground) {
      if(AsF64(CallScript("isOverEdge",t))) {
	t->x=ox;
	t->y=oy;
	CallScript("update",t); //New Chase Dir
      }
    }
  } else if(RadiusHitsWall(w,angle,&t->x,&t->y,t->z,THING_RADIUS,TRUE,,RADF_CEIL|RADF_FLOOR|RADF_DOOR))
    goto hit;
  if(rocket) {
    if(!(0.<=t->x<w->world_width*128))
      goto explode;
    if(!(0.<=t->y<w->world_height*128))
      goto explode;
    if(AsF64(CallScript("checkExplode",rocket)))
      return;
  }
//Only check for thing collision if we are the ones movin
  if(i_am_moving&&!rocket) {
    in_radius=CallScript("getObstaclesInRadiusForThing:inRadius:",wm,t,FrogNumNew(2*THING_RADIUS));
    set=in_radius->items;
    for(idx=0;idx!=set->cnt;idx++) {
      other=set->body[idx];
      if(other!=t&&Max(other->z,t->z)<=Min(other->z+THING_HEIGHT,t->z+THING_HEIGHT))
        if(AdjustRadiusThing(w,t,other,angle))
	  t->hit_thing=TRUE;
    }  
  }
  if(rocket) {
    if(HeightImpossible(w,t->x/GRID_SZ,t->y/GRID_SZ,t->z,TRUE,1.))
      goto explode;
  }
  WorldManagerUpdateThingPos(wm,t);
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
		dx=0;
	      tile_idx2=tile_idx+dx;
	      if(tile_idx2==have) {
		*offx=stain->x+dx*GRID_SZ-stain->center_x;
		*offy=stain->y+h*GRID_SZ-stain->center_y;
		return stain->dc;
	      }
	    break;
	  case 2 ... 3:
//Hits top/bottom,so check left/right tile
	      dy=0;
	      tile_idx2=tile_idx+dy*w->world_width;
	      if(tile_idx2==have) {
		*offx=stain->x-stain->center_x+dy*GRID_SZ;
		*offy=stain->y+h*GRID_SZ-stain->center_y;
		return stain->dc;
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
//-1 terminated
//https://github.com/cgyurgyik/fast-voxel-traversal-algorithm/blob/master/overview/FastVoxelTraversalOverview.md
I64 *GetTilesInPath(C3DWorld *w,F64 angle,F64 dist) {
  CI64Set *t=I64SetNew;
  F64 x=w->x/128,y=w->y/128,slope,cos,sin;
  I64 tx=x/GRID_SZ,ty=y/GRID_SZ,idx;
  I64 cnt=dist/128.;  
  Bool x_type;
  cos=Cos(angle);
  sin=Sin(angle);
  I64 stepx=Sign(cos);
  I64 stepy=Sign(sin);
  F64 current_x_index=Max(1,Ceil(x));
  F64 current_y_index=Max(1,Ceil(y));
  if(cos<0) current_x_index--;
  if(sin<0) current_y_index--;
  F64 tMaxX=(current_x_index-x)/cos;
  F64 tMaxY=(current_y_index-y)/sin;
  tx=x;
  ty=y;
  idx=ty*w->world_width+tx;
  I64SetAdd(t,idx);
  while(--cnt>=0) {
    if(tMaxX<tMaxY) {
      tMaxX+=1./Abs(cos);
      tx+=stepx;
    } else {
      tMaxY+=1./Abs(sin);
      ty+=stepy;
    } 

    if(0<=tx<w->world_width)
      if(0<=ty<w->world_height) {
        idx=ty*w->world_width+tx;
        I64SetAdd(t,idx);
	goto pass;
      }
    break;
pass:;
  }
fin:
  I64SetAdd(t,-1);
  I64 *tiles=t->body;
  Free(t);
  return tiles;
}

extern CDC *WhichTexture(C3DWorld *w,I64 tile,F64 h,F64 h2,F64 *hit_h,Bool *hit_wall);
CDC *ThingFace(C3DWorld *w,C3DThing *thing,Bool *flip=NULL) {
  C3DThingTemplate *template=thing->template;
PrintI("tt",template);
  if(template==FROG_SMALL_NIL) return NULL;
  F64 off=thing->angle-w->angle+pi,gap;
  I64 face=1;
  off=off%(2*pi);
  CDC *use_dc=NULL;
  I64 frame;
  F64 diff;
  for(gap=0.;gap<2*pi;gap+=2.*pi/4.) {
    diff=(off-gap+3*pi)%(2*pi)-pi;
//https://stackoverflow.com/questions/12234574/calculating-if-an-angle-is-between-two-angles
    if(-2*pi/4./2<=diff<=2*pi/4./2)
      break;
    face++;
  }
  if(flip) *flip=FALSE;
  switch(face) {
    default:
    case 1:
      use_dc=template->front;
      break;
    case 2:
      use_dc=template->side;
      if(flip) *flip=TRUE;
      break;
    case 3:
      use_dc=template->back;
      break;
    case 4:
      use_dc=template->side;
      break;
  }
draw:
  if(!ThingHasClass(use_dc,"CFrogImg")) return NULL;
  use_dc=use_dc(CFrogImg*)->dc;
  if(!use_dc||!AnimDCCnt(use_dc)) return NULL;
  frame=ToI64((Frog_tS-thing->animation_start_tS)/ANIM_DELAY);
  frame=MaxI64(frame,0); //Prevent poo poo suace
  if(thing->animation_no_repeat) 
     use_dc+=MinI64(frame,AnimDCCnt(use_dc)-1);
  else
    use_dc+=frame%AnimDCCnt(use_dc);
  return use_dc;
}
U0 PrepareThingsForDraw(C3DWorldManager *wm,F64 thing_scale=.6) {
  CFrogArray *arr=wm->things;WorldManagerThingsInRadius(wm,FrogNumNew(w->x),FrogNumNew(w->y),FrogNumNew(VIEW_DIST*128));
  C3DThing **things=arr->items->body,*thing;
  I64 cnt=arr->items->cnt,ix,iy,ox,oy;
  F64 normal;
  CDC *hit_texture;
  F64 width;
  for(ox=0;ox!=2*VIEW_DIST;ox++)
    for(oy=0;oy!=2*VIEW_DIST;oy++) {
      if(!w->things_around_camera[ox][oy])
	w->things_around_camera[ox][oy]=I64SetNew;
      else
	w->things_around_camera[ox][oy]->cnt=0;
    }
  while(--cnt>=0) {
    thing=things[cnt];
    if(thing->no_draw)
      goto skip;
    hit_texture=ThingFace(wm->world_handle,thing,&thing->draw_flip);
    if(!hit_texture)
      goto skip;
    thing->draw_face=hit_texture;
    normal=Arg(w->x-thing->x,w->y-thing->y)-pi/2;
    thing->scrn_st.x=thing->x-hit_texture->width/2.*Cos(normal)*thing_scale;
    thing->scrn_st.y=thing->y-hit_texture->width/2.*Sin(normal)*thing_scale;
    thing->scrn_en.x=thing->scrn_st.x+hit_texture->width*Cos(normal)*thing_scale;
    thing->scrn_en.y=thing->scrn_st.y+hit_texture->width*Sin(normal)*thing_scale;
    ix=ToI64((thing->x-w->x)/128.);
    iy=ToI64((thing->y-w->y)/128.);
    for(ox=-Floor(hit_texture->width/2./128.)-1;ox<Ceil(hit_texture->width/2./128.)+1;ox++) {
      for(oy=-Floor(hit_texture->width/2./128.)-1;oy<Ceil(hit_texture->width/2./128.)+1;oy++) {
	if(-VIEW_DIST<ox+ix<VIEW_DIST) {
	  if(-VIEW_DIST<oy+iy<VIEW_DIST) {
	    I64SetAdd(w->things_around_camera[ox+ix+VIEW_DIST][oy+iy+VIEW_DIST],thing);
	  }
        }
      }
    }
skip:;
  }
}
I64 ToTile(I64 block) {
  return block/256;
}

//https://en.wikipedia.org/wiki/Line%E2%80%93line_intersection
#ifdef TARGET_X86
Bool SegmentSegmentIntersect(CD2 *hit_at,CD2 *a,CD2 *b,CD2 *a2,CD2 *b2,F64 *t,F64 *u) {
  CD2 _a,_b,_a2,_b2,tmpb,tmpt,tmpu;
  _a.x=a->x;
  _a.y=a->y;
  _b.x=b->x;
  _b.y=b->y;
  _a2.x=a2->x;
  _a2.y=a2->y;
  _b2.x=b2->x;
  _b2.y=b2->y;
  MOVUPD XMM3,&_a[RBP];
  MOVUPD XMM4,&_b[RBP];
  MOVUPD XMM5,&_a2[RBP];
  MOVUPD XMM1,&_b2[RBP];


  MOVUPD XMM0,XMM3;
  SUBPD XMM0,XMM4 //a-b
  MOVUPD XMM2,XMM5
  SUBPD XMM2,XMM1 //a2-b2
//xx
  MOVSD2 &tmpb+8[RBP],XMM0 
  MOVSD2 &tmpb[RBP],XMM2
//yy  
  SHUFPD XMM0,XMM2,0b11
  MOVUPD XMM2,&tmpb[RBP]
  MULPD XMM2,XMM0
  MOVUPD &tmpb[RBP],XMM2

  MOVUPD XMM2,XMM5
  SUBPD XMM2,XMM1 //a2-b2
  MOVUPD XMM0,XMM3;
  SUBPD XMM0,XMM5 //a-a2
//xx 
  MOVSD2 &tmpt+8[RBP],XMM0 
  MOVSD2 &tmpt[RBP],XMM2 
  SHUFPD XMM0,XMM2,0b11 //Move yy into XMMM0
  MOVUPD XMM2,&tmpt[RBP]
  MULPD XMM2,XMM0
  MOVUPD &tmpt[RBP],XMM2


  MOVUPD XMM2,XMM3;
  SUBPD XMM2,XMM5 //a-a2
  MOVUPD XMM0,XMM3;
  SUBPD XMM0,XMM4 //a-b
//xx 
  MOVSD2 &tmpu+8[RBP],XMM0 
  MOVSD2 &tmpu[RBP],XMM2 
  SHUFPD XMM0,XMM2,0b11 //Move yy into XMMM0
  MOVUPD XMM2,&tmpu[RBP]
  MULPD XMM2,XMM0
  MOVUPD &tmpu[RBP],XMM2

//Do these after the asm blob to avoid messing up tmp registers
  F64 bottom=tmpb.y-tmpb.x;
  F64 _t=(tmpt.y-tmpt.x)/bottom;
  F64 _u=-(tmpu.y-tmpu.x)/bottom;

  if(0<=_t<=1)
    if(0<=_u<=1) {
      if(t) *t=_t;
      if(u) *u=_u;
      if(hit_at) {
	hit_at->x=a->x+_t*(b->x-a->x);
	hit_at->y=a->y+_t*(b->y-a->y);
      }
      return TRUE;
    }
  return FALSE;
}
#else
Bool SegmentSegmentIntersect(CD2 *hit_at,CD2 *a,CD2 *b,CD2 *a2,CD2 *b2,F64 *t,F64 *u) {
  F64 bottom=(a->x-b->x)*(a2->y-b2->y)-(a->y-b->y)*(a2->x-b2->x);
  F64 _t=((a->x-a2->x)*(a2->y-b2->y)-(a->y-a2->y)*(a2->x-b2->x))/bottom;
  F64 _u=-((a->x-b->x)*(a->y-a2->y)-(a->y-b->y)*(a->x-a2->x))/bottom;
  if(0<=_t<=1)
    if(0<=_u<=1) {
      if(t) *t=_t;
      if(u) *u=_u;
      if(hit_at) {
	hit_at->x=a->x+_t*(b->x-a->x);
	hit_at->y=a->y+_t*(b->y-a->y);
      }
      return TRUE;
    }
  return FALSE;
}
#endif
//https://github.com/cgyurgyik/fast-voxel-traversal-algorithm/blob/master/overview/FastVoxelTraversalOverview.md
I64 GetColorForRay(C3DWorldManager *man,CD3 *ray,F64 dist,F64 *hit_at,CD3 *hit_cords) {  
  C3DWorld *w=man->world_handle;
  CFrogArray *grid=man->grid;
  CI64Set *do_things;
  F64 x=w->x/128,y=w->y/128;
  CDoor *door;
  Bool hit=FALSE;
  F64 hit_dist=1e100;
  I64 hit_color=-1;
  I64 tx=x,ty=y,idx,tz;
  I64 cnt=dist/128.;  
  I64 stepx=Sign(ray->z);
  I64 stepy=Sign(-ray->x);
  I64 stepz=Sign(-ray->y);
  F64 current_x_index=Ceil(x);
  F64 current_y_index=Ceil(y);
  F64 current_z_index=Ceil(w->cam_height);
  if(stepx<0) current_x_index--;
  if(stepy<0) current_y_index--;
  if(stepz<0) current_z_index--;
  F64 tMaxX=(current_x_index-x)/ray->z;
  F64 tMaxY=(current_y_index-y)/-ray->x;
  F64 tMaxZ=(current_z_index-w->cam_height)/-ray->y;
  F64 dist2;
  F64 h,h2;
  F64 angle=Arg(ray->z,-ray->x);
  F64 cos=Cos(angle),sin=Sin(angle);
  F64 slope=-ray->y/Sqrt(Sqr(ray->z)+Sqr(ray->x)); //???
  F64 tan=Tan(angle);
  F64 r_abs_rx=1./Abs(ray->x);
  F64 r_abs_ry=1./Abs(ray->y);
  F64 r_abs_rz=1./Abs(ray->z);
  CDC *hit_texture;
  CDC *stain_dc;
  I64 cur,thing_idx,texture_x,texture_y;
  I64 texture_y_offset;
  I64 wall_side;
  I64 stain_x,stain_y;
  I64 color;
  I64 relx,rely;
  CD2 long;
  long.x=x+VIEW_DIST*cos;
  long.y=y+VIEW_DIST*sin;
  tx=x;
  ty=y;
  tz=Floor(w->cam_height);
  idx=ty*w->world_width+tx;
  for(cur=0;cur!=cnt&&!hit;cur++) {
    if(0<=tx<w->world_width)
      if(0<=ty<w->world_height) {
	relx=(tx-w->x/128.)+VIEW_DIST;
	rely=(ty-w->y/128.)+VIEW_DIST;
	if(0<=relx<2*VIEW_DIST)
	  if(0<=rely<2*VIEW_DIST)
	    if((do_things=w->things_around_camera[relx][rely])->cnt)
	      goto has_thing;
        goto check_tile;
has_thing:;
	C3DThing *thing;
        for(thing_idx=0;thing_idx!=do_things->cnt;thing_idx++) {
	  thing=do_things->body[thing_idx];
	  if(!thing->no_draw) {
	    CD2 origin128;
	    F64 scale=.6;
	    CD2 st,en,xyhit;
	    origin128.x=w->x/128;
	    origin128.y=w->y/128;
	    if(hit_texture=thing->draw_face) {
	      h=hit_texture->height/128.*scale;
	      if(!(Floor(thing->z)<=tz<=h+thing->z+1.))
		goto next_thing;
	      st.x=thing->scrn_st.x/128.;
	      st.y=thing->scrn_st.y/128.;
	      en.x=thing->scrn_en.x/128.;
	      en.y=thing->scrn_en.y/128.;
	      F64 i1=.5,i2=.5;
	      if(SegmentSegmentIntersect(&xyhit,&origin128,&long,&st,&en,&i1,&i2)) {
		if(1) {
		  dist=Sqrt(Sqr(xyhit.x-w->x/128)+Sqr(xyhit.y-w->y/128));
		  h=dist*slope+w->cam_height;
		  h2=hit_texture->height/128.*scale;
		  if(thing->z<=h<h2+thing->z) {
		    texture_y=ClampI64((1.-(h-thing->z)/h2)*hit_texture->height,0,hit_texture->height-1);
		    if(thing->draw_flip) i2=1.-i2;
		    texture_x=ClampI64(i2*hit_texture->width,0,hit_texture->width-1);
		    color=GrPeek0(hit_texture,texture_x,texture_y);
		    if(TRANSPARENT!=color) {
	              dist=Sqrt(Sqr(origin128.x-xyhit.x)+Sqr(origin128.y-xyhit.y))*128.;
		      if(dist<hit_dist) {
			hit=TRUE;
			hit_dist=dist;
                        if(hit_at) *hit_at=dist;
		        if(hit_cords) {
		  	  hit_cords->x=xyhit.x*128;
			  hit_cords->y=xyhit.y*128;
			  hit_cords->z=h;
		        }
	                hit_color=Fog(color,dist);
		      }
		    }
		  }
		}
	      }
	    }
next_thing:;
	  }
	}
check_tile:;
//Check for hitting a tile(WhichTexture also accounts for doors)
        texture_y_offset=0; //Ffor Dooors
        idx=(ty*w->world_width+tx)*256+tz-I8_MIN;
	if(w->world_blocks[idx]) {
tile:;
	I64 segment=0;
        CD2 corners[4];
        F64 nearest=VIEW_DIST*128,farest=0,tmp,fsegment;
        corners[0].x=tx;
        corners[0].y=ty;
        corners[1].x=tx+1;
        corners[1].y=ty;
        corners[2].x=tx+1;
        corners[2].y=ty+1;
        corners[3].x=tx;
        corners[3].y=ty+1;

	origin128.x=w->x/128;
	origin128.y=w->y/128;

        for(thing_idx=0;thing_idx!=4;thing_idx++) {
          if(SegmentSegmentIntersect(NULL,&corners[thing_idx],&corners[(thing_idx+1)&3],&origin128,&long,&fsegment,&tmp)) {
            nearest=Min(nearest,tmp);
            farest=Max(farest,tmp);
	    if(nearest==tmp) {
	      segment=fsegment*127;
	    }
	  }
        }

        if(farest) { //Was set to 0 above
          dist=nearest*VIEW_DIST*128;
          dist2=farest*VIEW_DIST*128;
        }

	if(ToI64(w->x/128)==tx&&ty==ToI64(w->y/128)) {
	  h=w->cam_height;
	  h2=slope*(dist2/128.)+w->cam_height;
	}
	else {
	  h=slope*(dist/128.)+w->cam_height;
	  h2=slope*(dist2/128.)+w->cam_height;
	}
	F64 ath=0;
	Bool hit_wall=FALSE;
	hit_texture=WhichTexture(w,idx,h,h2,&ath,&hit_wall);
	F64 hit_dist2;
        if(hit_texture&&AnimDCCnt(hit_texture)) {
	  if(hit_wall)  {
 	    color=GrPeek0(hit_texture,segment&127,ToI64(ath*128+texture_y_offset)&127);
	  } else {
	    hit_dist2=(ath-w->cam_height)/slope*128;
	    tx=hit_dist2*cos+w->x;
	    ty=hit_dist2*sin+w->y;
	    dist=Sqrt(Sqr(tx-w->x)+Sqr(ty-w->y));
 	    color=GrPeek0(hit_texture,tx&127,(ty+texture_y_offset)&127);
	  }
valid_color:
	  if(dist<hit_dist) {
	    if(hit_cords) {
              //Slightly before our wall(not in wall).
	      dist=Clamp(dist-2.,0,128*VIEW_DIST);
	      hit_cords->x=w->x+cos*dist;
	      hit_cords->y=w->y+sin*dist;
	      hit_cords->z=slope*(dist/128.)+w->cam_height;
	    }
	    if(hit_at) *hit_at=dist;
            hit=TRUE;
	    hit_dist=dist;
	    hit_color=Fog(color,dist);
	  }
        }
	}
	goto pass;
      }
    break;
pass:;
    if(tMaxX<tMaxY) {
      if(tMaxX<tMaxZ) {
        tMaxX+=r_abs_rz;
        tx+=stepx;
      } else {
        tMaxZ+=r_abs_ry;
        tz+=stepz;
      }
    } else {
      if(tMaxY<tMaxZ) {
        tMaxY+=r_abs_rx;
        ty+=stepy;
      } else {
        tMaxZ+=r_abs_ry;
        tz+=stepz;
      }
    } 
  }
fin:
  return hit_color;
}
CDC *WhichTexture(C3DWorld *w,I64 tile,F64 h,F64 h2,F64 *hit_h,Bool *hit_wall) {
  F64 have,have2;
  F64 mx,mn;
  CDoor *door;
  if(h>h2) {
    mx=h;
    mn=h2;
  } else {
    mx=h2;
    mn=h;
  }

  I64 tileh=(tile&255)+I8_MIN;
  have=tileh;
  have2=tileh+1;
  if(hit_wall) *hit_wall=TRUE;

  if(Max(mn,have)<=Min(mx,have2)) {
    if(have<=h<=have2) {
      if(hit_h) *hit_h=h;
      return w->wall_textures[w->world_blocks[tile]];
    }
    if(h>h2) {
//Looking  Down
      if(h>=have2) {//Hit top
        if(hit_wall) *hit_wall=FALSE;
        if(hit_h)*hit_h=have2;
        return w->floor_textures[w->world_blocks[tile]];
      }
    }
    if(h<h2) {
      if(h2>=have) {//Hit bottom
        if(hit_wall) *hit_wall=FALSE;
        if(hit_h) *hit_h=have;
        return w->ceil_textures[w->world_blocks[tile]];
      }
    }
  }
  return NULL;
}

I64 mp_done=0;
//https://github.com/shibenb/simple-c-raytracer
#ifdef TARGET_X86

U0 GenerateRay(C3DWorld *world,CD3 *ray_look,F64 i,F64 j,F64 w,F64 h,CD3 *pos,CD3 *lookat) {
  I32 vlookat[4];
  I32 up[4];
  F64 up2[3];
  I32 hori[4];
  I32 vert[4];
  I32 look[4];
  I32 samph[4];
  I32 sampv[4];
  I32 slook[4];
  I32 result[4];
  F64 noreg tmp;
  F64 noreg tmp2;
  F64 fov2;
  fov2=world->fov/2;
  tmp=(2*(i/w)-1);
  tmp2=(2*(j/h)-1)*(h/w);
  tmp*=fov2;
  tmp2*=fov2;
  up[0]=F64ToF32(0);
  up[1]=F64ToF32(1.);
  up[2]=F64ToF32(0);
  up[3]=F64ToF32(0.);
  
  look[0]=F64ToF32(lookat->x);
  look[1]=F64ToF32(lookat->y);
  look[2]=F64ToF32(lookat->z);

  MOVUPS XMM0,&look [RBP]
  MOVUPS XMM1,&up [RBP]
  MOVUPS XMM2,&look [RBP]
  MOVUPS XMM3,&up [RBP]
// Sexy cross product
//(http://threadlocalmutex.com/?p=8)
  SHUFPS XMM2,XMM2,-55 //1,2,0,3 as I8
  SHUFPS XMM3,XMM3,-55 //1,2,0,3
//a_yzx==XMM2
//b_yzx==XMM3
  MULPS XMM0,XMM3
  MULPS XMM1,XMM2
  SUBPS	XMM0,XMM1 //c
  SHUFPS XMM0,XMM0,-55
  MOVUPS &hori[RBP],XMM0
//XMM4(hori) is Cross(look,up)

  MOVUPS XMM0,&hori [RBP]
  MOVUPS XMM1,&look [RBP]
  MOVUPS XMM2,&hori [RBP]
  MOVUPS XMM3,&look [RBP]
  SHUFPS XMM2,XMM2,-55 //What do you think it is again
  SHUFPS XMM3,XMM3,-55
  MULPS XMM0,XMM3
  MULPS XMM1,XMM2
  SUBPS	XMM0,XMM1 //c
  SHUFPS XMM0,XMM0,-55
  MOVUPS &vert[RBP],XMM0
//XMM5 is Cross(hori,look)


  CVTSD2SS XMM4,&tmp [RBP]
  SHUFPS XMM4,XMM4,0
  MOVUPS XMM0,&hori[RBP]
  MULPS XMM4,XMM0 //samph=hori*tmp[4 vector]

  CVTSD2SS XMM5,&tmp2 [RBP]
  SHUFPS XMM5,XMM5,0 
  MOVUPS XMM0,&vert[RBP]
  MULPS XMM5,XMM0 //samph=hori*tmp[4 vector]

  ADDPS XMM4,XMM5
  MOVUPS XMM0,&look [RBP]
  ADDPS XMM4,XMM0
  MOVUPS &result[RBP],XMM4


  ray_look->x=F32ToF64(result[0]);
  ray_look->y=F32ToF64(result[1]);
  ray_look->z=F32ToF64(result[2]);  
}
#else
U0 GenerateRay(C3DWorld *world,CD3 *ray_look,F64 i,F64 j,F64 w,F64 h,CD3 *pos,CD3 *lookat) {
  CD3 up,hori,vert,look;
  F64 tmp,fov2,tmp2;
  fov2=world->fov/2;
  D3Equ(&up,0,1,0);
  D3Sub(&look,lookat,pos);
  D3Unit(&look);
  D3Cross(&hori,&look,&up);
  D3Cross(&vert,&hori,&look);
  
  CD3 samph,sampv,slook;
  i=(2*(i/w)-1);
  j=(2*(j/h)-1)*(h/w);
  D3Mul(&samph,i*fov2,&hori);
  D3Mul(&sampv,j*fov2,&vert);
  D3Add(&slook,&samph,&sampv);
  D3Add(ray_look,&slook,&look);
  D3Unit(ray_look);
}
#endif
U0 MPCastCol(C3DWorldManager *wm) {
  C3DWorld *w=wm->world_handle;
  F64 angle=w->angle-w->fov/2,angle2,hit_dist,ath;
  F64 dist,dist2,h,h2;
  F64 sin,width=GR_WIDTH,cos1,sin1,tan1,cos12;
  I64 cap,idx,x,y;
  CDoor *door;
  CDC *to_dc=w->to_dc;
  CDC *what;
  CD3 *p;
  I64 *tiles,tile;
  I64 color,col;
  U32 *ptr;
  I32 *depth_ptr;
  I64 tx,ty;
  I64 segment;
  I32 idist,row;
  Bool hit_wall;
  F64 angle_offset_table[GR_WIDTH];
  F64 y_angle_offset_table[GR_HEIGHT];
  F64 xrot=w->angle2;
  CD3 at,look_at,ray;
  D3Equ(&at,0,0,0);
  D3Equ(&look_at,
	0,
	Sin(xrot),
	1
	);
  look_at.x=Sin(-w->angle);
  look_at.z=Cos(-w->angle);
  idx=ToF64(Gs->num)/ToF64(mp_cnt)*GR_WIDTH;
  cap=ToF64(Gs->num+1)/ToF64(mp_cnt)*GR_WIDTH;
  for(x=idx;x<cap;x+=w->step_width) {
// divide by cos2_lookup_table to get 32 blocks from the camera
$SP,"<1>",BI=1$;



















    ptr=&to_dc->body[x];
    depth_ptr=&to_dc->depth_buf[x];
    for(y=0;y<GR_HEIGHT;y+=w->step_width) {
//Nroot has no idea what he was doing here.Literaly typing random stuff
      GenerateRay(w,&ray,x,y,to_dc->width,to_dc->height,&at,&look_at);   
      p=&w->to_point[x/4][y/4];
//If we dont hit a wall,just fill with "far out in the distacnve"
      p->x=w->x+ray.x*I16_MAX;
      p->y=w->y+ray.y*I16_MAX;
      p->z=w->cam_height;
      color=GetColorForRay(wm,&ray,32*GRID_SZ,&dist,p);
      idist=dist;
      idist|=idist<<32;
      if(color!=-1&&w->step_width==2) {
        for(col=0;col!=2;col++) {
	    if(col&1)
	      ptr(U16*)[0]=color;
	    else
	      ptr(U16*)[0]=color>>8; //Dither
            depth_ptr[0](I64)=idist;
	    ptr(U8*)+=to_dc->width_internal;
	    depth_ptr+=to_dc->width_internal;
	}
	goto fin;
      }
      if(color!=-1&&w->step_width==4) {
        for(col=0;col!=4;col++) {
	    if(col&1)
	      ptr(U32*)[0]=color;
	    else
	      ptr(U32*)[0]=color>>8; //Dither
            depth_ptr[0](I64)=idist;
            depth_ptr[2](I64)=idist;
	    ptr(U8*)+=to_dc->width_internal;
	    depth_ptr+=to_dc->width_internal;
	}
	goto fin;
      }
      if(color!=-1&&w->step_width==6) {
        for(col=0;col!=6;col++) {
	    if(col&1) {
	      ptr(U32*)[0]=color;
	      ptr(U16*)[2]=color;
	    } else {
	      ptr(U32*)[0]=color>>8; //Dither
	      ptr(U16*)[2]=color>>8; //Dither
            }
            depth_ptr[0](I64)=idist;
            depth_ptr[2](I64)=idist;
            depth_ptr[4](I64)=idist;
	    ptr(U8*)+=to_dc->width_internal;
	    depth_ptr+=to_dc->width_internal;
	}
	goto fin;
      }
      if(color!=-1&&w->step_width==8) {
	  for(col=0;col!=8;col++) {
	    if(col&1)
	      ptr(U64*)[0]=color;
	    else
	      ptr(U64*)[0]=color>>8|color<<(64-8); //Rotate for Dither
            depth_ptr[0](I64)=idist;
            depth_ptr[2](I64)=idist;
            depth_ptr[4](I64)=idist;
            depth_ptr[6](I64)=idist;
	    ptr(U8*)+=to_dc->width_internal;
	    depth_ptr+=to_dc->width_internal;
	  }
	  goto fin;
      }
      ptr(U8*)+=to_dc->width_internal*w->step_width;
      depth_ptr(I32*)+=to_dc->width_internal*w->step_width;
fin:;
    }
  }
  LBts(&mp_done,Gs->num);
}
U0 C3DWorldCastRays(C3DWorld *w) {
  I64 c;
  C3DWorldManager *man=FrogSymbol("world")->value;
  lock mp_done=0;
  for(c=1;c<mp_cnt;++c) {
    JobQue(&MPCastCol,man,c);
  }
  MPCastCol(man);
  for(c=1;c<mp_cnt;++c) {
    while(!Bt(&mp_done,c))
     __Sleep(2);
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
  I64 t_at_tile=ToI64(t->x/GRID_SZ)+ToI64(t->y/GRID_SZ)*w->world_width;
  I64 x,y,z;
  for(idx=0;ti[idx]!=-1;idx++) {
    if(ti[idx]==at_tile) {
      if(at_tile==t_at_tile) {
	ret=TRUE;
	break;
      }
    } else {
      x=ti[idx]%w->world_width;
      y=ti[idx]/w->world_width;
      FindRayWall(w,
	    Tan(angle),
	    Cos(angle),
	    Sin(angle),
	    NULL,
	    &near,
	    NULL,
	    I8_MIN,
	    x,
	    y,
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
	    x,
	    y,
	    TRUE,//far sdie
	    TRUE
      );
//TODO replace "+1" with thing height
      interp=Min((near+far)/2,dist)/dist*(t->z+1.-w->cam_height)+w->cam_height;
//Perhaps we got an extra block
      if(ti[idx]==t_at_tile)
	break;
      if(BlockAtXYZ(x,y,Floor(interp))) {
	ret=FALSE;
	break;
      }
    }
  }
  Free(ti);
  return ret;
}
#define THING_DRAW_CUTOFF GRID_SZ/2

U0 Mat4x4MulXYZ_F64(I64 *r,F64 *_x,F64 *_y,F64 *_z)
{
  F64 x1,y1,z1,xx=*_x,yy=*_y,zz=*_z;
  x1=(r[0*4+0]*xx+r[0*4+1]*yy+r[0*4+2]*zz+r[0*4+3])/GR_SCALE;
  y1=(r[1*4+0]*xx+r[1*4+1]*yy+r[1*4+2]*zz+r[1*4+3])/GR_SCALE;
  z1=(r[2*4+0]*xx+r[2*4+1]*yy+r[2*4+2]*zz+r[2*4+3])/GR_SCALE;
  *_x=x1;*_y=y1;*_z=z1;
}

U0 PointToScrn(C3DWorld *w,F64 x,F64 y,F64 z,CD3 *res) {
  F64 dist=Sqrt(Sqr(x-w->x)+Sqr(y-w->y));
  F64 dir=Arg(x-w->x,y-w->y);
  F64 xrot=Arg(dist/128,z-w->cam_height)-w->angle2;
  z=GR_HEIGHT/2-Wrap(xrot)/w->fov*GR_HEIGHT;
  res->x=GR_WIDTH/2+Wrap(dir-w->angle)/((w->fov/GR_WIDTH));
  res->y=z;
  res->z=dist; //???
}

U0 DrawParticle(C3DWorld *w,C3DParticle *p) {
  I32 dist=Sqrt(Sqr(w->x-p->x)+Sqr(w->y-p->y));
  I64 x0,y0;
  CD3 res;
  w->to_dc->color=p->color;
  w->to_dc->thick=(DIST_SCALE/ToF64(1+dist))/GRID_SZ*p->size;
  PointToScrn(w,p->x,p->y,p->z,&res);
  if(w->to_dc->thick>0)
    GrPlot3(w->to_dc,res.x,res.y,dist);
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

U0 DrawDogTongue(C3DWorld *w,CDogTongue *t) {
  if(!ThingHasClass(t,"CDogTongue"))
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
    dc->color=RED;
    dc->thick=16;   
    Line3D(w,dc,&stp,&enp);
    dc->color=LTRED;
    dc->thick=24;
    GrPlot3(dc,enp.x,enp.y,enp.z);
  }
}

U0 DrawLightningBolt(C3DWorld *w,CLightningBolt *l) {
  CDC *dc=w->to_dc;
  CD3 stp,enp,last;
  CLightningLink **links=l->links(CFrogArray*)->items->body;
  I64 idx,cnt=l->links(CFrogArray*)->items->cnt;
  if(cnt<1) return;
  last.x=links[0]->x;
  last.y=links[0]->y;
  last.z=links[0]->z;
  dc->thick=4;
  for(idx=1;idx!=cnt;idx++) {
    dc->color=links[idx]->color;
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

U0 DrawPissStream(C3DWorld *w,CPissStream *ps) {
  CDC *dc=w->to_dc;
  CD3 stp,enp,last;
  if(!ThingHasClass(ps,"CPissStream"))
    return;
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
U0  Draw2DThing(C3DWorld *w,C3DThing *thing) {
fin:
  if(ThingHasClass(thing,"CPorky")) {
    DrawDogTongue(w,thing(CPorky*)->tongue);
  }
  if(ThingHasClass(thing,"CFrogNPC")) {
    DrawFrogTongue(w,thing(CFrogNPC*)->tongue);
  }
  if(ThingHasClass(thing,"CPlayer")) {
    DrawPissStream(w,thing(CPlayer*)->piss_stream);
  }
  if(ThingHasClass(thing,"CZombie")) {
   DrawPissStream(w,thing(CZombie*)->piss_stream);
  }
  if(ThingHasClass(thing,"CAssBird")) {
    DrawLightningBolt(w,thing(CAssBird*)->lightning_bolt);
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
CFrogThing *WorldManagerNewSweepSound(C3DWorldManager *man,...) {
  if(man->sound_task) Kill(man->sound_task,FALSE);
  man->sound_task=Sweep(
	AsF64(argv[0]),
	AsF64(argv[1]),
	AsF64(argv[2]));
  return FROG_SMALL_NIL;
}
AddMethod("C3DWorldManager","sweepSoundForTime:withMin:withMax:",&WorldManagerNewSweepSound);
CFrogThing *WorldManagerNewNoiseSound(C3DWorldManager *man,...) {
  if(man->sound_task) Kill(man->sound_task,FALSE);
  man->sound_task=Noise(
	AsF64(argv[0]),
	AsF64(argv[1]),
	AsF64(argv[2]));
  return FROG_SMALL_NIL;
}
AddMethod("C3DWorldManager","noiseSoundForTime:withMin:withMax:",&WorldManagerNewNoiseSound);
CFrogThing *WorldManagerGetQuestChatBot(C3DWorldManager *man,...) {
  U8 *name=AsString(argv[0]);
  CEliza *e=FROG_SMALL_NIL;
  if(name)
    e=LoadQuestChatBot(name);
  Free(name);
  return e;
}
AddMethod("C3DWorldManager","getQuestChatBot:",&WorldManagerGetQuestChatBot);
Bool WorldManagerFloorIsLiquid(C3DWorldManager *man,...) {
  I64 x=AsF64(argv[0]);
  I64 y=AsF64(argv[1]);
  I64 z=AsF64(argv[2]);
  I64 tile=(x+y*w->world_width)*256+z-I8_MIN;
  if(0<=tile<w->world_width*w->world_height) {
    return FrogNumNew(IsLiquidTile(w->world_blocks[tile]));
  }
  return FrogNumNew(0);
}
AddMethod("C3DWorldManager","floorIsLiquidAtX:atY:atZ:",&WorldManagerFloorIsLiquid);

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
CFrogThing *WorldManagerSetTileAtXAtY(C3DWorldManager *self,...) {
  I8 tile=AsF64(argv[0]);
  I64 x=AsF64(argv[1]);
  I64 y=AsF64(argv[2]);
  I64 z=AsF64(argv[3]);
  if(0<=x<w->world_width)
    if(0<=y<w->world_height) {
      if(I8_MIN<=z<=I8_MAX)
        return w->world_blocks[(x+y*w->world_width)*256+z-I8_MIN]=tile;
    }
  return FROG_SMALL_NIL;
}
AddMethod("C3DWorldManager","setTile:atX:atY:atZ:",&WorldManagerSetTileAtXAtY);


CFrogThing *ThingCanSeeThing(C3DThing *self,...) {
  F64 old_x=w->x,old_y=w->y,old_z=w->cam_height;
  CFrogThing *ret;
  C3DThing *other=argv[0];
  if(other==FROG_SMALL_NIL) return FROG_SMALL_NIL;
  w->x=self->x;
  w->y=self->y;
//TODO replace "+1"  with thing height
  w->cam_height=self->z+1.;
  ret=FrogNumNew(CanSee2DThing(w,other));
  w->x=old_x;
  w->y=old_y;
  w->cam_height=old_z;
  return ret;
}
AddMethod("C3DThing","canSeeThing:",&ThingCanSeeThing);


CFrogThing *ScreenCoordToDist(C3DWorldManager *self,...) {
  CD3 *p=&w->to_point[GR_WIDTH/2/4][GR_HEIGHT/2/4];
  return FrogNumNew(Sqrt(Sqr(p->x-w->x)+Sqr(p->y-w->y)));
}
AddMethod("C3DWorldManager","screenCoordToDist",&ScreenCoordToDist);
CFrogThing *ScreenCoordToX(C3DWorldManager *self,...) {
  CD3 *p=&w->to_point[GR_WIDTH/2/4][GR_HEIGHT/2/4];
  return FrogNumNew(p->x);
}
AddMethod("C3DWorldManager","screenCoordToX",&ScreenCoordToX);
CFrogThing *ScreenCoordToY(C3DWorldManager *self,...) {
  CD3 *p=&w->to_point[GR_WIDTH/2/4][GR_HEIGHT/2/4];
  return FrogNumNew(p->y);
}
AddMethod("C3DWorldManager","screenCoordToY",&ScreenCoordToY);
CFrogThing *ScreenCoordToZ(C3DWorldManager *self,...) {
  CD3 *p=&w->to_point[GR_WIDTH/2/4][GR_HEIGHT/2/4];
  return FrogNumNew(p->z);
}
AddMethod("C3DWorldManager","screenCoordToZ",&ScreenCoordToZ);
//
// World Edit section
//

CFrogNum *WorldManagerGetShiftKey(C3DWorldManager *,...) {
  return FrogNumNew(Bt(kbd.down_bitmap,SC_SHIFT));
}
AddMethod("C3DWorldManager","getShiftKey",&WorldManagerGetShiftKey);

CFrogNum *WorldManagerGetTileAtXAtYAtZ(C3DWorldManager *,...) {
  I64 x=Floor(AsF64(argv[0]));
  I64 y=Floor(AsF64(argv[1]));
  I64 z=Floor(AsF64(argv[2]));
  return FrogNumNew(BlockAtXYZ(x,y,z));
}
AddMethod("C3DWorldManager","getTileAtX:atY:atZ:",&WorldManagerGetTileAtXAtYAtZ);
CFrogNum *WorldManagerSetTileAtXAtYAtZ(C3DWorldManager *,...) {
  I64 x=Floor(AsF64(argv[1]));
  I64 y=Floor(AsF64(argv[2]));
  I64 z=Floor(AsF64(argv[3]));
  if(0<=x<w->world_width)
    if(0<=y<w->world_height)
      if(I8_MIN<=z<=I8_MAX) {
	w->world_blocks[(x+y*w->world_width)*256+z-I8_MIN]=AsF64(argv[0]);
      }
  return FROG_SMALL_NIL;
}
AddMethod("C3DWorldManager","setTile:atX:atY:atZ:",&WorldManagerSetTileAtXAtYAtZ);


//
// Test section
//
#ifdef TEST_3D
 DocClear;
#include "UI.HC"
InitWorld;
PrintI("doofus",FrogSymbol("world")->value);
I64 mp_thing_done=0;
extern CDC *MakeMinimap1(C3DWorld *w,F64 x,F64 y,F64 angle,I64 radius,F64 height);
U0 Draw3DWorld(CTask *,CDC *dc) {
  C3DWorldManager *man=FrogSymbol("world")->value;
  man->world_handle=w;
  w->_wall_stains=man->wall_stains->items;
  w->_floor_stains=man->floor_stains->items;
  w->_2d_things=man->things->items;
  PrepareThingsForDraw(man);
  CDoor **doors;
  CPlayer *player=CallScript("getPlayer",man);
  if(player==FROG_SMALL_NIL) {
    return;
  }
  CFrogImg *hand_gr,*minimap;
  I32 *odepth_buf;
  I64 tx,ty,c,f;
  CI64Set *s;
  C3DParticle *p,*head,*n;
  CShellCasing *shellc;
  CHandItem *hand=FrogSymbol("hand_item")->value;
  w->angle2=player->angle2;
  w->angle=player->angle;
  w->x=player->x;
  w->y=player->y;
  w->cam_height=player->z+.6;
  w->to_dc=dc;
  DCFill(dc,LTCYAN);
  DCDepthBufRst(dc);
  odepth_buf=dc->depth_buf;
  InitTables(w->angle,w->fov);
  C3DWorldCastRays(w);   
  mp_thing_done=0;
  CFrogThing ***body=MAllocIdent(w->_2d_things->body);
  I64 idx=w->_2d_things->cnt;
//Draw normal things first
  while(--idx>=0)
    if(!ThingHasClass(body[idx],"CPickup"))
      Draw2DThing(w,body[idx]);
//Draw powerups in front
  idx=w->_2d_things->cnt;
  while(--idx>=0)
    if(ThingHasClass(body[idx],"CPickup"))
      Draw2DThing(w,body[idx]);
  Free(body);
  
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
	if(BlockAtXYZ(tx,ty,Floor(p->z))) {
	  if(p->momz>0.) {
	    p->momz=0;
	    p->z=Floor(p->z);
	  } else if(p->momz<0.) {
	    p->z=Ceil(p->z);
	    p->momz=0.;
	  }
	}
      }
    DrawParticle(w,p);
    n=p->next;
    if(Frog_tS>1+p->born_at) {
      QueRem(p);
      Free(p);
      w->particle_cnt--;
    }
  }
  doors=man->doors->items->body;
  c=man->doors->items->cnt;
//Rely on wall commands to choose what part of door to draw
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
	  if(ThingHasClass(shellc->dc,"CFrogImg"))
	   AnimDCBlot(dc,shellc->x,shellc->y,shellc->dc->dc);
	}
      }
   }
  } 

  if(ThingHasClass(hand,"CHandItem")) {
    hand->x=ms.pos.x;
    if(ThingHasClass(hand_gr=hand->gr,"CFrogImg")) {
      c=AnimDCCnt(hand_gr->dc);
      f=(Frog_tS-hand->anim_start_tS)/ANIM_DELAY;
      if(hand->anim_no_repeat) {
        if(f>=c)
	  f=c-1;
	else
          f%=c;
      } else 
        f%=c;
      GrBlot(dc,hand->x+hand->xoff-hand_gr->dc->width/2,hand->y+hand->yoff-hand_gr->dc->height/2,hand_gr->dc+f);
    }
  }
fin:
/*  minimap=MakeMinimap1(man,player->x,player->y,player->angle,64,player->z);
  GrBlot(dc,GR_WIDTH-128-16,30,minimap);
  DCDel(minimap);*/
  dc->depth_buf=odepth_buf;
  w->to_dc=NULL;
}

CFrogThing *WorldManagerEmptyWithDim(C3DWorldManager *man,...) {
  w->world_width=AsF64(argv[0]);
  w->world_height=AsF64(argv[1]);
  Free(w->world_blocks);
  w->world_blocks=CAlloc(256*(w->world_width*w->world_height),frog_mem_task);
  CFrogDictionary *old_templates=man->thing_templates,*ot2=man->tile_templates;
  CallScript("initGrid",man);
  man->thing_templates=old_templates;
  man->tile_templates=ot2;
  w->_wall_stains=man->wall_stains->items;
  w->_floor_stains=man->floor_stains->items;
  w->_2d_things=man->things->items;
  return man;
}
AddMethod("C3DWorldManager","emptyWorldWithWidth:withHeight:",&WorldManagerEmptyWithDim);
CDC *MakeMinimap1(C3DWorldManager *wm,F64 x,F64 y,F64 angle,I64 radius,F64 height) {
/*
  CDC *mask=DCNew(radius*2,radius*2),*tile_dc;
  CDC *res=DCNew(radius*2,radius*2);
  I64 px,py;
  I64 x2,y2;
  I64 wx,wy,wz=0,tmp;
  I64 mat2[16];
  F64 angle2,dist;
  CFrogArray *near;
  C3DThing *thing;
  CI64Set *near_set;
  U8 *ptr,*mask_ptr,color;
  Mat4x4IdentEqu(mat2);
  angle+=pi/2;
  Mat4x4RotZ(mat2,angle);
  Mat4x4Scale(mat2,12.);
  Mat4x4TranslationEqu(mat2,x,y,0);

  DCFill(res,TRANSPARENT);
  mask->color=WHITE;
  GrFillCircle(mask,radius,radius,0,radius*2);
  for(py=0;py!=res->height;py++) {
    ptr=res->body+py*res->width_internal;
    mask_ptr=mask->body+py*mask->width_internal;
    for(px=0;px!=res->width;px++)  {
      x2=px;
      y2=py;
      if(*mask_ptr) {
        wx=x2-radius;
        wy=y2-radius;
	wz=0;
        Mat4x4MulXYZ(mat2,&wx,&wy,&wz);
        color=BLACK;
	x2=wx%128/128.*16;
	y2=wy%128/128.*16;
	wx/=128;
	wy/=128;
	if(0<=wx<w->world_width)
	  if(0<=wy<w->world_height) {
	    tmp=wx+wy*w->world_width;
	    tile_dc=NULL;
	    if(height>=w->ceilmap[tmp])
              tile_dc=w->floor_textures1616[w->world_mat[tmp].u8[1]];
	    if(!tile_dc)
              tile_dc=w->floor_textures1616[w->world_mat[tmp].u8[0]];
	    if(tile_dc)
	      color=GrPeek0(tile_dc,x2,y2);
	  }
        *ptr=color;
      }
      mask_ptr++;
      ptr++;
    }
  }
  near=WorldManagerThingsInRadius(wm,FrogNumNew(x),FrogNumNew(y),FrogNumNew(radius*128));
  if(near!=FROG_SMALL_NIL) {
    near_set=near->items;
    for(tmp=0;tmp!=near_set->cnt;tmp++) {
      thing=near_set->body[tmp];
      if(thing->health>0.||ThingHasClass(thing,"CPickup")) {
        angle2=Arg(thing->x-x,thing->y-y)-angle;
        dist=Sqrt(Sqr(thing->x-x)+Sqr(thing->y-y))*(12./128.);
        res->color=LTPURPLE; //TODO change
        res->thick=6;
        GrPlot3(res,
	  radius+dist*Cos(angle2),
	  radius+dist*Sin(angle2),
	  0
	);
      }
    }
  }
  DCDel(mask);
  return res;
*/
  return DCNew(1,1);
}
CFrogThing *WorldPhysics(C3DWorldManager *wm,...) {
  C3DThing **body=MAllocIdent(w->_2d_things->body),*thing,*player;
  player=CallScript("getPlayer",wm);
  I64 c=w->_2d_things->cnt,idx;
  F64 t,now=AsF64(FrogTimeNow(FROG_SMALL_NIL)->ts);
//Heres the deal.
//If we are a client,we will let the server do the physics on everyting except the player
  if(wm->is_client) {
    if(ThingHasClass(player,"CPlayer")) {
      PhysicsOnThing(w,player,wm,0.);
      player->momx2=0;
      player->momy2=0;
//interoplate things
      for(idx=0;idx<c;idx++) {
        thing=body[idx];
	  if(thing!=player) {
//interpolate_end_tS is the time we recived,start_tS is the frame before that
	    t=(now-thing->interpolate_end_tS)/(thing->interpolate_end_tS-thing->interpolate_start_tS);
            thing->x=Lerp(t,thing->server_old_x,thing->server_new_x);
            thing->y=Lerp(t,thing->server_old_y,thing->server_new_y);
            thing->z=Lerp(t,thing->server_old_z,thing->server_new_z);
	  }
      }
    }
    Free(body);
    return FROG_SMALL_NIL;
  }
  for(idx=0;idx<c;idx++) {
    thing=body[idx];
//Only update when in view
    if(Sqr(VIEW_DIST*GRID_SZ)
		>Sqr(thing->y-player->y)+Sqr(thing->x-player->x)) {
      PhysicsOnThing(w,thing,wm,0.);
      if(body[idx]==player) {
	player->momx2=0;
	player->momy2=0;
      }
    }
  }
  Free(body);
  return FROG_SMALL_NIL;
}
AddMethod("C3DWorldManager","physics",&WorldPhysics);



CFrogThing *TileTemplateUpdate(CTileTemplate *tile,...) {
  I64 idx=tile->tile_idx;
  CDC *dc;
  if(dc=w->wall_textures[idx])
    AnimDCDel(dc);
  if(dc=w->floor_textures[idx])
    AnimDCDel(dc);
  if(dc=w->ceil_textures[idx])
    AnimDCDel(dc);
  if(ThingHasClass(tile->wall_texture,"CFrogImg")) {
    w->wall_textures[idx]=ScaleDC(tile->wall_texture->dc,128,128,frog_mem_task);
  } else
    w->wall_textures[idx]=NULL;

  if(ThingHasClass(tile->floor_texture,"CFrogImg")) {
    w->floor_textures[idx]=ScaleDC(tile->floor_texture->dc,128,128,frog_mem_task);
  } else
    w->floor_textures[idx]=NULL;

  if(ThingHasClass(tile->ceil_texture,"CFrogImg")) {
    w->ceil_textures[idx]=ScaleDC(tile->ceil_texture->dc,128,128,frog_mem_task);
  } else
    w->ceil_textures[idx]=NULL;
  return FROG_SMALL_NIL;
}
AddMethod("CTileTemplate","updateTextures",&TileTemplateUpdate);
//
//
//
#if __CMD_LINE__
CallScript("newLandscapeWithWidth:withHeight:",FrogSymbol("world")->value,FrogNumNew(100),FrogNumNew(100));
C3DWorldShell *shell=ConstructThing("C3DWorldShell");
CallScript("init",shell);
UIShellRun(shell);
#endif
#endif
#endif               
   
*   ]   g   3   
)   _   l   ‚   #   '   i   '   !   ‰   k   ‹   '   _   j   [         32 Away from camera    ^      
m   ”   j   "    