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
U64 fog0_table[0x10][COLORS_NUM];
U64 fog1_table[0x10][COLORS_NUM];
U64 fog2_table[0x10][COLORS_NUM];
U0 ErectFogTable0(U64 *table,I64 fog_color,F64 ratio) {
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
U0 ErectFogTable(U64 *table,F64 ratio) {
  I64 c;
  for(c=0;c!=16;c++)
     ErectFogTable0(&table[c*16],c,ratio);
}
ErectFogTable(fog0_table,.75);
ErectFogTable(fog1_table,.5);
ErectFogTable(fog2_table,.25);
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
AddMethod("CFrogImg","asString",&FrogImgToString);
CFrogStr *FrogImgFromString(CFrogImg *img,...) {
  CFrogStr *s=argv[0];
  CDC *d=NULL;
  if(s) {
    d=AnimDCLoad(s->items->body,,frog_mem_task);
    AnimDCDel(img->dc);
    img->dc=d;
  }
  return FROG_SMALL_NIL;
}
AddMethod("CFrogImg","setGraphicsFromString:",&FrogImgFromString);


U64 Fog(I64 color,I64 dist,U8 fcolor=BLACK) {
  dist>>=7; //GRID_SZ is 128(7 bits)
  if(dist<=FOG0_DIST)
    return gr.to_8_colors[color];
  if(dist<=FOG1_DIST)
    return fog0_table[fcolor][color];
  if(dist<=FOG2_DIST)
    return fog1_table[fcolor][color];
  return fog2_table[fcolor][color];
}

Bool IsLiquidTile(I64 t) {
  switch(t) {
    case 6: //water
    case 10: //lava
      return TRUE;
  }
  return FALSE;
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
  U8 splat_lump_name[STR_LEN];
  Bool hit;
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
   I64 things_around_camera_origin_x;
   I64 things_around_camera_origin_y;
   CI64Set *things_around_camera[VIEW_DIST*2][VIEW_DIST*2];
   CI64Set *stains_around_camera[VIEW_DIST*2][VIEW_DIST*2];
};
C3DWorld *w;
extern U0 Draw2DThing(C3DWorld *w,C3DThing *thing);
#define MAX_PARTICLES 64
U0 NewParticle(C3DWorld *w,I64 color,I64 sz,F64 x,F64 y,F64 z,F64 mx,F64 my,F64 mz,U8 *splat_lump_name=NULL) {
  C3DParticle *p;
  if(w->particle_cnt>=MAX_PARTICLES) {
    w->particle_cnt--;
    QueRem(p=w->particles.next);
    Free(p);
  }
  p=CAlloc(sizeof(C3DParticle),w->mem_task);
  p->color=color;
  p->size=sz;
  p->x=x;
  p->y=y;
  p->z=z;
  p->momx=mx;
  p->momy=my;
  p->momz=mz;
  p->born_at=Frog_tS;
  if(splat_lump_name)
    StrCpy(p->splat_lump_name,splat_lump_name);
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
  ret->world_width=64;
  ret->world_height=64;
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
Bool IsSolidTile(I64 t) {
  if(!t) return FALSE;
  return !IsLiquidTile(t);
}
Bool HeightImpossible(C3DWorld *w,I64 ix,I64 iy,F64 above,Bool allow_ceil,F64 tallness=.1,F64 wiggle_room=0) {
  I64 iz=Floor(above);
  I64 c,idx2,t;
  F64 h;
  if(!(-128<iz<128)) return FALSE;
  if(IsSolidTile(BlockAtXYZ(ix,iy,iz))) {
     return TRUE;
  }
  for(idx2=0;idx2<tallness;idx2++) {
    idx2++;
    if(IsSolidTile(BlockAtXYZ(ix,iy,iz+idx2)))
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

//Cant move anywhere but up
  if(z==oz) {
    while(HeightImpossible(w,x/GRID_SZ,y/GRID_SZ,z,TRUE,tallness))
      ++z;
  }

  if(hit)
    if(Abs(z-Floor(z))<=2*dir/128.)
      z=Floor(z);
  *_height=z;
  return hit;
}
//Returns true on wall hit
Bool C3DWorldMoveWithCollision(C3DWorld *w,F64 angle,F64 dist,F64 *x,F64 *y,Bool adjust_smart=TRUE,F64 height=0) {
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
  if(adjust_smart)
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
  if(C3DWorldMoveZWithCollision(w,t->momz*weight+t->momz2*weight,t->x,t->y,&t->z)) {
    if(!rocket)  //Explode later(computer hitting floor after we move x/y)
      t->momz=0;
  } else if(!rocket&&!t->floating) {
    if(IsLiquidTile(BlockAtXYZ(t->x/128,t->y/128,t->z))) {
      t->momz=t->momz2-wm->gravity/3*weight;
    } else 
      t->momz-=wm->gravity*weight;
  }
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
    on_ground=AsF64(CallScript("isOnGround",t));
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
Bool PreparePlot(C3DThing *t,I64 x,I64 y,I64 z) {
  CI64Set *use;
  I64 ox=0,oy=0;
  x-=w->things_around_camera_origin_x*128;
  y-=w->things_around_camera_origin_y*128;
//Add offsets to avoid integer truncation issues with divdie
  for(ox=-1;ox<=1;ox++)
    for(oy=-1;oy<=1;oy++)
     if(0<=x/128+ox<2*VIEW_DIST)
       if(0<=y/128+oy<2*VIEW_DIST) {
         use=w->things_around_camera[x/128+ox][y/128+oy];
         if(!I64SetHas(use,t))
          I64SetAdd(use,t);
       }
  return TRUE;
}
//Also prepares CWallStain's
U0 PrepareThingsForDraw(C3DWorldManager *wm,F64 thing_scale=.6) {
  CFrogArray *arr=wm->things;WorldManagerThingsInRadius(wm,FrogNumNew(w->x),FrogNumNew(w->y),FrogNumNew(VIEW_DIST*128));
  C3DThing **things=arr->items->body,*thing;
  CWallStain **stains,*stain;
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
  w->things_around_camera_origin_x=Floor(w->x/128.)-VIEW_DIST;
  w->things_around_camera_origin_y=Floor(w->y/128.)-VIEW_DIST;
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
    Line(thing,
	thing->scrn_st.x,
	thing->scrn_st.y,
	0,
	thing->scrn_en.x,
	thing->scrn_en.y,
	0,
	&PreparePlot,
	64
	);
skip:;
  }

  //Stains
  for(ox=0;ox!=2*VIEW_DIST;ox++)
    for(oy=0;oy!=2*VIEW_DIST;oy++) {
      if(!w->stains_around_camera[ox][oy])
	w->stains_around_camera[ox][oy]=I64SetNew;
      else
	w->stains_around_camera[ox][oy]->cnt=0;
    }

  stains=wm->wall_stains->items->body;
  cnt=wm->wall_stains->items->cnt;
  while(--cnt>=0) {
    stain=stains[cnt];
    ix=stain->tile_x-w->things_around_camera_origin_x;
    iy=stain->tile_y-w->things_around_camera_origin_y;
    if(0<=ix<2*VIEW_DIST)
      if(0<=iy<2*VIEW_DIST)
        I64SetAdd(w->stains_around_camera[ix][iy],stain);
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
#define RAY_TRACE_MAX_DEPTH 3
I64 GetColorForRay(C3DWorldManager *man,CD3 *origin,CD3 *ray,F64 dist,F64 *hit_at,CD3 *hit_cords,I64 depth=0,I64 last_block=0,I64 fog_color=BLACK) { 
  if(Abs(ray->x-Ceil(ray->x))<.001)
    ray->x-=.001;
  if(Abs(ray->y-Ceil(ray->y))<.001)
    ray->y-=.001;
  if(Abs(ray->z-Ceil(ray->z))<.001)
    ray->z-=.001;
  CFrogArray *grid=man->grid;
  C3DWorld *w=man->world_handle;
  CI64Set *do_things;
  F64 x=origin->x/128,y=origin->y/128;
  CDoor *door;
  Bool hit=FALSE;
  F64 hit_dist=1e100;
  CWallStain **wall_stains,*wall_stain;
  I64 wall_stain_cnt;
  I64 hit_color=-1;
  I64 tx=x,ty=y,idx,tz;
  I64 cnt=dist/128.;  
  I64 stepx=Sign(ray->z);
  I64 stepy=Sign(-ray->x);
  I64 stepz=Sign(-ray->y);
  F64 current_x_index=Ceil(x);
  F64 current_y_index=Ceil(y);
  F64 current_z_index=Ceil(origin->z);
  if(stepx<0) current_x_index--;
  if(stepy<0) current_y_index--;
  if(stepz<0) current_z_index--;
  F64 tMaxX=(current_x_index-x)/ray->z;
  F64 tMaxY=(current_y_index-y)/-ray->x;
  F64 tMaxZ=(current_z_index-origin->z)/-ray->y;
  F64 dist2;
  F64 h,h2;
  F64 angle=Arg(ray->z,-ray->x);
  F64 cos=Cos(angle),sin=Sin(angle);
  F64 slope=-ray->y/Sqrt(Sqr(ray->z)+Sqr(ray->x)); //???
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
  CD2 long,long128,xyhit,origin_d_128;
  I64 side,ttx,tty;
  long.x=x+VIEW_DIST*cos;
  long.y=y+VIEW_DIST*sin;
  long128.x=long.x*128;
  long128.y=long.y*128;
  tx=x;
  ty=y;
  tz=Floor(origin->z);
  idx=ty*w->world_width+tx;
  for(cur=0;cur!=cnt&&!hit;cur++) {
    if(0<=tx<w->world_width)
      if(0<=ty<w->world_height) {
	relx=tx-w->things_around_camera_origin_x;
	rely=ty-w->things_around_camera_origin_y;
	if(0<=relx<2*VIEW_DIST)
	  if(0<=rely<2*VIEW_DIST) {
	    if((do_things=w->things_around_camera[relx][rely])->cnt) {
	      goto has_thing;
	    }
	}
        goto check_tile;
has_thing:;
	C3DThing *thing;
        for(thing_idx=0;thing_idx!=do_things->cnt;thing_idx++) {
	  thing=do_things->body[thing_idx];
	  if(!thing->no_draw) {
	    F64 scale=.6;
	    if(hit_texture=thing->draw_face) {
	      h=hit_texture->height/128.*scale;
	      if(!(Floor(thing->z)<=tz<=h+thing->z))
		goto next_thing;
	      F64 i1=.5,i2=.5;
	      if(SegmentSegmentIntersect(&xyhit,origin,&long128,&thing->scrn_st,&thing->scrn_en,&i1,&i2)) {
//Integer truncation is weird,make sure our hit is in the right tile
		if(ToI64(xyhit.x/128)==tx&&ToI64(xyhit.y/128)==ty) {
		  dist=i1*VIEW_DIST; //dist/128.
		  if(dist*128>hit_dist) goto next_thing;
		  h=dist*slope+origin->z;
		  h2=hit_texture->height/128.*scale;
		  if(thing->z<=h<h2+thing->z) {
		    texture_y=ClampI64((1.-(h-thing->z)/h2)*hit_texture->height,0,hit_texture->height-1);
		    if(thing->draw_flip) i2=1.-i2;
		    texture_x=ClampI64(i2*hit_texture->width,0,hit_texture->width-1);
		    color=GrPeek0(hit_texture,texture_x,texture_y);
		    if(TRANSPARENT!=color) {
		      dist*=128.; //Regular dist
		      hit=TRUE;
		      hit_dist=dist;
                      if(hit_at) *hit_at=dist;
		      if(hit_cords) {
		  	hit_cords->x=xyhit.x;
			hit_cords->y=xyhit.y;
			hit_cords->z=h-Sign(slope)*.001;
		      }
		      dist2=Sqrt(Sqr((h-origin->z)*128)+Sqr(xyhit.y-origin->y)+Sqr(xyhit.x-origin->x));
	              hit_color=Fog(color,dist2+ToBool(depth)*FOG0_DIST,fog_color);
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
          if(w->world_blocks[idx]==last_block) goto pass;
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

	origin_d_128.x=origin->x/128;
	origin_d_128.y=origin->y/128;

	side=-1;
        for(thing_idx=0;thing_idx!=4;thing_idx++) {
          if(SegmentSegmentIntersect(&xyhit,&corners[thing_idx],&corners[(thing_idx+1)&3],&origin_d_128,&long,&fsegment,&tmp)) {
            nearest=Min(nearest,tmp);
            farest=Max(farest,tmp);
	    if(nearest==tmp) {
	      side=thing_idx;
	      if(side>=2)
	        segment=(1.-fsegment)*127;
	      else
	        segment=fsegment*127;
	    }
	  }
        }

        if(farest) { //Was set to 0 above
          dist=nearest*VIEW_DIST*128;
          dist2=farest*VIEW_DIST*128;
        }

	if(ToI64(origin->x/128)==tx&&ty==ToI64(origin->y/128)) {
	  h=origin->z;
	  h2=slope*(dist2/128.)+origin->z;
	}
	else {
	  h=slope*(dist/128.)+origin->z;
	  h2=slope*(dist2/128.)+origin->z;
	}
	F64 ath=0;
	Bool hit_wall=FALSE;
	hit_texture=WhichTexture(w,idx,h,h2,&ath,&hit_wall);
	F64 hit_dist2;
        if(hit_texture) {
	  if(0<=relx<2*VIEW_DIST)
	    if(0<=rely<2*VIEW_DIST)
	      if(cnt=(do_things=w->stains_around_camera[relx][rely])->cnt)
	        goto try_stains;
	  goto try_block;
try_stains:;
          wall_stains=do_things->body;
	  wall_stain_cnt=cnt;
	  I64 sidex=0,sidey=0,sidez=0;
          while(--wall_stain_cnt>=0) {
	     wall_stain=wall_stains[wall_stain_cnt];
	     if(wall_stain->tile_x==tx&&wall_stain->tile_y==ty&&wall_stain->tile_z==tz) {
	       if(!hit_wall) {
		if(slope<0) {
		  sidez=1;
		} else
		  sidez=-1;
	       } else {
		switch(side) {
		  case 0:
		   sidey=-1;
		   break;
		  case 1:
		   sidex=1;
		   break;
		  case 2:
		   sidey=1;
		   break;
		  case 3:
		   sidex=-1;
		   break;
		}
	       }
	       if(sidez&&wall_stain->sidez==sidez) {
 	          hit_dist2=(ath-origin->z)/slope*128;
		  ttx=hit_dist2*cos+origin->x;
		  tty=hit_dist2*sin+origin->y;
	          dist=hit_dist2;
		  if(0<=GrPeek(wall_stain->dc,
			(ttx&127),
			(tty&127)
			)<TRANSPARENT) {
		    color=GrPeek(wall_stain->dc,ttx&127,tty&127);
		    goto valid_color;
		  }
	       } else if((sidex&&wall_stain->sidex==sidex)||(sidey&&wall_stain->sidey==sidey)) {
 	          color=GrPeek(wall_stain->dc,segment&127,ToI64(ath*128+texture_y_offset)&127); 
		  if(0<=color<TRANSPARENT) {
		    goto valid_color;
		  }
	       }
next_stain:;
	     }
          }
try_block:;
          CD3 new_origin;
          CD3 new_ray;
          idx=(ty*w->world_width+tx)*256+tz-I8_MIN;
	  idx=w->world_blocks[idx];
	    if(hit_wall)  {
	      SegmentSegmentIntersect(&xyhit,&corners[side],&corners[(side+1)&3],&origin_d_128,&long,NULL,NULL);
 	      color=GrPeek0(hit_texture,segment&127,ToI64(ath*128+texture_y_offset)&127);
	      //For-recursive
	      hit_dist2=Sqrt(Sqr(xyhit.x*128-origin->x)+Sqr(xyhit.y*128-origin->y))+2.;
	      new_origin.x=origin->x+hit_dist2*cos;
	      new_origin.y=origin->y+hit_dist2*sin;
	      new_origin.z=ath;
	    } else {
	      hit_dist2=(ath-origin->z)/slope*128+2.;
	      ttx=hit_dist2*cos+origin->x;
	      tty=hit_dist2*sin+origin->y;
	      dist=hit_dist2;
 	      color=GrPeek0(hit_texture,ttx&127,(tty+texture_y_offset)&127);
	      //For-recursive
	      new_origin.x=ttx;
	      new_origin.y=tty;
	      new_origin.z=hit_dist2/128.*slope+origin->z;
	    }
          if(IsLiquidTile(idx)&&depth<RAY_TRACE_MAX_DEPTH) {
	    //TODO displace ray based on "wavew"
	    fog_color=color&0xff;
	    depth++;
	    last_block=idx;
//Weird issues  with exact values
	    //Snells law
	    F64 snell_a,snell_a2,normal;
	    F64 t=Frog_tS/30.;
	    F64 rand_refrac=1.1+.1*(Abs(Sin((t/4.)*200))-Abs(Cos(t*125)))+.1*(Rand-.5)*2;
	    if(hit_wall) {
	      normal=(1+side)*pi/2;
	      snell_a=Arg(origin->x-xyhit.x*128,origin->y-xyhit.y*128)-normal;
	      snell_a=ASin(Sin(snell_a)/rand_refrac);
	      snell_a=normal-snell_a+pi;
	      new_ray.x=Sin(snell_a);
	      new_ray.y=ray->y*ASin(Sin((pi/2-ATan(slope)))/(rand_refrac+.2));
	      new_ray.z=-Cos(snell_a);
	    } else {
              if(slope<0.)
	        normal=pi/2;
	      else
	        normal=-pi/2;
	      snell_a=ATan(slope)-normal;
	      snell_a=ASin(Sin(snell_a)/rand_refrac);
	      snell_a=normal-snell_a+pi;
	      new_ray.x=ray->x;
	      new_ray.y=-Sin(snell_a);
	      new_ray.z=ray->z;
	    }
	    return GetColorForRay(man,&new_origin,&new_ray,128*VIEW_DIST,hit_at,hit_cords,depth,last_block,fog_color);
	    goto pass;
	  }
valid_color:
	  if(dist<hit_dist) {
	    dist2=Sqrt(Sqr((slope*(dist/128.)-origin->z)*128)+Sqr(cos*dist)+Sqr(sin*dist));
	    if(hit_cords) {
              //Slightly before our wall(not in wall).
	      dist=Clamp(dist-2.,0,128*VIEW_DIST);
	      hit_cords->x=origin->x+cos*dist;
	      hit_cords->y=origin->y+sin*dist;
	      hit_cords->z=slope*(dist/128.)+origin->z;
	    }
	    if(hit_at) *hit_at=dist;
            hit=TRUE;
	    hit_dist=dist;
	    hit_color=Fog(color,dist2+depth*FOG1_DIST*128,fog_color);
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
  if(depth&&!hit) {
    return gr.to_8_colors[fog_color&0xff];
  }
  return hit_color;
}
CDC *WhichTexture(C3DWorld *w,I64 tile,F64 h,F64 h2,F64 *hit_h,Bool *hit_wall) {
  F64 have,have2;
  F64 mx,mn;
  CDoor *door;
  I64 cnt;
  CDC *ret=NULL;
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
      ret=w->wall_textures[w->world_blocks[tile]];
      goto en;
    }
    if(h>h2) {
//Looking  Down
      if(h>=have2) {//Hit top
        if(hit_wall) *hit_wall=FALSE;
        if(hit_h)*hit_h=have2;
        ret=w->floor_textures[w->world_blocks[tile]];
	goto en;
      }
    }
    if(h<h2) {
      if(h2>=have) {//Hit bottom
        if(hit_wall) *hit_wall=FALSE;
        if(hit_h) *hit_h=have;
        ret=w->ceil_textures[w->world_blocks[tile]];
	goto en;
      }
    }
  }
en:
  if(ret&&(cnt=AnimDCCnt(ret)))
    return ret+ToI64(Frog_tS/ANIM_DELAY)%cnt;
  return NULL;
}

I64 mp_done=0;

//https://blog.scottlogic.com/2020/03/10/raytracer-how-to.html
//ca==Cos(-w->angle)
//sa==Sin(-w->angle)
//ca2==Cos(-w->angle2)
//sa2==Sin(-w->angle2)
U0 GenerateRay(C3DWorld *world,CD2 *ray_look,F64 i,F64 j,F64 width,F64 height,F64 ca,F64 sa,F64 ca2,F64 sa2) {
  CD3 m,tmpy,tmpx;
  D3Equ(&m,(i/width-.5)*-2,(j/height-.5)*2,1);
  D3Equ(&tmpy,
     m.x,
     m.y*ca2-m.z*sa2,
     m.y*sa2+m.z*ca2
   );
  D3Equ(ray_look,
     tmpy.x*ca+tmpy.z*sa,
     tmpy.y,
     -tmpy.x*sa+tmpy.z*ca,
   );
  D3Norm(ray_look);
}


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
  I64 idist,row;
  Bool hit_wall;
  I64 fogc;
  CD3 ray;
  F64 angle_offset_table[GR_WIDTH];
  F64 y_angle_offset_table[GR_HEIGHT];
  F64 xrot=w->angle2;
  F64 sa=Sin(-w->angle);
  F64 ca=Cos(-w->angle);
  F64 sa2=Sin(-w->angle2);
  F64 ca2=Cos(-w->angle2);
  Bool in_water=FALSE;
  F64 t=Frog_tS/30.,rand_refrac,snell_a,snell_a2;
  if(IsLiquidTile(BlockAtXYZ(w->x/128.,w->y/128.,Floor(w->cam_height)))) {
    in_water=TRUE;
  }
  idx=ToF64(Gs->num)/ToF64(mp_cnt)*GR_WIDTH;
  cap=ToF64(Gs->num+1)/ToF64(mp_cnt)*GR_WIDTH;
  for(x=idx;x<cap;x+=w->step_width) {
// divide by cos2_lookup_table to get 32 blocks from the camera
$SP,"<1>",BI=1$;



















    ptr=&to_dc->body[x];
    depth_ptr=&to_dc->depth_buf[x];
    for(y=0;y<GR_HEIGHT;y+=w->step_width) {
//Nroot has no idea what he was doing here.Literaly typing random stuff
      GenerateRay(w,&ray,x,y,GR_WIDTH,GR_HEIGHT,ca,sa,ca2,sa2);   
      if(in_water) {
	 rand_refrac=1.1+.1*(Abs(Sin((t/4.)*200))-Abs(Cos(t*125)))+.1*(Rand-.5)*2;
	 snell_a2=(y/ToF64(GR_HEIGHT)-.5)*w->fov;
         snell_a=(x/ToF64(GR_WIDTH)-.5)*w->fov;
         snell_a=ASin(Sin(snell_a)/rand_refrac)/2.;
         snell_a2=ASin(Sin(snell_a2)/(rand_refrac+.2))/2.;
         D3Equ(&ray,
	   ray.x*Cos(snell_a)+ray.z*Sin(snell_a),
	   ray.y,
	   -ray.x*Sin(snell_a)+ray.z*Cos(snell_a),
	 );
	D3Equ(&ray,
	  ray.x,
	  ray.y*Cos(snell_a2)-ray.z*Sin(snell_a2),
	  ray.y*Sin(snell_a2)+ray.z*Cos(snell_a2)
	);
//TODO what kind of liquid are we in TOODO
        fogc=LTBLUE;
      } else
	fogc=BLACK;
      p=&w->to_point[x/4][y/4];
//If we dont hit a wall,just fill with "far out in the distacnve"
      p->x=w->x+ray.x*I16_MAX;
      p->y=w->y+ray.y*I16_MAX;
      p->z=w->cam_height;
      CD3 origin;
      origin.x=w->x;
      origin.y=w->y;
      origin.z=w->cam_height;
//depth==1 to simulate going through a (liquid) block
      if(in_water) {
        color=GetColorForRay(wm,&origin,&ray,32*GRID_SZ,&dist,p,1*in_water,BlockAtXYZ(w->x/128.,w->y/128.,Floor(w->cam_height)),fogc);
      } else
        color=GetColorForRay(wm,&origin,&ray,32*GRID_SZ,&dist,p);
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
  F64 xrot=Arg(dist/128,z-w->cam_height)+w->angle2;
  z=GR_HEIGHT/2-xrot/w->fov*GR_HEIGHT;
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
//Make sure the line isnt insanely cose the the camera.
//I approximate the things based on angles,its pretty dumb.
  CD3 clip,clip2,res,res2;
  F64 angle=Arg(en->x-st->x,en->y-st->y);
  clip.x=st->x;
  clip.y=st->y;
  clip.z=st->z;
  clip2.x=en->x;
  clip2.y=en->y;
  clip2.z=en->z;

  ClipLineToCamera(w,&clip,&clip2);


  if(1.>Sqr(clip.x-w->x)+Sqr(clip.y-w->y)) {
    clip.x=32*Cos(angle)+w->x;
    clip.y=32*Sin(angle)+w->y;
  }
  if(1.>Sqr(clip2.x-w->x)+Sqr(clip2.y-w->y)) {
    clip2.x=32*Cos(angle)+w->x;
    clip2.y=32*Sin(angle)+w->y;
  }

  PointToScrn(w,clip.x,clip.y,clip.z,&res);
  PointToScrn(w,clip2.x,clip2.y,clip2.z,&res2);
  GrLine3(dc,res.x,res.y,res.z,res2.x,res2.y,res2.z);
}

U0 WallStainDel(CWallStain *s) {
  if(s->dc) AnimDCDel(s->dc);
  Free(s);
}
//
// SmallTalk Section
//
U0 FloorStainDel(CFloorStain *s) {
  if(s->dc) AnimDCDel(s->dc);
  Free(s);
}

CFrogThing *WallStainSetGr(CWallStain *self,...) {
  CFrogStr *str=argv[0];
  U8 *name=AsString(str),*raw=BlobFileGetLump("ASS",name);
  I64 x=AsF64(argv[1]),y=AsF64(argv[2]);
  CDC *loaded;
  CFrogNum *ret=FrogNumNew(0);
  if(raw) {
    if(!self->dc) {
      self->dc=AnimDCNew(128,128,frog_mem_task);
      DCFill(self->dc);
    }
    loaded=AnimDCLoad(raw);
    ret=FrogNumNew(GrBlot(self->dc,x-loaded->width/2,y-loaded->height/2,loaded)); 
    AnimDCDel(loaded);
    Free(raw);
  }
  Free(name);
  return ret;
}
AddMethod("CWallStain","addGraphics:atX:atY:",&WallStainSetGr);
CFrogThing *WorldManagerNewParticle(C3DWorldManager *man,...) {
  F64 x=AsF64(argv[0]);
  F64 y=AsF64(argv[1]);
  F64 z=AsF64(argv[2])+.001; //For not hiting floor at spawn 
  F64 spread=AsF64(argv[3]);
  F64 color=AsF64(argv[4]);
  NewParticle(w,color,16,x,y,z,spread*(Rand-.5),spread*(Rand-.5),man->gravity*3);
  return FROG_SMALL_NIL;
}

AddMethod("C3DWorldManager","basicNewParticleAtX:atY:atZ:withSpread:withColor:",&WorldManagerNewParticle);
CFrogThing *WorldManagerNewParticle2(C3DWorldManager *man,...) {
  F64 x=AsF64(argv[0]);
  F64 y=AsF64(argv[1]);
  F64 z=AsF64(argv[2])+.001; //For not hiting floor at spawn 
  F64 spread=AsF64(argv[3]);
  F64 color=AsF64(argv[4]);
  U8 *splat_lump=AsString(argv[5]);
  NewParticle(w,color,16,x,y,z,spread*(Rand-.5),spread*(Rand-.5),man->gravity*3,splat_lump);
  Free(splat_lump);
  return FROG_SMALL_NIL;
}

AddMethod("C3DWorldManager","basicNewParticleAtX:atY:atZ:withSpread:withColor:withSplatLump:",&WorldManagerNewParticle2);
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
CFrogNum *WorldManagerIsLiquid(C3DWorldManager *man,...) {
  I64 x=AsF64(argv[0]);
  I64 y=AsF64(argv[1]);
  I64 z=Floor(AsF64(argv[2]));
  I64 tile=(x+y*w->world_width)*256+z-I8_MIN;
  if(0<=tile<w->world_width*w->world_height) {
    return FrogNumNew(IsLiquidTile(w->world_blocks[tile]));
  }
  return FrogNumNew(0);
}
AddMethod("C3DWorldManager","tileIsLiquidAtX:atY:atZ:",&WorldManagerIsLiquid);

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
I64 mp_thing_done=0;
CFrogThing *UpdateParticles(C3DWorldManager *man,...) {
  I64 tx,ty;
  F64 fx,cx,fy,cy,dx,dy;
  static CFrogClass *ws_class=FrogClassNew(UniverseAddClass("CWallStain"));
  C3DParticle *head,*p,*n;
  head=&w->particles;
  for(p=head->next;head!=p;p=n) {
    n=p->next;
    if(!p->hit&&BlockAtXYZ(p->x/128,p->y/128,Floor(p->z))) {
      //Pick nearest "wall"
      fx=Floor(p->x/128.);
      cx=Ceil(p->x/128.);
      fy=Floor(p->y/128.);
      cy=Ceil(p->y/128.);
      dx=Min(cx-p->x/128.,p->x/128.-fx);
      dy=Min(cy-p->y/128.,p->y/128.-fy);
      if(dy<dx) {
	if(p->y/128-fy>.5)
	  p->y=(fy-.1)*128;
	else
	  p->y=(cy+.1)*128;
      } else {
	if(p->x/128.-fx>.5)
	  p->x=(fx-.1)*128;
	else
	  p->x=(cx+.1)*128;
      }
      if(!p->hit)
        goto hit;
    }
    if(p->momx||p->momy)
    if(C3DWorldMoveWithCollision(
	  w,
	  Arg(p->momx,p->momy),
	  Sqrt(p->momx*p->momx+p->momy*p->momy), 
	  &p->x,
	  &p->y,
	  FALSE,
	  p->z
	  )) {         
	goto hit;
    }
    if(C3DWorldMoveZWithCollision(w,p->momz,p->x,p->y,&p->z)) {
        goto hit;
    }
    p->momx*=20/30.;
    p->momy*=20/30.;
    p->momz-=.2;
    tx=p->x/GRID_SZ;
    ty=p->y/GRID_SZ;
   if(0) {
hit:
	  if(p->momz<=0.) {
 	    p->hit=1;
	    p->momx=0;
	    p->momy=0;
	    p->momz=0;
stain:
	    if(p->splat_lump_name[0]) {
	      CallScript("newStainAtX:atY:atZ:withGraphicsLump:withSpread:",ws_class,
		    FrogNumNew(p->x),
		    FrogNumNew(p->y),
		    FrogNumNew(p->z),
		    FrogStrNew(p->splat_lump_name),
		    FrogNumNew(32.)
	      );
	      p->splat_lump_name[0]=0;
	    }
	  }
        }
    if(Frog_tS>1+p->born_at) {
      QueRem(p);
      Free(p);
      w->particle_cnt--;
    }
  }
  return FROG_SMALL_NIL;
}
AddMethod("C3DWorldManager","updateParticles",&UpdateParticles);
U0 Draw3DWorld(CTask *,CDC *dc) {
  C3DWorldManager *man=FrogSymbol("world")->value;
  static CFrogClass *ws_class=FrogClassNew(UniverseAddClass("CWallStain"));
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
  C3DLine *line;
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
  C3DLine ***body;
  I64 idx;
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
    n=p->next;
    DrawParticle(w,p);
  }
  doors=man->doors->items->body;
  c=man->doors->items->cnt;
//Rely on wall commands to choose what part of door to draw
  cnt=man->lines->items->cnt;
  body=MAllocIdent(man->lines->items->body);
  for(idx=0;idx!=cnt;idx++) {
    line=body[idx];
    dc->color=line->color;
    dc->thick=line->thick;
    Line3D(w,dc,&line->x0,&line->x);
  }
  Free(body);
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
CFrogThing *WorldPhysics(C3DWorldManager *wm,...) {
  C3DThing **body=MAllocIdent(wm->things->items->body),*thing,*player;
  player=CallScript("getPlayer",wm);
  I64 c=wm->things->items->cnt,idx;
  F64 t,now=AsF64(FrogTimeNow(FROG_SMALL_NIL)->ts);
//Heres the deal.
//If we are a client,we will let the server do the physics on everyting except the player
  if(wm->is_client) {
    if(ThingHasClass(player,"CPlayer")) {
      PhysicsOnThing(w,player,wm,0.);
      player->momx2=0;
      player->momy2=0;
      player->momz2=0;
//interoplate things
      for(idx=0;idx<c;idx++) {
        thing=body[idx];
	  if(thing!=player) {
//interpolate_end_tS is the time we recived,start_tS is the frame before that
	    t=(now-thing->interpolate_end_tS)/(thing->interpolate_end_tS-thing->interpolate_start_tS);
            thing->x=Lerp(t,thing->server_old_x,thing->server_new_x);
            thing->y=Lerp(t,thing->server_old_y,thing->server_new_y);
            thing->z=Lerp(t,thing->server_old_z,thing->server_new_z);
	  }
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
	player->momz2=0;
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
CallScript("newLandscapeWithWidth:withHeight:",FrogSymbol("world")->value,FrogNumNew(64),FrogNumNew(64));
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