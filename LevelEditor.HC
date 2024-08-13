/*
THIS IS A WIP FILE!!!
*/
#include "AnimDC.HC"
#include "BlobFile.HC"
#include "SmallTalk/Set.HC";
#include "QuestEditor.HC";
extern U0 SexyCeiling(I64 x,I64 y);
F64 Lerp(F64 per,F64 min,F64 max) {
  return Clamp(min+(max-min)*per,Min(min,max),Max(max,min));
}
#define GRID_SZ 16
#define DIST_SCALE (GRID_SZ*GR_WIDTH)

#define BLOB_THINGS_ROOT "Level/Things"
#define BLOB_TILES_ROOT "Level/Tiles"

#define SEGMENT_SZ 32
#define GRID_SZ 16
#define THING_WIDTH (16*8)
#define THING_HEIGHT (32*8)
#define THING_WIDTH_SCALED 16
#define THING_HEIGHT_SCALED 32
class CLevelSegmentEditIns:CQue {
  I64 type;
  I64 xoff,yoff;
  I16 data;
  I8 height,ceil,ceil2;
};
class CLevelSegmentEditFill:CQue {
  I64 type;
  I64 xoff,yoff;
  F64 tS;
  I16 data[SEGMENT_SZ][SEGMENT_SZ];
  I8 heights[SEGMENT_SZ][SEGMENT_SZ];
  I8 ceil_heights[SEGMENT_SZ][SEGMENT_SZ];
  I8 ceil_heights2[SEGMENT_SZ][SEGMENT_SZ];
};
class CFileLevelTransition {
  U8 display_name[STR_LEN];
  U8 start_screen_blob[STR_LEN];
  U8 end_screen_blob[STR_LEN];
  U8 next_level_blob[STR_LEN];
};
//Used for 'ThingDel'/'ThingIns'
class CLevelSegmentEditThing:CQue {
  I64 type;
  F64 x,y,rot;
  I64 thing_template_idx;
};
//Used for 'DoorIns'/'DoorDel'
class CLevelSegmentEditDoor:CQue {
  I64 type;
  I64 x,y,act_as_tile;
  F64 ceil_rise;
  I32 flags;
  I32 tag; //Used when opening doors when an enemy is killed
};
class CLevelSegment:CQue {
  CLevelSegment *top,*bottom,*left,*right;
  I64 xoff,yoff;
  CQue edits;
  CQue things;
  CQue doors;
//u8[0] is the floor
  //u8[1] is the ceiliing
  I16 data[SEGMENT_SZ][SEGMENT_SZ];
  I8 heights[SEGMENT_SZ][SEGMENT_SZ];
  I8 ceil_heights[SEGMENT_SZ][SEGMENT_SZ];
  I8 ceil_heights2[SEGMENT_SZ][SEGMENT_SZ];
};

class CFileThingData {
  U8 chat_bot_name[32];
  U8 drop_item_name[32];
  U8 activate_tag[32];
  U8 pad[32];
};


class CLevelThingTemplate:CQue {
  I64 idx;
//Animation frames will be inserted in ->anim_que
  //They will share the same idx
  //ANIMATION FRAMES WILL NOT BE IN world_edit.thing_templates_que
  #define TEMPLATEF_ANIM_FRAME 1
  I64 flags;
  CQue anim_que;
  CDC *side_orig_dc;
  CDC *front_orig_dc;
  CDC *back_orig_dc;
  CDC *side_dc;
  CDC *front_dc;
  CDC *back_dc;
  U8 name[STR_LEN];
  U8 blob_side_name[STR_LEN];
  U8 blob_front_name[STR_LEN];
  U8 blob_back_name[STR_LEN];
};
class CLevelThing:CQue {
//In width of tiles
  F64 x,y,rot;
  I64 thing_template_idx;
  I64 flags;
  CFileThingData data;
};
class CLevelDoor:CQue {
  I64 x,y,act_as_tile;
  F64 ceil_rise;
  I32 flags;
  I32 tag;
};
class CLevelSegmentAddThing:CQue {
  I64 type;
  CLevelThing *t;
};
class CLevelTexture:CQue {
  I64 idx;
//These are the top dc
  CDC *orig_dc; //The unscaled DC
  CDC *dc; //The scaled DC for use with drawing the level
  CDC *wall_dc; //The scaled DC for use with drawing the lewvel
  U8 wall_blob_name[STR_LEN];
  U8 floor_blob_name[STR_LEN];
  U8 ceil_blob_name[STR_LEN];
};
#define EDITOR_TOOL_SQUARE 0b10
#define EDITOR_TOOL_CIRLCE 0b110
//See grow_force
#define EDITOR_TOOLF_RADIUS 1 //This will grow depending on the radius
class CWorldEditor {
  CDC *scrn;
  CTask *mem_task;
//In pixels,not tiles
  I64 at_x,at_y;
//Corner of screen
  I64 base_x,base_y;
  I64 w,h;
  CLevelTexture *textures[0x10000];
  CLevelThingTemplate *thing_templates[0x10000];
  CQue textures_que;
  CQue thing_templates_que;
//TEXTURE SCROLLS AREMULTIPLES OF 3 Dude
  I64 wall_texture_scroll;
  I64 ceil_texture_scroll;
//This isnt a multiple of 3 Dude
  I64 thingbar_scroll;
//Currently selected
  I64 wall_texture;
  I64 ceil_texture;
  I64 cur_thing_template_idx;
  I64 ms_x,ms_y,ms_scroll_delta;
  U8 *tooltip_text;
  CQue segments;
  CQue edits;
  CLevelTexture *edit_texture;
  CLevelThingTemplate *edit_thing_template;
  F64 grow_force,cam_height;
//Used when holding down a mouse button to not repeat operations
  CI64Set *dont_modify_tiles;
  U8 *filename;
  CFileLevelTransition level_transition;
  Bool ms_left_down;
  Bool ms_right_down;
  Bool kbd_left_down;
  Bool kbd_right_down;
  Bool kbd_up_down;
  Bool kbd_down_down;
  Bool ms_wheel_down;
  Bool ms_wheel_up;
  Bool flat_mode;
  I8 ceil_height,floor_height,ceil_height2;
} world_edit;
CDC *LoadGr(U8 *blob,U8 *name) {
  U8 *body=BlobFileGetLump(blob,name);
  CDC *dc;
  if(body) dc=AnimDCLoad(body,,world_edit.mem_task);
  else dc=DCNew(1,1,world_edit.mem_task);
  Free(body);
  return dc;
}
I64 SegmentRoundDown(I64 s) {
  return FloorI64(s,SEGMENT_SZ);
}
CLevelTexture *LoadTexture(CDC *from_dc,I64 idx) {
  I64 len,x;
  I64 greatest=0;
  CDC *scaled;
  CLevelTexture *new=CAlloc(sizeof CLevelTexture),*cur;
  if(from_dc) {
    new->orig_dc=AnimDCCopy(from_dc,world_edit.mem_task);
    scaled=ScaleDC(from_dc,GRID_SZ,GRID_SZ,world_edit.mem_task);
  } else {
    new->orig_dc=DCNew(128,128,world_edit.mem_task);
    scaled=DCNew(GRID_SZ,GRID_SZ,world_edit.mem_task);
    DCFill(scaled,TRANSPARENT);
  }

  new->idx=idx;
  new->dc=scaled;
  world_edit.textures[new->idx]=new;
  QueIns(new,&world_edit.textures_que);
  return new;
}
U0 WorldExtents(I64 *minx,I64 *maxx,I64 *miny,I64 *maxy) {
  CLevelSegment *cur=world_edit.segments.next;
  if(!QueCnt(cur)) {
    *minx=0;
    *miny=0;
    *maxx=0;
    *maxy=0;
    return;
  }
  *minx=I64_MAX;
  *miny=I64_MAX;
  *maxx=I64_MIN;
  *maxy=I64_MIN;
  while(cur!=&world_edit.segments) {
    I64 x=cur->xoff,y=cur->yoff;
    if(minx) *minx=MinI64(x,*minx);
    if(miny) *miny=MinI64(y,*miny);
    if(maxx) *maxx=MaxI64(x+SEGMENT_SZ,*maxx);
    if(maxy) *maxy=MaxI64(y+SEGMENT_SZ,*maxy);
    cur=cur->next;
  }
}
//
// DO NOT CHANGE
//
class CFilePtrLen {
  I32 ptr;
  I32 len;
};
class CFileThingTemplate {
  I16 idx;
  U8 name[STR_LEN];
  U8 data[STR_LEN];
  U8 blob_side_name[STR_LEN];
  U8 blob_front_name[STR_LEN];
  U8 blob_back_name[STR_LEN];
};

#define DOORF_SMALL_KEY 1
#define DOORF_BIG_KEY 2
#define DOORF_TO_CEILING 4
#define DOORF_SIDE_DOOR 8

class CFileDoor {
  I64 x,y,act_as_tile;
  F64 ceil_rise;
  I32 flags;
  I32 tag;
};
class CFileThing {
  U16 thing_template_idx;
//x/y are in tiles 
  F64 x,y,rot;
  CFileThingData data;
};
class CFileTexture {
  I64 idx;
  U8 floor_blob_name[STR_LEN];
  U8 wall_blob_name[STR_LEN]; 
  U8 ceil_blob_name[STR_LEN];
};
class CFileLevelTransiton {
  U8 display_name[STR_LEN];
  U8 next_level_blob[STR_LEN];
  U8 start_screen_blob[STR_LEN]; //Graphics Lump
  U8 ending_screen_blob[STR_LEN]; //Graphics Lump
};
class CWorld {
  I64 w,h;
  I64 startx,starty;
  I16 *data;
  union {
    CFileTexture *textures;
    CFilePtrLen textures_where;
  };
  union {
    CFileThingTemplate *thing_templates;
    CFilePtrLen thing_templates_where;
  };
  union {
    U8 *things;
    CFilePtrLen things_where;
  };
  CFilePtrLen heightmap;
  CFilePtrLen ceilmap;
  CFilePtrLen ceilmap2;
  CFilePtrLen world_start;
  CFilePtrLen doors;
  CFilePtrLen level_transition;
  U0 start;
}; 
U0 _DumpSegment(CWorld *world,CLevelSegment *seg) {
  I16 *ptr=world->data+((seg->xoff-world->startx)+world->w*(seg->yoff-world->starty));
  I64 x,y;
  for(y=0;y!=SEGMENT_SZ;y++) {
    for(x=0;x!=SEGMENT_SZ;x++) {
      *ptr++=seg->data[x][y];
    }
    ptr-=SEGMENT_SZ;
    ptr+=world->w;
  }
}
U0 _DumpSegmentHeight(CWorld *world,CLevelSegment *seg) {
  I8 *ptr=world->data(I8*)+sizeof(U16)*(world->h*world->w)+((seg->xoff-world->startx)+world->w*(seg->yoff-world->starty));
  I64 x,y;
  for(y=0;y!=SEGMENT_SZ;y++) {
    for(x=0;x!=SEGMENT_SZ;x++) {
      *ptr++=seg->heights[x][y];
    }
    ptr-=SEGMENT_SZ;
    ptr+=world->w;
  }
}
U0 _DumpSegmentCeil(CWorld *world,CLevelSegment *seg) {
  I8 *ptr=world->data(I8*)+3*(world->h*world->w)+((seg->xoff-world->startx)+world->w*(seg->yoff-world->starty));
  I64 x,y,h;
  for(y=0;y!=SEGMENT_SZ;y++) {
    for(x=0;x!=SEGMENT_SZ;x++) {
      h=seg->ceil_heights[x][y];
      if(seg->heights[x][y]>h) {
        *ptr++=I8_MAX;
      } else
        *ptr++=seg->ceil_heights[x][y];
    }
    ptr-=SEGMENT_SZ;
    ptr+=world->w;
  }
}
U0 _DumpSegmentCeil2(CWorld *world,CLevelSegment *seg) {
  I8 *ptr=world->data(I8*)+4*(world->h*world->w)+((seg->xoff-world->startx)+world->w*(seg->yoff-world->starty));
  I64 x,y,ch;
  for(y=0;y!=SEGMENT_SZ;y++) {
    for(x=0;x!=SEGMENT_SZ;x++) {
      ch=seg->ceil_heights[x][y];
      if(seg->heights[x][y]>ch) {
        *ptr++=0;
      } else
        *ptr++=seg->ceil_heights2[x][y];
    }
    ptr-=SEGMENT_SZ;
    ptr+=world->w;
  }
}
U0 LevelEditorExport(U8 *blob,U8 *filename) {
  I64 minx=0,miny=0,maxx=0,maxy=0,idx;
  CLevelTexture *texture;
  CLevelSegment *cur;
  CLevelThingTemplate *template;
  CLevelThing *thing;
  CLevelDoor *door;
  U8 *fptr,save,*fptr2;
  WorldExtents(&minx,&maxx,&miny,&maxy);
  I64 textures_sz=0,tsz,templates_sz=0,things_sz=0;
  I64 doors_sz=0;
  for(
        template=world_edit.thing_templates_que.next;
        template!=&world_edit.thing_templates_que;
        template=template->next) {
    templates_sz+=sizeof(CFileThingTemplate);
  }
  for(
        cur=world_edit.segments.next;
        cur!=&world_edit.segments;
        cur=cur->next) {
    things_sz+=sizeof(CFileThing)*QueCnt(&cur->things);
    doors_sz+=sizeof(CFileDoor)*QueCnt(&cur->doors);
  }
  textures_sz=sizeof(CFileTexture)*QueCnt(&world_edit.textures_que);
  I64 w=maxx-minx,h=maxy-miny;
  I64 fsz=(w*h)+(w*h)+(w*h)+2*(w*h)+sizeof(CWorld)+textures_sz+templates_sz+things_sz+doors_sz
	+sizeof(CFileLevelTransition);
  CWorld *data=CAlloc(fsz);
  data->startx=minx;
  data->starty=miny;
  data->w=w,data->h=h;
  data->data=data+1;
  data->textures=data->data(U8*)+(w*h)*5;
  data->thing_templates=data->textures(U8*)+textures_sz;
  data->things=data->thing_templates(U8*)+sizeof(CFileThingTemplate)*QueCnt(&world_edit.thing_templates_que);
  fptr2=data->things(U8*)+things_sz;
  for(cur=world_edit.segments.next;cur!=&world_edit.segments;cur=cur->next) {
    _DumpSegment(data,cur);
    _DumpSegmentHeight(data,cur);
    _DumpSegmentCeil(data,cur);
    _DumpSegmentCeil2(data,cur);
  }
  texture=world_edit.textures_que.next;
  idx=0;
  fptr=data->textures;
  for(
        texture=world_edit.textures_que.next;
        texture!=&world_edit.textures_que;
        texture=texture->next) {
    fptr(CFileTexture*)->idx=texture->idx;
    StrCpy(fptr(CFileTexture*)->wall_blob_name,texture->wall_blob_name);
    StrCpy(fptr(CFileTexture*)->floor_blob_name,texture->floor_blob_name);
    StrCpy(fptr(CFileTexture*)->ceil_blob_name,texture->ceil_blob_name);
    fptr(CFileTexture*)++;
  }
  if(fptr-data->textures(U8*)!=textures_sz)
    throw('Save');
  for(
        template=world_edit.thing_templates_que.next;
        template!=&world_edit.thing_templates_que;
        template=template->next) {
    fptr(CFileThingTemplate*)->idx=template->idx;
    StrCpy(fptr(CFileThingTemplate*)->name,template->name);
    StrCpy(fptr(CFileThingTemplate*)->blob_side_name,template->blob_side_name);
    StrCpy(fptr(CFileThingTemplate*)->blob_front_name,template->blob_front_name);
    StrCpy(fptr(CFileThingTemplate*)->blob_back_name,template->blob_back_name);
    fptr(CFileThingTemplate*)++;
  }
  if(fptr-data->thing_templates(U8*)!=sizeof(CFileThingTemplate)*QueCnt(&world_edit.thing_templates_que)) {
    throw('Save');
  }
  for(
        cur=world_edit.segments.next;
        cur!=&world_edit.segments;
        cur=cur->next) {
    for(thing=cur->things.next;thing!=&cur->things;thing=thing->next) {
      fptr(U16*)[0]=thing->thing_template_idx;
      fptr+=2;
      fptr(F64*)[0]=thing->x;
      fptr(F64*)[1]=thing->y;
      fptr(F64*)[2]=thing->rot;
      fptr(F64*)+=3;
      MemCpy(fptr,&thing->data,sizeof(CFileThingData));
      fptr(U8*)+=sizeof(CFileThingData);
    }
  }
  if(fptr-data->things(U8*)!=things_sz) {
    throw('Save');
  }
  data->doors.ptr=fptr(U8*)-data(U8*);
  data->doors.len=doors_sz;
  for(cur=world_edit.segments.next;cur!=&world_edit.segments;cur=cur->next) {
    door=cur->doors.next;
    while(door!=&cur->doors) {
      fptr(CFileDoor*)->x=door->x;
      fptr(CFileDoor*)->y=door->y;
      fptr(CFileDoor*)->act_as_tile=door->act_as_tile;
      fptr(CFileDoor*)->ceil_rise=door->ceil_rise;
      fptr(CFileDoor*)->flags=door->flags;
      fptr(CFileDoor*)->tag=door->tag;
      fptr(CFileDoor*)++;
      door=door->next;
    }
  }
  data->level_transition.ptr=fptr(U8*)-data(U8*);
  data->level_transition.len=sizeof(CFileLevelTransition);
  MemCpy(fptr,&world_edit.level_transition,sizeof (CFileLevelTransition));
  fptr+=sizeof(CFileLevelTransition);
  data->textures_where.ptr=data->textures(U8*)-data(U8*);
  data->textures_where.len=sizeof(CFileTexture)*QueCnt(&world_edit.textures_que);
  data->thing_templates_where.ptr=data->thing_templates(U8*)-data(U8*);
  data->thing_templates_where.len=sizeof(CFileThingTemplate)*QueCnt(&world_edit.thing_templates_que);
  data->things_where.ptr=data->things(U8*)-data(U8*);
  data->things_where.len=things_sz;
  data->heightmap.len=w*h;
  data->ceilmap.len=w*h;
  data->ceilmap2.len=w*h;
  data->heightmap.ptr=(data->data(U8*)-data(U8*))+sizeof(U16)*(w*h);
  data->ceilmap.ptr=data->heightmap.ptr+w*h;
  data->ceilmap2.ptr=data->ceilmap.ptr+w*h;
//  MemSet(data(U8*)+data->ceilmap.ptr,I8_MAX,w*h);
  data->world_start.len=w*h;
  data->world_start.ptr=sizeof(CWorld);
  data->data=w*h;
  BlobFileAddLump(blob,filename,data,fsz,'LEVEL');
  Free(data);
}
CLevelSegment *LevelEditorNewSegment(I64 at_x,I64 at_y) {
  at_x=SegmentRoundDown(at_x);
  at_y=SegmentRoundDown(at_y);
  CLevelSegment *new=CAlloc(sizeof(CLevelSegment),world_edit.mem_task),*cur;
  MemSet(new->ceil_heights,I8_MAX,SEGMENT_SZ*SEGMENT_SZ);
  QueInit(&new->things);
  QueInit(&new->doors);
  QueInit(&new->edits);
  QueIns(new,world_edit.segments.last);
  new->xoff=at_x;
  new->yoff=at_y;
  for(cur=world_edit.segments.next;cur!=&world_edit.segments;cur=cur->next) {
    if(cur->xoff==at_x+SEGMENT_SZ) cur->left=new;
    if(cur->xoff+SEGMENT_SZ==at_x) cur->right=new;
    if(cur->yoff==at_y+SEGMENT_SZ) cur->top=new;
    if(cur->yoff+SEGMENT_SZ==at_y) cur->bottom=new;
  }
  return new;
}
CLevelSegment *GetSegmentForPos(I64 at_x,I64 at_y) {
  static I64 at_x_cache,at_y_cache;
  static CLevelSegment *ret_cache=NULL;
  if(FloorI64(at_x,SEGMENT_SZ)==at_x_cache)
    if(FloorI64(at_y,SEGMENT_SZ)==at_y_cache)
      if(ret_cache) { 
        return ret_cache;
      }
  CLevelSegment *cur;
  for(cur=world_edit.segments.next;cur!=&world_edit.segments;cur=cur->next) {
    if(cur->xoff<=at_x<cur->xoff+SEGMENT_SZ)
      if(cur->yoff<=at_y<cur->yoff+SEGMENT_SZ) {
        ret_cache=cur;
        at_x_cache=FloorI64(at_x,SEGMENT_SZ);
        at_y_cache=FloorI64(at_y,SEGMENT_SZ);
        return cur;
      }
  }
  return NULL;
}
//direction is the amount we scroll by
//$BK,1$Returns scroll bar position percent$BK,0$
F64 SidebarScroll(I64 direction,Bool wall=TRUE) {
  CLevelTexture *texture=world_edit.textures_que.next;
//Find count of floor/wall textures
  I64 cnt=0,*cur_scroll;
  while(texture!=&world_edit.textures_que) {
    if(wall&&texture->idx>=1)
      cnt=MaxI64(texture->idx,cnt);
    else if(!wall&&texture->idx<0) {
      cnt=MaxI64(cnt,-texture->idx);
    }
    texture=texture->next;
  }
//Dude,there are 3 textures in a row
  cnt/=3;
  if(wall)
    cur_scroll=&world_edit.wall_texture_scroll;
  else
    cur_scroll=&world_edit.ceil_texture_scroll;
  if(*cur_scroll-direction<0) {
    *cur_scroll=0;
  } else if(*cur_scroll+direction>=cnt) {
    *cur_scroll=cnt;
  } else {
    *cur_scroll+=direction;
  }
  if(!cnt) return 0.0;
  return ToF64(*cur_scroll)/cnt;
}

#define SIDEBAR_WIDTH (3*(GRID_SZ+8)+16)
U0 DrawSidebar(CDC*dc,I64 x_start,Bool right_side=FALSE) {
  I64 idx,scroll,direction,y,idx2,x,color;
  F64 percent;
  CLevelTexture *t;
  U8 *str;
  dc->color=BLACK;
  GrRect(dc,x_start,0,SIDEBAR_WIDTH,GR_HEIGHT);
//Process Scroll
  if(world_edit.ms_scroll_delta&&x_start<=world_edit.ms_x<x_start+SIDEBAR_WIDTH) {
    idx=0;
    for(t=world_edit.textures_que.next;t!=&world_edit.textures_que;t=t->next) {
//idx here is the max texture index
      if(t->idx>0)
        idx=MaxI64(idx,t->idx);
    }
    idx2=world_edit.wall_texture_scroll;
    idx2=ClampI64(idx2+=3*world_edit.ms_scroll_delta,0,idx/3);
    world_edit.wall_texture_scroll=idx2;
    world_edit.ms_scroll_delta=0;
  }
  if(right_side)
    str="Right";
  else
    str="Left";
  scroll=world_edit.wall_texture_scroll;
  direction=1;
  idx=1+scroll*3;
//Draw title
  dc->color=WHITE;
  GrPutS(dc,x_start+SIDEBAR_WIDTH/2-StrLen(str)*8/2,0,str);
//Draw stuff
  for(y=16+4;y+GRID_SZ<GR_HEIGHT;y+=GRID_SZ+8) {
    for(x=x_start+8+4,idx2=0;idx2!=3;x+=GRID_SZ+8,idx2++) {
      if(!right_side) {
        if(idx==world_edit.wall_texture) {
paint_selected:
	  if(Blink)
	    color=RED;
	  else
	    color=BLUE;
	  dc->color=color;
	  GrRect(dc,x-4,y-4,GRID_SZ+8,GRID_SZ+8);
        }
      } else {
        if(idx==world_edit.ceil_texture) {
	  goto paint_selected;
        }
      }
      if(t=world_edit.textures[idx]) {
        if(world_edit.ms_left_down)
	  if(x<=world_edit.ms_x<x+8+GRID_SZ)
	    if(y<=world_edit.ms_y<y+8+GRID_SZ) {
	      Free(world_edit.tooltip_text);
	      world_edit.tooltip_text=MStrPrint("Floor:%d",t->idx);
	      if(!right_side)
	        world_edit.wall_texture=idx;
	      else
	        world_edit.ceil_texture=idx;
	    }
        if(world_edit.ms_right_down)
	  if(x<=world_edit.ms_x<x+8+GRID_SZ)
	    if(y<=world_edit.ms_y<y+8+GRID_SZ) {
edit_texture:
	      world_edit.edit_texture=t;
	    }
        dc->color=LTGRAY;
        AnimDCBlot(dc,x,y,t->dc);
      } else if(world_edit.ms_right_down)
        if(x<=world_edit.ms_x<x+8+GRID_SZ)
	  if(y<=world_edit.ms_y<y+8+GRID_SZ) {
	    t=LoadTexture(NULL,idx);
	    goto edit_texture;
	  }
      idx+=direction;
    }
  }
}

CLevelThingTemplate *CreateNewThingTemplate(I64 idx) {
  CLevelThingTemplate *template;
  template=CAlloc(sizeof(CLevelThingTemplate),world_edit.mem_task);
  QueInit(&template->anim_que);
  StrCpy(template->name,"EDIT_ME");
  template->front_orig_dc=DCNew(THING_WIDTH,THING_HEIGHT,world_edit.mem_task);
  template->back_orig_dc=DCNew(THING_WIDTH,THING_HEIGHT,world_edit.mem_task);
  template->side_orig_dc=DCNew(THING_WIDTH,THING_HEIGHT,world_edit.mem_task);
  DCFill(template->front_orig_dc,TRANSPARENT);
  DCFill(template->side_orig_dc,TRANSPARENT);
  DCFill(template->back_orig_dc,TRANSPARENT);
  template->side_dc=ScaleDC(template->side_orig_dc,
        THING_WIDTH_SCALED,
        THING_HEIGHT_SCALED,world_edit.mem_task);
  template->back_dc=ScaleDC(template->back_orig_dc,
        THING_WIDTH_SCALED,
        THING_HEIGHT_SCALED,world_edit.mem_task);
  template->front_dc=ScaleDC(template->front_orig_dc,
        THING_WIDTH_SCALED,
        THING_HEIGHT_SCALED,world_edit.mem_task);
  template->idx=idx;
  QueIns(template,&world_edit.thing_templates_que);
  world_edit.thing_templates[idx]=template;
  return template;
}
//Title+item+padding
#define THING_BAR_HEIGHT (8+4*8+8)
U0 DrawThingBar(CDC *dc,CTask *task) {
//0==front
  //1==side
  //2==back
  I64 cycle=AbsI64(__GetTicks/(JIFFY_FREQ/3))%3,idx,x,y,cap;
  U8 *title=NULL,*str;
  CDC *use_dc;
  CLevelThingTemplate *template;
  x=SIDEBAR_WIDTH+4;
  y=task->pix_height-THING_BAR_HEIGHT+8+4-16; //-16 for status bar
//Scroll
  if(world_edit.ms_scroll_delta)
    if(SIDEBAR_WIDTH<=world_edit.ms_x<task->pix_width-SIDEBAR_WIDTH) {
      world_edit.thingbar_scroll=ClampI64(
	    world_edit.thingbar_scroll+world_edit.ms_scroll_delta,
	    0,
	    I16_MAX);
    }
//
  idx=world_edit.thingbar_scroll;
  for(;x+20<=task->pix_width-SIDEBAR_WIDTH&&idx<0x10000;idx++) {
    if(world_edit.cur_thing_template_idx==idx) {
      if(Blink)
        dc->color=RED;
      else
        dc->color=BLUE;
      GrRect(dc,x-4,y-4,16+8,32+8);
    } else {
      dc->color=BLACK;
      GrRect(dc,x-4,y-4,16+8,32+8);
    }
    if(idx>=0&&(template=world_edit.thing_templates[idx])) {
      switch(cycle) {
        case 0:
	  use_dc=template->front_dc;
	  break;
        case 1:
	  use_dc=template->side_dc;
	  break;
        case 2:
	  use_dc=template->back_dc;
	  break;
      }
      GrBlot(dc,x,y,use_dc);
    }
    if(x-4<=world_edit.ms_x<x+16+8)
      if(y-4<=world_edit.ms_y<y+32+8) {
        if(template) title=template->name;
        if(world_edit.ms_left_down) {
	  if(template)
	    world_edit.cur_thing_template_idx=idx;
        } else if(world_edit.ms_right_down) {
	  if(!template)
	    template=CreateNewThingTemplate(idx);
	  world_edit.edit_thing_template=template;
        }
      }
    x+=16+4;
  }
  if(title)
    str=MStrPrint("ThingBar:%s",title);
  else
    str=MStrPrint("ThingBar");
  x=(task->pix_width-2*SIDEBAR_WIDTH)/2+SIDEBAR_WIDTH-StrLen(str)*8/2;
  y=task->pix_height-THING_BAR_HEIGHT;
  dc->color=WHITE;
  GrPutS(dc,x,y,str);
  Free(str);
}
//Centers for you
U0 DrawSubtitleForThing(CDC *dc,I64 x,I64 y,CLevelThing *thing) {
  U8 *str;
  I64 idx;
  if(Blink)
    dc->color=YELLOW;
  else dc->color=RED;
  for(idx=0;idx!=4;idx++) {
    str=NULL;
    if(thing->data.chat_bot_name[0]&&idx==0) {
      str=MStrPrint("Quest:%s",thing->data.chat_bot_name);
    } else if(idx==1&&thing->data.drop_item_name[0]) {
      str=MStrPrint("Drop:%s",thing->data.drop_item_name);
    } else if(idx==2&&thing->data.activate_tag[0]) {
      str=MStrPrint("Trigger:%s",thing->data.activate_tag);
    }
    if(str) {
      GrPutS(dc,x-StrLen(str)*4,y,str);
      y+=8;
    }
    Free(str);
  }
}
U0 DrawThingSexy(CDC *dc,I64 dispx,I64 dispy,F64 x,F64 y,CDC *thing,U8 *who=NULL) {
  CLevelSegment *segment=GetSegmentForPos(x/GRID_SZ,y/GRID_SZ);
  if(!segment) return;
  I64 height=segment->heights[ToI64(x/GRID_SZ)-segment->xoff][ToI64(y/GRID_SZ)-segment->yoff];
  if(world_edit.cam_height-height<=0) return;
  I64 idist=(world_edit.cam_height-height)*GRID_SZ,l;
  F64 width=DIST_SCALE/ToF64(idist);
  x=(x-GR_WIDTH/2+dispx)*width/16+GR_WIDTH/2;
  y=(y-GR_HEIGHT/2+dispy)*width/16+GR_HEIGHT/2;
  GrBlot(dc,x-thing->width/2,y-thing->height/2,thing); 
  y+=thing->height/2;
  if(who) DrawSubtitleForThing(dc,x,y,who);
}
U0 DrawThingDumb(CDC *dc,I64 dispx,I64 dispy,I64 x,I64 y,CDC *thing,U8 *who=NULL) {
  I64 l;
  x=x-thing->width/2+dispx;
  y=y-thing->height/2+dispy;
  GrBlot(dc,x,y,thing); 
  y+=thing->height;
  if(who) DrawSubtitleForThing(dc,x,y,who);
}
U0 DrawSegmentThings(CTask *t,CDC *dc) {
  CLevelSegment *segment=world_edit.segments.next;
  CLevelThing *thing;
  CLevelThingTemplate *template;
  I64 x,y,xspan,yspan;
  I64 tx=world_edit.base_x/GRID_SZ,ty=world_edit.base_y/GRID_SZ;
  while(segment!=&world_edit.segments) {
    thing=segment->things.next;
    while(thing!=&segment->things) {
      template=world_edit.thing_templates[thing->thing_template_idx];
      if(template->front_dc) {
        if(world_edit.flat_mode) {
	  DrawThingDumb(dc,world_edit.base_x,world_edit.base_y,thing->x*GRID_SZ,thing->y*GRID_SZ,template->front_dc,thing);
        } else 
	  DrawThingSexy(dc,world_edit.base_x,world_edit.base_y,thing->x*GRID_SZ,thing->y*GRID_SZ,template->front_dc,thing);
      }
      dc->color=WHITE;
//	  GrPutS(dc,x-StrLen(template->name)*8/2,y+16-4,template->name);
      thing=thing->next;
    }
    segment=segment->next;
  }
}
//https://stackoverflow.com/questions/40051279/affine-transform-given-4-points
U0 Persp(F64 *matrix,F64 *x,F64 *y,Bool inverse=FALSE) {
  I64 idx;
  F64 x1=x[0];
  F64 x2=x[1];
  F64 x3=x[2];
  F64 x4=x[3];
  F64 y1=y[0];
  F64 y2=y[1];
  F64 y3=y[2];
  F64 y4=y[3];
  F64 i=1;

  F64 j = (y1 - y2 + y3 - y4) / (y2 - y3);
  F64 k = (x1 - x2 + x3 - x4) / (x4 - x3);
  F64 m = (y4 - y3) / (y2 - y3);
  F64 n = (x2 - x3) / (x4 - x3);

  F64 h,g;
  if((1-m*n)==0.||y2==y3||x4==x3)
    h=0,g=0;
  else {
    h = i * (j - k * m) / (1 - m * n);
    g = i * (k - j * n) / (1 - m * n);
  }
  F64 c = x1 * i;
  F64 f = y1 * i;
  F64 a = x4 * (g + i) - x1 * i;
  F64 b = x2 * (h + i) - x1 * i;
  F64 d = y4 * (g + i) - y1 * i;
  F64 e = y2 * (h + i) - y1 * i;

  //https://stackoverflow.com/questions/63981471/how-do-i-solve-inverse-of-3x3-matrices-without-using-a-library
  if(inverse) {
    F64 xx= e * i - h * f;
    F64 yy = f * g - d * i;
    F64 zz = d * h - g * e;
    F64 det= a * xx + b * yy + c * zz;
    matrix[0]=xx;
    matrix[1]=c * h - b * i;
    matrix[2]=b * f - c * e;
    matrix[3]=yy;
    matrix[4]=a * i - c * g;
    matrix[5]=d * c - a * f;
    matrix[6]=zz;
    matrix[7]=g * b - a * h;
    matrix[8]=a * e - d * b;
    idx=9;
    while(--idx>=0)
      matrix[idx]/=det;
    return;
  }
  matrix[0]=a;
  matrix[1]=b;
  matrix[2]=c;
  matrix[3]=d;
  matrix[4]=e;
  matrix[5]=f;
  matrix[6]=g;
  matrix[7]=h;
  matrix[8]=i;
}
//https://stackoverflow.com/questions/983999/simple-3x3-matrix-inverse-code-c
U0 DrawTexturedQuad(CDC *dc,CD3I32 *poly,CDC *texture=NULL,I64 idist) {
  F64 x[4],y[4],matrix[10];
  F64 angle,plane_dist,dist;
  F64 plane_normal;
  CD2 center,point,*use1,*use2;
  I64 x2,y2,idx2;
  F64 ix,iy,ix2,iy2;
  I64 minx,miny,maxx,maxy;
  if(!texture) {
    dc->color=BLUE;
    GrFillTri0(dc,poly,poly+2,poly+1);
    GrFillTri0(dc,poly,poly+2,poly+3);
  } else {
    minx=poly[0].x;
    maxx=poly[0].x;
    miny=poly[0].y;
    maxy=poly[0].y;
    for(x2=0;x2!=4;x2++) {
      minx=MinI64(minx,poly[x2].x);
      miny=MinI64(miny,poly[x2].y);
      maxx=MaxI64(maxx,poly[x2].x);
      maxy=MaxI64(maxy,poly[x2].y);
      x[x2]=poly[x2].x;
      y[x2]=poly[x2].y;
    }
    minx=ClampI64(minx,0,GR_WIDTH);
    maxx=ClampI64(maxx,0,GR_WIDTH);
    miny=ClampI64(miny,0,GR_HEIGHT);
    maxy=ClampI64(maxy,0,GR_HEIGHT);
    Persp(matrix,x,y,TRUE); //TRUE for inverse matrix
    for(x2=minx;x2<maxx;x2++)
      for(y2=miny;y2<maxy;y2++) {
        ix=x2;
        iy=y2;
        ix2=(matrix[0]*ix+matrix[1]*iy+matrix[2]);
        iy2=(matrix[3]*ix+matrix[4]*iy+matrix[5]);
        if(0.<=ix2<1.)
	  if(0.<=iy2<1.) {
	    dc->color=GrPeek0(texture,
		  MinI64(ix2*texture->width,texture->width-1),
		  MinI64(iy2*texture->height,texture->height-1)
	    );
	    GrPlot3(dc,x2,y2,idist);
	  }
      }
  }
}
// xoff/yoff specify which wall
U0 DrawWall(CDC *dc,CDC *texture,I64 dispx,I64 dispy,I64 tx,I64 ty,I64 xoff,I64 yoff,I64 side,F64 height,I64 start_height=INVALID_PTR) {
  if(xoff&&yoff) return;
  I64 idist=(world_edit.cam_height-height)*GRID_SZ+2; //+2 to appear below tiles
  F64 width=DIST_SCALE/ToF64(idist);

  F64 h,w,width2;
  I64 x=(tx*16-GR_WIDTH/2+dispx)*width/16+GR_WIDTH/2;
  I64 y=(ty*16-GR_HEIGHT/2+dispy)*width/16+GR_HEIGHT/2;
  CLevelSegment *seg=GetSegmentForPos(tx+xoff,ty+yoff);
  if(!seg)
    return;
  if(start_height==INVALID_PTR) {
    h=seg->heights[(tx+xoff)-seg->xoff][(ty+yoff)-seg->yoff];
  } else {
    h=start_height;
  }
  width2=DIST_SCALE/((world_edit.cam_height-h)*GRID_SZ);
//Use higher wall texture for side
  if(width-width2<1.) return;
  I64 x2=((tx+xoff)*16-GR_WIDTH/2+dispx)*width2/16+GR_WIDTH/2;
  I64 y2=((ty+yoff)*16-GR_HEIGHT/2+dispy)*width2/16+GR_HEIGHT/2;
  I64 sx=x-width/2; 
  I64 sy=y-width/2; 
  I64 ex=x+width/2,ey=y+width/2;
  I64 sx2=x2-width2/2; 
  I64 sy2=y2-width2/2; 
  I64 ex2=x2+width2/2,ey2=y2+width2/2;
  CD3I32 points[4];
  points[0].z=idist;
  points[1].z=idist;
  points[2].z=idist;
  points[3].z=idist;
  if(xoff==1&&x<GR_WIDTH/2) {
    points[0].x=ex;
    points[1].x=ex;
    points[2].x=sx2; 
    points[3].x=sx2;
    points[0].y=sy;
    points[1].y=ey;
    points[2].y=ey2;
    points[3].y=sy2;
    DrawTexturedQuad(dc,points,texture,idist);
  } else if(xoff==-1&&x>GR_WIDTH/2) {
    points[0].x=sx;
    points[1].x=sx;
    points[2].x=ex2; 
    points[3].x=ex2;
    points[0].y=sy;
    points[1].y=ey;
    points[2].y=ey2;
    points[3].y=sy2;
    DrawTexturedQuad(dc,points,texture,idist);
  } else if(yoff==1&&y<GR_HEIGHT/2) {
    points[0].x=sx;
    points[1].x=ex;
    points[2].x=ex2; 
    points[3].x=sx2;
    points[0].y=ey;
    points[1].y=ey;
    points[2].y=sy2;
    points[3].y=sy2;
    DrawTexturedQuad(dc,points,texture,idist);
  } else if(yoff==-1&&y>GR_HEIGHT/2) {
    points[0].x=sx;
    points[1].x=ex;
    points[2].x=ex2; 
    points[3].x=sx2;
    points[0].y=sy;
    points[1].y=sy;
    points[2].y=ey2;
    points[3].y=ey2;
    DrawTexturedQuad(dc,points,texture,idist);
  }
}



U0 DrawTileSexy(CDC *dc,I64 dispx,I64 dispy,F64 height,CDC *top,CDC *side,I64 tx,I64 ty,I64 ceil_height2=INVALID_PTR,Bool highlight=FALSE) {
  if(world_edit.cam_height<=height+1)
    return;
  I64 idist=(world_edit.cam_height-height)*GRID_SZ,wi;
  F64 width=DIST_SCALE/ToF64(idist);
  I64 x=(tx*16-GR_WIDTH/2+dispx)*width/16+GR_WIDTH/2;
  I64 y=(ty*16-GR_HEIGHT/2+dispy)*width/16+GR_HEIGHT/2;
  I64 sx=x-width/2; 
  I64 sy=y-width/2; 
  I64 ex=x+width/2,ey=y+width/2;
  I64 xoff,yoff,c;
  U8 *base,*dst;
  I32 *depth_buf,depth=world_edit.cam_height-height;
  wi=top->width_internal;
  sx=MaxI64(sx,0);
  sy=MaxI64(sy,0);
  ex=MinI64(ex,dc->width-4);
  ey=MinI64(ey,dc->height-4);
  if(dc->flags&DCF_SCRN_BITMAP) {
    sx=MinI64(sx+dc->win_task->pix_left,dc->win_task->pix_right);
    sy=MinI64(sy+dc->win_task->pix_top,dc->win_task->pix_bottom);
    ex=MinI64(ex+dc->win_task->pix_left,dc->win_task->pix_right);
    ey=MinI64(ey+dc->win_task->pix_top,dc->win_task->pix_bottom);    
  }
//Align to 2
  sx=sx&~1;
  for(yoff=sy;yoff<ey;yoff+=2) {
    base=&top->body[ToI64((yoff-sy)/width*top->height)*wi]; 
    dst=&dc->body[dc->width_internal*yoff+sx];
    depth_buf=&dc->depth_buf[dc->width_internal*yoff+sx];
    for(xoff=sx;xoff<ex;xoff+=2) {
      if(*depth_buf>idist) {
        for(c=2;--c>=0;) {
	  dst(U16*)[0]=gr.to_8_colors[base[MinI64((xoff-sx)/width*top->width,top->width-1)]];
	  depth_buf[0]=idist;
	  depth_buf[1]=idist;
	  dst+=dc->width_internal;
	  depth_buf+=dc->width_internal;
        }
        dst-=dc->width_internal*2;
        depth_buf-=dc->width_internal*2;
      }
      depth_buf+=2;
      dst+=2;
    }
  }
  if(highlight) {
    if(Blink)
      dc->color=(TRANSPARENT<<16)|LTCYAN|ROPF_DITHER;
    else
      dc->color=(TRANSPARENT<<16)|LTRED|ROPF_DITHER;
    GrRect(dc,sx,sy,ex-sx+2,ey-sy+2);
  }
  if(side)
    for(xoff=-1;xoff<2;xoff++)
      for(yoff=-1;yoff<2;yoff++) {
        if(ceil_height2!=INVALID_PTR)
	  DrawWall(dc,side,dispx,dispy,tx,ty,xoff,yoff,side,height,ceil_height2);
        else
	  DrawWall(dc,side,dispx,dispy,tx,ty,xoff,yoff,side,height);
      }
}
U0 DrawTileDumb(CDC *dc,I64 dispx,I64 dispy,CDC *top,I64 tx,I64 ty) {
  GrBlot(dc,tx*GRID_SZ+dispx,ty*GRID_SZ+dispy,top);
}
//Returns GRID_SZ*tile cordnate
U0 MouseToPos(I64 ms_x,I64 ms_y,I64 *_x,I64 *_y) {
  I64 idist;
  F64 width;
  I64 height=0;
  F64 x;
  F64 y;
  I64 dispx=world_edit.base_x;
  I64 dispy=world_edit.base_y;
  CLevelSegment *seg;
  if(world_edit.flat_mode) {
    if(_x) *_x=ms_x-dispx;
    if(_y) *_y=ms_y-dispy;
    return;
  }
  for(height=I8_MAX;height>=I8_MIN;height--) {
    idist=(world_edit.cam_height-height)*GRID_SZ;
    width=DIST_SCALE/ToF64(idist);
    x=ToF64((ms_x+width/2-GR_WIDTH/2)*16/width-dispx+GR_WIDTH/2)/GRID_SZ;
    y=ToF64((ms_y+width/2-GR_HEIGHT/2)*16/width-dispy+GR_HEIGHT/2)/GRID_SZ;
    if(seg=GetSegmentForPos(x,y)) {
      if(seg->heights[ToI64(x)-seg->xoff][ToI64(y)-seg->yoff]==height) {
        if(_x) *_x=x*16;
        if(_y) *_y=y*16;
        return;
      }
    }
  }
//Assume new tile at 0
  idist=(world_edit.cam_height-0)*GRID_SZ;
  width=DIST_SCALE/ToF64(idist);
  x=((ms_x+width/2-GR_WIDTH/2)*16/width-dispx+GR_WIDTH/2)/16;
  y=((ms_y+width/2-GR_HEIGHT/2)*16/width-dispy+GR_HEIGHT/2)/16;
  if(_x) *_x=x*16;
  if(_y) *_y=y*16;
}
U0 DrawTitleForDoor(CDC *dc,I64 x,I64 y,CLevelDoor *door) {
  U8 *str=CAlloc(STR_LEN);
  StrCpy(str,"Door ");
  I64 idx;
  if(Blink)
    dc->color=YELLOW;
  else dc->color=RED;
  if(door->flags&DOORF_SMALL_KEY)
    CatPrint(str,"SmallKey");
  else if(door->flags&DOORF_BIG_KEY)
    CatPrint(str,"BigKey");
  else if(door->flags&DOORF_SIDE_DOOR)
    CatPrint(str,"Side");
  else if(door->tag)
    CatPrint(str,"Tag(%d)",door->tag);

  StrUtil(str,SUF_REM_SPACES);
  GrPutS(dc,x-StrLen(str)*4,y,str);
  Free(str);
}

U0 DrawDoorSexy(CDC *dc,I64 dispx,I64 dispy,CDC *top,CDC *side,I64 tx,I64 ty,F64 rise,Bool highlight=FALSE,CLevelDoor *door) {
  CLevelSegment *s=GetSegmentForPos(tx,ty);
  F64 height=s->heights[tx-s->xoff][ty-s->yoff];
  height+=rise;
  if(world_edit.cam_height<=height+1)
    return;
  I64 idist=(world_edit.cam_height-height)*GRID_SZ,wi;
  F64 width=DIST_SCALE/ToF64(idist);
  I64 x=(tx*16-GR_WIDTH/2+dispx)*width/16+GR_WIDTH/2;
  I64 y=(ty*16-GR_HEIGHT/2+dispy)*width/16+GR_HEIGHT/2;
  I64 sx=x-width/2; 
  I64 sy=y-width/2; 
  I64 ex=x+width/2,ey=y+width/2;
  I64 xoff,yoff,c;
  U8 *base,*dst;
  I32 *depth_buf,depth=world_edit.cam_height-height;
  wi=top->width_internal;
  sx=MaxI64(sx,0);
  sy=MaxI64(sy,0);
  ex=MinI64(ex,dc->width-4);
  ey=MinI64(ey,dc->height-4);
  if(dc->flags&DCF_SCRN_BITMAP) {
    sx=MinI64(sx+dc->win_task->pix_left,dc->win_task->pix_right);
    sy=MinI64(sy+dc->win_task->pix_top,dc->win_task->pix_bottom);
    ex=MinI64(ex+dc->win_task->pix_left,dc->win_task->pix_right);
    ey=MinI64(ey+dc->win_task->pix_top,dc->win_task->pix_bottom);    
  }
//Align to 2
  sx=sx&~1;
  for(yoff=sy;yoff<ey;yoff+=2) {
    base=&top->body[ToI64((yoff-sy)/width*top->height)*wi]; 
    dst=&dc->body[dc->width_internal*yoff+sx];
    depth_buf=&dc->depth_buf[dc->width_internal*yoff+sx];
    for(xoff=sx;xoff<ex;xoff+=2) {
      if(*depth_buf>idist) {
        for(c=2;--c>=0;) {
	  dst(U16*)[0]=gr.to_8_colors[base[MinI64((xoff-sx)/width*top->width,top->width-1)]];
	  depth_buf[0]=idist;
	  depth_buf[1]=idist;
	  dst+=dc->width_internal;
	  depth_buf+=dc->width_internal;
        }
        dst-=dc->width_internal*2;
        depth_buf-=dc->width_internal*2;
      }
      depth_buf+=2;
      dst+=2;
    }
  }
  if(highlight) {
    if(Blink)
      dc->color=(TRANSPARENT<<16)|LTRED|ROPF_DITHER;
    else
      dc->color=(TRANSPARENT<<16)|LTCYAN|ROPF_DITHER;
    GrRect(dc,sx,sy,ex-sx+2,ey-sy+2);
  }
  DrawTitleForDoor(dc,x,y-4,door);
  if(side)
    for(xoff=-1;xoff<2;xoff++)
      for(yoff=-1;yoff<2;yoff++)
        DrawWall(dc,side,dispx,dispy,tx,ty,xoff,yoff,side,height,height-rise);
}

U0 DrawSegmentDoors(CTask *t,CDC *dc) {
  CLevelSegment *segment=world_edit.segments.next;
  CLevelDoor *door;
  CLevelTexture *txr;
  I64 tx=world_edit.base_x/GRID_SZ,ty=world_edit.base_y/GRID_SZ,atx,aty;
  MouseToPos(world_edit.ms_x,world_edit.ms_y,&atx,&aty);
  atx=FloorI64(atx,GRID_SZ)/GRID_SZ;
  aty=FloorI64(aty,GRID_SZ)/GRID_SZ;
  while(segment!=&world_edit.segments) {
    door=segment->doors.next;
    while(door!=&segment->doors) {
      txr=world_edit.textures[door->act_as_tile];
      if(txr) {
        if(world_edit.flat_mode) {
	  ;//        DrawThingDumb(dc,world_edit.base_x,world_edit.base_y,thing->x*GRID_SZ,thing->y*GRID_SZ,template->front_dc);
        } else  
	  {
	  DrawDoorSexy(dc,world_edit.base_x,world_edit.base_y,
	        txr->dc,
	        txr->wall_dc,
	        door->x,door->y,door->ceil_rise,door->x==atx&&door->y==aty,
		door);
        }
      }
      door=door->next;
    }
    segment=segment->next;
  }
}

U0 LevelEditorDraw(CTask *t,CDC *dc) {
  CDC *main=dc;
  dc=world_edit.scrn;
  DCFill(dc,WHITE);
  DCDepthBufAlloc(dc);
  CLevelSegment *seg;
  CLevelTexture *texture;
  I64 theight,cheight,ch2;
//Tile offsets
  I64 t_xoff=world_edit.base_x/GRID_SZ,t_yoff=world_edit.base_y/GRID_SZ;
  I64 x,y,minx,maxx,miny,maxy,atx,aty;
  I64 data;
  U8 *str;
  WorldExtents(&minx,&maxx,&miny,&maxy);
  MouseToPos(world_edit.ms_x,world_edit.ms_y,&atx,&aty);
  atx=FloorI64(atx,GRID_SZ)/GRID_SZ;
  aty=FloorI64(aty,GRID_SZ)/GRID_SZ;
  for(x=minx;x!=maxx;x++) {
    for(y=miny;y!=maxy;y++) {
      seg=GetSegmentForPos(x,y);
      if(!seg) goto next;
      data=seg->data
	    [x-seg->xoff]
	    [y-seg->yoff];
//u8[0] is floor tile
      texture=world_edit.textures[data.u8[0]];
      theight=seg->heights[(x)-seg->xoff][(y)-seg->yoff];
      if(texture) {
        if(!world_edit.flat_mode) {
	  DrawTileSexy(dc,world_edit.base_x,world_edit.base_y,theight,texture->orig_dc,texture->wall_dc,x,y,,atx==x&&aty==y);
//u8[1] is ceil tile
	  texture=world_edit.textures[data.u8[1]];
	  if(Blink&&texture) {
	    cheight=seg->ceil_heights[x-seg->xoff][y-seg->yoff];
	    ch2=seg->ceil_heights2[x-seg->xoff][y-seg->yoff];
	    if(cheight!=I8_MAX&&cheight>=theight)
	      DrawTileSexy(dc,world_edit.base_x,world_edit.base_y,cheight+ch2,texture->dc,texture->wall_dc,x,y,cheight,atx==x&&aty==y);
	  }
        } else {
	  if(texture) {
	    DrawTileDumb(dc,world_edit.base_x,world_edit.base_y,texture->dc,x,y);
//u8[1] is ceil tile
	    texture=world_edit.textures[data.u8[1]];
	    cheight=seg->ceil_heights[x-seg->xoff][y-seg->yoff];
	    ch2=seg->ceil_heights2[x-seg->xoff][y-seg->yoff];
	    if(cheight!=I8_MAX&&cheight>=theight)
	      if(texture&&Blink) {
	        DrawTileDumb(dc,world_edit.base_x,world_edit.base_y,texture->dc,x,y);
	      }
	  }
        }
      }
next:;
    }
  }
  DrawSegmentThings(t,dc);
  DrawSegmentDoors(t,dc);
  DrawSidebar(dc,0);
  DrawSidebar(dc,t->pix_width-SIDEBAR_WIDTH,TRUE);
  DrawThingBar(dc,t);
  dc->color=RED;
  GrRect(dc,SIDEBAR_WIDTH,0,t->pix_width-SIDEBAR_WIDTH*2,8);
  if(Blink)
    dc->color=YELLOW;
  else
    dc->color=LTCYAN;
  GrPutS(dc,SIDEBAR_WIDTH,0,"Press F1 for help.");
  dc->color=BLUE;
  GrRect(dc,SIDEBAR_WIDTH,t->pix_height-24,t->pix_width-SIDEBAR_WIDTH*2,16);
  str=MStrPrint("Floor Height(%d),Ceil Height(%d)(Shift+Wheel == Change Ceil Height)",
        world_edit.floor_height,
        world_edit.ceil_height
        );
  dc->color=YELLOW;
  GrPutS(dc,SIDEBAR_WIDTH,t->pix_height-24,str);
  Free(str);
  GrPrint(dc,SIDEBAR_WIDTH,t->pix_height-16,"Ceil-Raise(%d)==Ctrl+Wheel", world_edit.ceil_height2);
//Draw Tile Info bar
  GrRect(dc,SIDEBAR_WIDTH,t->pix_height-8,t->pix_width-SIDEBAR_WIDTH*2,8);
  dc->color=RED;
  MouseToPos(world_edit.ms_x,world_edit.ms_y,&x,&y);
  x=FloorI64(x,GRID_SZ)/GRID_SZ;
  y=FloorI64(y,GRID_SZ)/GRID_SZ;
  seg=GetSegmentForPos(x,y);
  if(seg) {
    GrPrint(dc,SIDEBAR_WIDTH,t->pix_height-8,"Flr=%d,Ceil=%d,Rise=%d",
	  seg->heights[x-seg->xoff][y-seg->yoff],
	  seg->ceil_heights[x-seg->xoff][y-seg->yoff],
	  seg->ceil_heights2[x-seg->xoff][y-seg->yoff],
	  );
  }
  Free(dc->depth_buf);
  dc->depth_buf=NULL;
  world_edit.scrn->flags|=DCF_NO_TRANSPARENTS;
  GrBlot(main,0,0,dc);
} 
Bool EditDC(U8 *blob,U8 *name,I64 dft_w,I64 dft_h) {
//TempleOS lexer gets rid of rest of line after #include
  Bool old_flat=world_edit.flat_mode;
  world_edit.flat_mode=TRUE;
  PopUpPrint(
	"Cd(\"%Q\");\n"
	"#include \"TextureEditor.HC\";;\n"
	"StrCpy(%d,\"\");\n"
	"U8 *n=TextureEdit(\"%Q\",,%d,%d);\n"
	"if(n) StrCpy(%d,n);\n",
	__DIR__,
	name,blob,dft_w,dft_h,name);
  world_edit.flat_mode=old_flat;
  return ToBool(StrLen(name));
}
U0 EditLevelTransition(U8 *blob,CFileLevelTransition *trans) {
  Bool old_flat=world_edit.flat_mode;
  U8 *str;
  CDoc *doc=DocNew;
  world_edit.flat_mode=TRUE;
  DocPrint(doc,"$$TX+CX,\"Level Transition Editor\"$$\n");
  DocPrint(doc,"$$MU,\"Edit Name\",LE=1$$(%Q)\n",trans->display_name);
  DocPrint(doc,"$$MU,\"Edit Intro Screen\",LE=2$$(%Q)\n",trans->start_screen_blob);
  DocPrint(doc,"$$MU,\"Edit Exit Screen\",LE=3$$(%Q)\n",trans->end_screen_blob);
  DocPrint(doc,"$$MU,\"Choose Next Level\",LE=4$$(%Q)\n",trans->next_level_blob);
  switch(PopUpMenu(doc)) {
    case 1:
      str=PopUpGetStr("Level Display Name:");
      if(str) StrCpy(trans->display_name,str);
      Free(str);
      break;
    case 2:
      EditDC(blob,trans->start_screen_blob,GR_WIDTH-64,GR_HEIGHT-8);
      break;
    case 3:
      EditDC(blob,trans->end_screen_blob,GR_WIDTH-64,GR_HEIGHT-8);
      break;
    case 4:
      str=BlobFileSelect(blob);
      if(str)
        StrCpy(trans->next_level_blob,str);
      Free(str);
      break;
  }
  world_edit.flat_mode=old_flat;
  DocDel(doc);
}


class CDoorFlags {
  Bool small_key format "$$CB,\"Small Key\"$$\n";
  Bool big_key format "$$CB,\"Big Key\"$$\n";
  Bool side_door format "$$CB,\"Side Door(opened w/ other doors)\"$$\n";
  Bool to_ceiling format "$$CB,\"Rise to ceiling\"$$\n";
  I64 tag format "$$DA-TRM,A=\"Tag Number:%12d\"$$\n";
};
U0 DoorFlagsForm(CLevelDoor *door) {
  I64 ret=0;
  CDoorFlags df;
  MemSet(&df,0,sizeof CDoorFlags);
  PopUpForm(&df);
  if(df.small_key)  ret|=DOORF_SMALL_KEY;
  if(df.big_key)  ret|=DOORF_BIG_KEY;
  if(df.side_door)  ret|=DOORF_SIDE_DOOR;
  if(df.to_ceiling)  ret|=DOORF_TO_CEILING;
  door->flags=ret;
  door->tag=df.tag;
}


CLevelDoor *InsertDoor(I64 tx,I64 ty,Bool ask=FALSE,Bool undo=TRUE) {
  CLevelSegment *seg=GetSegmentForPos(tx,ty);
  CLevelDoor *d;
  CLevelSegmentEditDoor *edit_door;
  Bool old;
  if(!seg) return;
  d=seg->doors.next;
  while(d!=&seg->doors) {
    if(d->x==tx&&d->y==ty) {
      if(d->act_as_tile==world_edit.wall_texture)
        return;
      else {
        QueRem(d);
        Free(d);
        break;
      }
    }
    d=d->next;
  }
  d=CAlloc(sizeof CLevelDoor,world_edit.mem_task);
  d->x=tx;
  d->y=ty;
  d->act_as_tile=world_edit.wall_texture;
  if(ask) {
    old=world_edit.flat_mode;
    world_edit.flat_mode=TRUE;
    d->ceil_rise=PopUpRangeI64(1,16,,"Door Height");
    DoorFlagsForm(d);
    world_edit.flat_mode=old;
  } else
    d->ceil_rise=1;
  if(undo) {
    edit_door=CAlloc(sizeof(CLevelSegmentEditDoor),world_edit.mem_task);
    edit_door->type='DoorIns';
    edit_door->x=d->x;
    edit_door->y=d->y;
    edit_door->flags=d->flags;
    edit_door->ceil_rise=d->ceil_rise;
    edit_door->act_as_tile=d->act_as_tile;
    edit_door->tag=d->tag;
    QueIns(edit_door,world_edit.edits.last);
  }
  QueIns(d,seg->doors.last);
  return d;
} 
U0 AddLevelThingTemplateToBlob(U8 *blob,CLevelThingTemplate *thing) {
  U8 *path=MStrPrint("%s/NO_EDIT%d",BLOB_THINGS_ROOT,thing->idx);
  CFileThingTemplate dummy;
  MemSet(&dummy,0,sizeof CFileThingTemplate);
  dummy.idx=thing->idx;
  StrCpy(dummy.name,thing->name);
  StrCpy(dummy.blob_side_name,thing->blob_side_name);
  StrCpy(dummy.blob_front_name,thing->blob_front_name);
  StrCpy(dummy.blob_back_name,thing->blob_back_name);
  BlobFileAddLump(blob,path,&dummy,sizeof(CFileThingTemplate),'THING');
  Free(path);
}
U0 EditThingTemplate(U8 *blob,CLevelThingTemplate *template) {
enter:;
  CDoc *what=DocNew(blkdev.tmp_filename);
  CLevelThingTemplate *head,*cur;
  I64 resp,idx,len;
  U8 *str,*new,*old;
  Bool old_flat=world_edit.flat_mode;
  DocPrint(what,"$$TX+CX,\"Welcome to thing edit\"$$\n");
  DocPrint(what,"\n\n$$BT,\"Change Name\",LE=1$$\n");
  DocPrint(what,"\n\n$$BT,\"Edit Front\",LE=2$$\n");
  DocPrint(what,"\n\n$$BT,\"Edit Back\",LE=3$$\n");
  DocPrint(what,"\n\n$$BT,\"Edit Side\",LE=4$$\n");
  DocPrint(what,"\n\n$$BT,\"Use Front for All Sides\",LE=5$$\n");
  if(!StrOcc(template->name,'/')) DocPrint(what,"\n\n$$BT,\"Add State\",LE=6$$\n");
  DocPrint(what,"\n\n$$BT,\"Done\",LE=-1$$\n");
  world_edit.flat_mode=TRUE;
  resp=PopUpMenu(what);
  switch(resp) {
    case -1:
      break;
    case 1:
//Name
      str=PopUpGetStr("Thing Title:");
      head=&world_edit.thing_templates_que;
      old=StrNew(template->name);
      idx=StrLen(old);
      for(cur=head->next;cur!=head;cur=cur->next) {
        if(!StrNCmp(cur->name,old,idx)) {
	  if(cur->name[idx]==0) {// XXX
	    StrCpy(cur->name,str);
	  } else if(cur->name[idx]=='/') { // XXX/State
	    new=MStrPrint("%s%s",str,cur->name+idx);
	    StrCpy(cur->name,new);
	    Free(new);
	  }
        }
      }
      Free(str),Free(old);
      break;
    case 2:
//Front
      if(EditDC(blob,template->blob_front_name,150,275)) {
        AnimDCDel(template->front_orig_dc);
        template->front_orig_dc=LoadGr(blob,template->blob_front_name);
        AnimDCDel(template->front_dc);
        template->front_dc=ScaleDC(template->front_orig_dc,
	      THING_WIDTH_SCALED,
	      THING_HEIGHT_SCALED,world_edit.mem_task);
      }
      break;
    case 3:
//Back
      if(EditDC(blob,template->blob_back_name,150,275)) {
        AnimDCDel(template->back_orig_dc);
        template->back_orig_dc=LoadGr(blob,template->blob_back_name);
        template->back_dc=ScaleDC(template->back_orig_dc,
	      THING_WIDTH_SCALED,
	      THING_HEIGHT_SCALED,world_edit.mem_task);
      }
      break;
    case 4:
//Side
      if(EditDC(blob,template->blob_side_name,150,275)) {
        AnimDCDel(template->side_orig_dc);
        template->side_orig_dc=LoadGr(blob,template->blob_side_name);
        template->side_dc=ScaleDC(template->side_orig_dc,
	      THING_WIDTH_SCALED,
	      THING_HEIGHT_SCALED,world_edit.mem_task);
      }
      break;
    case 5:
//Use front for all sides
      AnimDCDel(template->side_orig_dc);
      AnimDCDel(template->back_orig_dc);
      AnimDCDel(template->side_dc);
      AnimDCDel(template->back_dc);
      StrCpy(template->blob_side_name,template->blob_front_name);
      StrCpy(template->blob_back_name,template->blob_front_name);
      template->side_dc=AnimDCCopy(template->front_dc,world_edit.mem_task);
      template->back_dc=AnimDCCopy(template->front_dc,world_edit.mem_task);
      template->side_orig_dc=AnimDCCopy(template->front_orig_dc,world_edit.mem_task);
      template->back_orig_dc=AnimDCCopy(template->front_orig_dc,world_edit.mem_task);
      break;
    case 6:
      DocDel(what);
      what=DocNew;
      DocPrint(what,"$$TX+CX,\"What State\"$$:\n\n");
      head=&world_edit.thing_templates_que;
      for(cur=head->next;cur!=head;cur=cur->next) {
        len=StrLen(template->name);
        if(!StrNCmp(template->name,cur->name,len)) {
	  if(cur->name[len]=='/')
	    DocPrint(what,"$$BLUE$$$$MU,\"State:%s\",LE=%d$$$$FD$$\n",cur->name,cur);
        }
      }
      DocPrint(what,"$$RED$$$$MU,\"NEW STATE\",LE=%d$$$$FD$$\n",INVALID_PTR);
      resp=PopUpMenu(what);
      if(resp==DOCM_CANCEL)
        break;
      else if(resp==INVALID_PTR) {
        str=PopUpGetStr("New state name:");
        for(idx=I16_MAX/2;idx<I16_MAX;idx++) {
	  if(!world_edit.thing_templates[idx]) {
	    cur=CreateNewThingTemplate(idx);
	    StrPrint(cur->name,"%s/%s",template->name,str);
	    Free(str);
	    DocDel(what);
	    template=cur;
	    goto enter;
	  }
        }
        Free(str);
      } else {
        DocDel(what);
        template=resp;
        goto enter;
      }
      break;
  }
  AddLevelThingTemplateToBlob(blob,template);
  DocDel(what);
  world_edit.flat_mode=old_flat;
}
U0 FreeEditorData() {
  CLevelTexture *texture;
  CLevelSegment *segment;
  CLevelThingTemplate *template;
  Free(world_edit.filename);

  template=world_edit.thing_templates_que.next;
  while(template!=&world_edit.thing_templates_que) {
    AnimDCDel(template->front_dc);
    AnimDCDel(template->back_dc);
    AnimDCDel(template->side_dc);
    AnimDCDel(template->front_orig_dc);
    AnimDCDel(template->back_orig_dc);
    AnimDCDel(template->side_orig_dc);
    template=template->next;
  }
  QueDel(&world_edit.thing_templates_que);

  texture=world_edit.textures_que.next;
  while(texture!=&world_edit.textures_que) {
    AnimDCDel(texture->orig_dc);
    AnimDCDel(texture->dc);
    texture=texture->next;
  }
  QueDel(&world_edit.textures_que);

  segment=world_edit.segments.next;
  while(segment!=&world_edit.segments) {
    QueDel(&segment->things);
    segment=segment->next;
  }
  QueDel(&world_edit.segments);
  QueDel(&world_edit.edits);
  QueInit(&world_edit.segments);
  QueInit(&world_edit.edits);
  QueInit(&world_edit.textures_que);
  QueInit(&world_edit.thing_templates_que);
  MemSetI64(world_edit.textures,NULL,0x10000);
  MemSetI64(world_edit.thing_templates,NULL,0x10000);
  MemSet(&world_edit.level_transition,0,sizeof(CFileLevelTransition));
}
U0 WorldInsertTileAt(I64 x,I64 y,I64 thing,I64 floor_ceil_ceil2=0) {
  CLevelSegment *seg=GetSegmentForPos(x,y);
  if(!seg) {
    if(!thing) return;
    seg=LevelEditorNewSegment(x,y);
  }
  x-=seg->xoff;
  y-=seg->yoff;
  if(!floor_ceil_ceil2)
    seg->data[x][y].u8[0]=AbsI64(thing);
  else
    seg->data[x][y].u8[1]=AbsI64(thing);
  if(floor_ceil_ceil2==2) {
    seg->ceil_heights2[x][y]=world_edit.ceil_height2;
  } else if(floor_ceil_ceil2==1) {
    seg->ceil_heights[x][y]=world_edit.ceil_height;
  } else  {
//If we insert a floor,reset the ceil
    seg->ceil_heights[x][y]=I8_MAX;
    seg->ceil_heights2[x][y]=0;
    seg->heights[x][y]=world_edit.floor_height;
  }
}
I64 WorldGetTileAt(I64 x,I64 y) {
  CLevelSegment *seg=GetSegmentForPos(x,y);
  if(!seg)
    return 0;
  x-=seg->xoff;
  y-=seg->yoff;
  return seg->data[x][y];
}
I64 WorldGetCeilAt(I64 x,I64 y) {
  CLevelSegment *seg=GetSegmentForPos(x,y);
  if(!seg)
    return I8_MAX;
  x-=seg->xoff;
  y-=seg->yoff;
  return seg->ceil_heights[x][y];
}
I64 WorldGetHeightAt(I64 x,I64 y) {
  CLevelSegment *seg=GetSegmentForPos(x,y);
  if(!seg)
    return I8_MAX;
  x-=seg->xoff;
  y-=seg->yoff;
  return seg->heights[x][y];
}
I64 WorldGetCeilRiseAt(I64 x,I64 y) {
  CLevelSegment *seg=GetSegmentForPos(x,y);
  if(!seg)
    return 0;
  x-=seg->xoff;
  y-=seg->yoff;
  return seg->ceil_heights2[x][y];
}
U0 LoadLevelThingTemplatesFromBlob(U8 *blob) {
  CBlobFileHeader *data=GetBlobFileData(blob); //Dont Free
  CLumpHeader *lump=data->lump_table;
  CFileThingTemplate *f_template;
  CLevelThingTemplate *template;
  I64 idx=data->lump_cnt;
  while(--idx>=0) {
    if(!StrNCmp(lump->name,BLOB_THINGS_ROOT,StrLen(BLOB_THINGS_ROOT))) {
      f_template=data(U8*)+lump->offset;
      template=CreateNewThingTemplate(f_template->idx);
      template->front_orig_dc=LoadGr(blob,f_template->blob_front_name);
      template->back_orig_dc=LoadGr(blob,f_template->blob_back_name);
      template->side_orig_dc=LoadGr(blob,f_template->blob_side_name);
      StrCpy(template->blob_side_name,f_template->blob_side_name);
      StrCpy(template->blob_front_name,f_template->blob_front_name);
      StrCpy(template->blob_back_name,f_template->blob_back_name);
      template->side_dc=ScaleDC(template->side_orig_dc,
	  THING_WIDTH_SCALED,
	  THING_HEIGHT_SCALED,world_edit.mem_task);
      template->back_dc=ScaleDC(template->back_orig_dc,
	  THING_WIDTH_SCALED,
	  THING_HEIGHT_SCALED,world_edit.mem_task);
      template->front_dc=ScaleDC(template->front_orig_dc,
	  THING_WIDTH_SCALED,
	  THING_HEIGHT_SCALED,world_edit.mem_task);
      StrCpy(template->name,f_template->name);
    }
    lump++;
  }
}
U0 LoadWorld(U8 *blob,U8 *filename) {
  U8 *str;
  U8 *textures;
  U8 *templates;
  I8 *heightmap;
  I8 *ceilmap;
  I8 *ceilmap2;
  I64 width,height,cap;
  I64 x,y,oldf=world_edit.floor_height,oldc=world_edit.ceil_height;
  I64 och2=world_edit.ceil_height2;
  I64 sx,sy;
  U64 type;
  CDC *odc;
  I64 tsz;
  I64 data;
  CLevelThingTemplate *template;
  CFileTexture *f_texture;
  CFileThingTemplate *f_template;
  CFileThing *f_thing,*things;
  CLevelThing *thing;
  CLevelSegment *segment;
  CLevelTexture *texture;
  CFileDoor *doors;
  CLevelDoor *door;
  CWorld *w=NULL;
  Bool old_flat=world_edit.flat_mode;
  world_edit.flat_mode=TRUE;
  w=BlobFileGetLump(blob,filename,,&type);
  if(!w||type!='LEVEL') {
    PopUpOk(str=MStrPrint("Can't open world %s!!!",filename));
    Free(str);
    goto fail;
  }
  world_edit.flat_mode=old_flat;
  FreeEditorData;
  LoadLevelThingTemplatesFromBlob(blob);
  world_edit.filename=StrNew(filename);
  width=w->w;
  height=w->h;
  w->data=w(U8*)+w->world_start.ptr;
  doors=w(U8*)+w->doors.ptr;
  textures=w(U8*)+w->textures_where.ptr;
  templates=w(U8*)+w->thing_templates_where.ptr;
  heightmap=w(U8*)+w->heightmap.ptr;
  ceilmap=w(U8*)+w->ceilmap.ptr;
  ceilmap2=w(U8*)+w->ceilmap2.ptr;
  sx=w->startx;
  sy=w->starty;
  for(x=0;x!=width;x++)
    for(y=0;y!=height;y++) {
      world_edit.ceil_height=ceilmap[x+y*width];
      world_edit.floor_height=heightmap[x+y*width];
      world_edit.ceil_height2=ceilmap2[x+y*width];
      data=w->data[x+y*width];
      WorldInsertTileAt(x+sx,y+sy,data.u8[0]);
      WorldInsertTileAt(x+sx,y+sy,data.u8[1],1);
      WorldInsertTileAt(x+sx,y+sy,data.u8[1],2);
    }
  cap=w->doors.len/sizeof (CFileDoor);
  while(--cap>=0) {
    world_edit.wall_texture=doors[cap].act_as_tile;
    door=InsertDoor(doors[cap].x,doors[cap].y,,FALSE);
    door->ceil_rise=doors[cap].ceil_rise;
    door->flags=doors[cap].flags;
    door->tag=doors[cap].tag;
  }
  f_texture=textures;
  cap=w->textures_where.len;
  while(f_texture<textures(U8*)+cap) {
    str=LoadGr(blob,f_texture->floor_blob_name);
    texture=LoadTexture(str,f_texture->idx);
    Free(str);
    StrCpy(texture->wall_blob_name,f_texture->wall_blob_name);
    StrCpy(texture->floor_blob_name,f_texture->floor_blob_name);
    StrCpy(texture->ceil_blob_name,f_texture->ceil_blob_name);
    str=LoadGr(blob,f_texture->wall_blob_name);
    if(str) {
      texture->wall_dc=ScaleDC(str,GRID_SZ,GRID_SZ,world_edit.mem_task);
      AnimDCDel(str);
    }
    f_texture++;
  }
  f_template=templates;
  cap=w->thing_templates_where.len;
  //Now unused
  things=f_thing=w->things_where.ptr+w(U8*);
  cap=w->things_where.len;
  while(f_thing<things(U8*)+cap) {
    segment=GetSegmentForPos(f_thing->x,f_thing->y);
    if(segment) {
      thing=CAlloc(sizeof(CLevelThing),world_edit.mem_task);
      thing->x=f_thing->x;
      thing->y=f_thing->y;
      thing->rot=f_thing->rot;
      thing->thing_template_idx=f_thing->thing_template_idx;
      MemCpy(&thing->data,&f_thing->data,sizeof(CFileThingData));
      QueIns(thing,&segment->things);
    }
    f_thing++;
  }

  MemCpy(&world_edit.level_transition,w->level_transition.ptr+w(U8*),sizeof (CFileLevelTransition));
fail: 
  Free(w);
  world_edit.floor_height=oldf;
  world_edit.ceil_height=oldc;
  world_edit.ceil_height2=och2;
}
class CFloodFillAt {
  I64 at_x,at_y;
};
I16 *GetTilePtrAt(I64 at_x,I64 at_y) {
  CLevelSegment *seg=GetSegmentForPos(at_x,at_y);
  if(!seg) return NULL;
  return &seg->data[at_x-seg->xoff][at_y-seg->yoff];
}
I8 *GetHeightPtrAt(I64 at_x,I64 at_y) {
  CLevelSegment *seg=GetSegmentForPos(at_x,at_y);
  if(!seg) return NULL;
  return &seg->heights[at_x-seg->xoff][at_y-seg->yoff];
}
I8 *GetCeilPtrAt(I64 at_x,I64 at_y) {
  CLevelSegment *seg=GetSegmentForPos(at_x,at_y);
  if(!seg) return NULL;
  return &seg->data[at_x-seg->xoff][at_y-seg->yoff].i8[1];
}
I8 *GetCeilHeightPtrAt(I64 at_x,I64 at_y) {
  CLevelSegment *seg=GetSegmentForPos(at_x,at_y);
  if(!seg) return NULL;
  return &seg->ceil_heights[at_x-seg->xoff][at_y-seg->yoff];
}
I8 *GetCeilHeight2PtrAt(I64 at_x,I64 at_y) {
  CLevelSegment *seg=GetSegmentForPos(at_x,at_y);
  if(!seg) return NULL;
  return &seg->ceil_heights2[at_x-seg->xoff][at_y-seg->yoff];
}
//target_height==I64_MAX for ignore height
U0 FloodFill(I64 at_x,I64 at_y,I64 with,I64 target_tile=I16_MAX,I64 target_height=I64_MAX,I64 height=0,F64 ts=-1,Bool add_undo=TRUE,Bool ceil=FALSE) {
  CI64Set *done_segments=I64SetNew;
  CLevelSegment *segment=GetSegmentForPos(at_x,at_y),*other_segment;
  if(!segment) return;
  I64 stk_sz=0x100000,stk_ptr=0,x,y,xo,yo;
  I16 *ptr;
  CFloodFillAt *stk;
  CLevelSegmentEditFill *edit_ff;
  if(target_tile==I64_MAX) target_tile=segment->data[at_x-segment->xoff][at_y-segment->yoff];
  else if(target_tile!=segment->data[at_x-segment->xoff][at_y-segment->yoff]) return;
  stk=CAlloc(stk_sz*sizeof(CFloodFillAt));
  if(target_tile==with)
    goto fin;
  if(ts<0.) ts=tS;
  if(add_undo) {
    edit_ff=CAlloc(sizeof(CLevelSegmentEditFill));
    edit_ff->tS=ts;
    edit_ff->xoff=at_x;
    edit_ff->yoff=at_y;
    edit_ff->type='FldFill';
    stk[stk_ptr].at_x=at_x;
    MemCpy(edit_ff->data,segment->data,2*SEGMENT_SZ*SEGMENT_SZ);
    MemCpy(edit_ff->heights,segment->heights,SEGMENT_SZ*SEGMENT_SZ);
    MemCpy(edit_ff->ceil_heights,segment->ceil_heights,SEGMENT_SZ*SEGMENT_SZ);
    MemCpy(edit_ff->ceil_heights2,segment->ceil_heights2,SEGMENT_SZ*SEGMENT_SZ);
    QueIns(edit_ff,world_edit.edits.last);
  }
  stk[stk_ptr].at_y=at_y;
  stk_ptr++;
  while(stk_ptr) {
    stk_ptr--;
    at_x=stk[stk_ptr].at_x;
    at_y=stk[stk_ptr].at_y;
    if(GetTilePtrAt(at_x,at_y)) {
      if(!ceil) {
        *GetTilePtrAt(at_x,at_y)=with;
        *GetHeightPtrAt(at_x,at_y)=height;
      } else {
        *GetCeilPtrAt(at_x,at_y)=with;
        *GetCeilHeightPtrAt(at_x,at_y)=height;
        *GetCeilHeight2PtrAt(at_x,at_y)=world_edit.ceil_height2;
      }
      if(stk_sz<=stk_ptr+4) {
        FloodFill(at_x+1,at_y,with,target_tile,target_height,height,ts,add_undo,ceil);
        FloodFill(at_x-1,at_y,with,target_tile,target_height,height,ts,add_undo,ceil);
        FloodFill(at_x,at_y-1,with,target_tile,target_height,height,ts,add_undo,ceil);
        FloodFill(at_x,at_y+1,with,target_tile,target_height,height,ts,add_undo,ceil);
        goto next;
      }
      for(xo=-1;xo!=2;xo++)
        for(yo=-1;yo!=2;yo++) {
	  if(xo^^yo) {
	    if(ptr=GetTilePtrAt(at_x+xo,at_y+yo)) {
	      if(*ptr==target_tile&&
		(target_height==*GetHeightPtrAt(at_x+xo,at_y+yo)
		  ||target_height==I64_MAX)) {
		other_segment=GetSegmentForPos(at_x+xo,at_y+yo);
	        if(other_segment!=segment&&!I64SetHas(done_segments,other_segment)) {
		  I64SetAdd(done_segments,other_segment);
		  FloodFill(at_x+xo,at_y+yo,with,target_tile,target_height,height,ts,add_undo,ceil);
	        } else {
		  stk[stk_ptr].at_x=at_x+xo;
		  stk[stk_ptr].at_y=at_y+yo;
		  stk_ptr++;
	        }
	      }
	    }

	  }
        }
    }
next:
  }
fin:
  I64SetDel(done_segments);
  Free(stk);
}
U0 HelpMenu() {
  Bool old_flat=world_edit.flat_mode;
  CDoc *doc=DocNew;
  world_edit.flat_mode=TRUE;
  DocPrint(doc,"$$PURPLE$$$$TX+CX,\"Level Editor Help!\"$$$$FD$$\n");
  DocPrint(doc,"\n  See $$LK,\"(This)\",A=\"FI:Help/LevelEditor.DD\"$$ for the general gist of things\n");
  DocPrint(doc,"$$TR-C,\"Level Controls\"$$\n$$ID,2$$\n");
  DocPrint(doc,"$$PURPLE$$[f]$$FD$$ - Flood fill the floor with a tile\n");
  DocPrint(doc,"$$PURPLE$$[s]$$FD$$ - Sexy ceiling maker(make sure ceiling exists)\n");
  DocPrint(doc,"$$PURPLE$$[d]$$FD$$ - Make a door\n");
  DocPrint(doc,"$$PURPLE$$[Shift+d]$$FD$$ - Remove a door\n");
  DocPrint(doc,"$$PURPLE$$[Left-Click]$$FD$$ - Place tile\n");
  DocPrint(doc,"$$PURPLE$$[Right-Click]$$FD$$ - Place ceiling\n");
  DocPrint(doc,"$$PURPLE$$[Shift+Right-Click]$$FD$$ - Remove ceiling/thing\n");
  DocPrint(doc,"$$PURPLE$$[Shift+Left-Click]$$FD$$ - Place thing\n");
  DocPrint(doc,"$$PURPLE$$[q]$$FD$$ - Edit Quest on thing\n");
  DocPrint(doc,"$$PURPLE$$[Ctrl+z]$$FD$$ - Undo\n");
  DocPrint(doc,"$$ID,-2$$\n");
  DocPrint(doc,"$$TR-C,\"Height Controls\"$$\n$$ID,2$$\n");
  DocPrint(doc,"$$PURPLE$$[Mouse-Wheel]$$FD$$ - Change floor height\n");
  DocPrint(doc,"$$PURPLE$$[Shift+Mouse-Wheel]$$FD$$ - Change ceil height\n");
  DocPrint(doc,"$$PURPLE$$[Ctrl+Mouse-Wheel]$$FD$$ - Change ceil rise\n");
  DocPrint(doc,"$$ID,-2$$\n");
  DocPrint(doc,"$$TR-C,\"Camera Controls\"$$\n$$ID,2$$\n");
  DocPrint(doc,"$$PURPLE$$[PageUp]$$FD$$ - Move camera up\n");
  DocPrint(doc,"$$PURPLE$$[PageDown]$$FD$$ - Move camera down\n");
  DocPrint(doc,"$$PURPLE$$[Shift+f]$$FD$$ - Toggle flat view-mode\n");
  DocPrint(doc,"$$PURPLE$$[Arrow keys]$$FD$$ - What do you think they do?\n");
  DocPrint(doc,"$$ID,-2$$\n");
  PopUpMenu(doc);
  world_edit.flat_mode=old_flat;
  DocDel(doc);
}
I64 WallCeilFloor() {
  CDoc *doc=DocNew;
  DocPrint(doc,"$$TX+CX,\"Wall,Ceil or Floor texture?\"$$\n");
  DocPrint(doc,"\n\n$$BT+CX,\"Wall\",LE=1$$\n\n");
  DocPrint(doc,"\n\n$$BT+CX,\"Floor\",LE=0$$\n\n");
  DocPrint(doc,"\n\n$$BT+CX,\"Ceil\",LE=2$$\n\n");
  Bool old_flat=world_edit.flat_mode;
  world_edit.flat_mode=TRUE;
  I64 wall=PopUpMenu(doc);
  world_edit.flat_mode=old_flat;
  DocDel(doc);
  return wall;
}
Bool IsUndoNecescary(CLevelSegmentEditIns *ins) {
  CLevelSegment *seg=GetSegmentForPos(ins->xoff,ins->yoff);
  if(!seg) return TRUE;
  I64 x=ins->xoff-seg->xoff;
  I64 y=ins->yoff-seg->yoff;
  if(ins->type=='Insert') {
    if(ins->height!=seg->heights[x][y]||
	  ins->ceil!=seg->ceil_heights[x][y]||
	  ins->ceil2!=seg->ceil_heights2[x][y]||
	  ins->data!=seg->data[x][y]
    )
      return TRUE;
    return FALSE;
  }
  return TRUE;
}
U0 WorldEditUndo() {
  CLevelSegmentEditFill *ff,*ff2;
  CLevelSegmentEditThing *thing;
  CLevelSegmentEditIns *ins,*ins2;
  CLevelThing *new_thing;
  CLevelSegment *seg;
  CLevelSegmentEditDoor *door;
  CLevelDoor *new_door;
  I64 x,y,cnt;
  if(!(cnt=QueCnt(&world_edit.edits)))
    return;
  ff=world_edit.edits.last;
  ins=ff;
  QueRem(ff);
  if(ins->type=='DoorIns') {
    door=ins;
    if(seg=GetSegmentForPos(door->x,door->y)) {
      for(new_door=seg->doors.next;new_door!=&seg->doors;new_door=new_door->next) {
        if(new_door->x==door->x&&
	      new_door->y==door->y) {
	  QueRem(new_door);
	  Free(new_door);
	  break;
        }
      }
    }
  } else if(ins->type=='DoorDel') {
    door=ins;
    if(seg=GetSegmentForPos(door->x,door->y)) {
      for(new_door=seg->doors.next;new_door!=&seg->doors;new_door=new_door->next) {
        if(new_door->x==door->x&&
	      new_door->y==door->y) {
	  QueRem(new_door);
	  Free(new_door);
	  break;
        }
      }
    }
    new_door=InsertDoor(door->x,door->y,FALSE,FALSE);
    new_door->act_as_tile=door->act_as_tile;
    new_door->flags=door->flags;
    new_door->ceil_rise=door->ceil_rise;
  } else if(ins->type=='ThingIns') {
    thing=ins;
    if(seg=GetSegmentForPos(Floor(thing->x),Floor(thing->y))) {
      for(new_thing=seg->things.next;new_thing!=&seg->things;new_thing=new_thing->next) {
        if(new_thing->x==thing->x&&
	      new_thing->y==thing->y&&
	      new_thing->rot==thing->rot&&
	      new_thing->thing_template_idx==thing->thing_template_idx) {
	  QueRem(new_thing);
	  Free(new_thing);
	  break;
        }
      }
    }
  } else if(ins->type=='ThingDel') {
    thing=ins;
    if(seg=GetSegmentForPos(Floor(thing->x),Floor(thing->y))) {
      new_thing=CAlloc(sizeof(CLevelThing),world_edit.mem_task);
      new_thing->x=thing->x;
      new_thing->y=thing->y;
      new_thing->rot=thing->rot;
      new_thing->thing_template_idx=thing->thing_template_idx;
      QueIns(new_thing,seg->things.last);
    }
  } else if(ins->type=='Insert') {
    seg=GetSegmentForPos(ins->xoff,ins->yoff);
    if(seg) {
      x=ins->xoff-seg->xoff;
      y=ins->yoff-seg->yoff;
      seg->heights[x][y]=ins->height;
      seg->ceil_heights[x][y]=ins->ceil;
      seg->ceil_heights2[x][y]=ins->ceil2;
      seg->data[x][y]=ins->data;
    }
//Check for "same" edits(maybe we held down the mouse button)
    --cnt;
    while(--cnt>=0) {
      ins2=world_edit.edits.last;
      if(ins2->xoff==ins->xoff&&
	    ins2->yoff==ins->yoff&&
	    ins2->ceil==ins->ceil&&
	    ins2->ceil2==ins->ceil2&&
	    ins2->height==ins->height&&
	    ins2->data==ins->data) {
        seg->heights[x][y]=ins2->height;
        seg->ceil_heights[x][y]=ins2->ceil;
        seg->ceil_heights2[x][y]=ins2->ceil2;
        seg->data[x][y]=ins2->data;
        QueRem(ins2);
        Free(ins2);
      } else
        break;
    } 
  } else if(ins->type=='FldFill') {
    seg=GetSegmentForPos(ins->xoff,ins->yoff);
    MemCpy(seg->ceil_heights2,ff->ceil_heights2,SEGMENT_SZ*SEGMENT_SZ);
    MemCpy(seg->ceil_heights,ff->ceil_heights,SEGMENT_SZ*SEGMENT_SZ);
    MemCpy(seg->heights,ff->heights,SEGMENT_SZ*SEGMENT_SZ);
    MemCpy(seg->data,ff->data,2*SEGMENT_SZ*SEGMENT_SZ);
    if(cnt>=2) {
      ff2=world_edit.edits.last;
      if(ff2->tS==ff->tS&&ff->type==ff2->type)
        WorldEditUndo;
    }
  }
  Free(ff);
}
Bool I64SetHas(CI64Set *set,I64 s) {
  I64 i=set->cnt;
  while(--i>=0) if(set->body[i]==s) return TRUE;
  return FALSE;
}
class CFillOpts {
  Bool same_height format "$$CB,\"Same Height\"$$\n";
  Bool ceil format "$$CB,\"Fill Ceiling\"$$\n";
};
U0 WorldEdit(U8 *blob,U8 *filename=NULL) {
  I64 m1,m2;
  I64 tx,ty;
  I64 ch2,old;
  I64 activate;
  U64 type;
  I64 idx,idx2;
  I64 tile; //i32[0]==x,.i32[1]==y
  I64 last_wheel=ms.pos.z;
  CFillOpts fill_opts;
  CLevelSegmentEditDoor *edit_door;
  CLevelTexture *texture;
  CLevelSegment *segment;
  CLevelThingTemplate *thingt;
  CLevelThing *thing;
  CLevelSegmentEditThing *edit_thing;
  CLevelSegmentEditIns *edit_ins;
  CLevelDoor *door;
  U8 *str;
  Bool continue=TRUE,*which_key,floor_fill=FALSE;
  Bool old_flat;
  MemSet(&world_edit,0,sizeof(CWorldEditor));
  world_edit.cam_height=16;
  world_edit.ceil_height=10;
  world_edit.ceil_height2=1;
  world_edit.mem_task=Fs;
  QueInit(&world_edit.textures_que);
  QueInit(&world_edit.thing_templates_que);
  QueInit(&world_edit.segments);
  QueInit(&world_edit.edits);
  world_edit.dont_modify_tiles=I64SetNew;
  SettingsPush;
  WinBorder;
  WinMax;
  DocClear;
  if(filename)
    world_edit.filename=StrNew(filename);
  LoadLevelThingTemplatesFromBlob(blob);
  world_edit.scrn=DCNew(GR_WIDTH,GR_HEIGHT);
  Fs->draw_it=&LevelEditorDraw;
//See WinQueIPMsgs,needed to avoid waiting for dbl click
  Bts(&(Fs->win_inhibit),WIf_FOCUS_TASK_MS_L_D);
  Bts(&(Fs->win_inhibit),WIf_FOCUS_TASK_MS_R_D);
  while(continue) {
    if(texture=world_edit.edit_texture) {
      world_edit.ms_right_down=FALSE;
      switch(idx=WallCeilFloor) {
        case 2:
	  EditDC(blob,texture->ceil_blob_name,128,128);
	  break;
        case 1:
	  EditDC(blob,texture->wall_blob_name,128,128);
	  break;
        case 0:
	  EditDC(blob,texture->floor_blob_name,128,128);
	  break;
        default:
	  goto no_edit_tile;
      }
      if(idx) {
        str=LoadGr(blob,texture->wall_blob_name);
        if(texture->wall_dc) AnimDCDel(texture->wall_dc);
        texture->wall_dc=ScaleDC(str,GRID_SZ,GRID_SZ,world_edit.mem_task);
        AnimDCDel(str);
      } else {
        texture->orig_dc=LoadGr(blob,texture->floor_blob_name);
        AnimDCDel(texture->dc);
        texture->dc=ScaleDC(texture->orig_dc,GRID_SZ,GRID_SZ,world_edit.mem_task);
      }
      world_edit.edit_texture=NULL;
no_edit_tile:;
    }
    if(str=world_edit.edit_thing_template) {
      world_edit.ms_right_down=FALSE;
      world_edit.edit_thing_template=NULL;
      EditThingTemplate(blob,str);
    }
    switch(ScanMsg(&m1,&m2)) {
      default:
        world_edit.ms_scroll_delta=ms.pos.z-last_wheel;
        last_wheel=ms.pos.z;
        if(Fs->pix_height-THING_BAR_HEIGHT>world_edit.ms_y)
	  if(SIDEBAR_WIDTH<world_edit.ms_x<=Fs->pix_width-SIDEBAR_WIDTH) {
	    if(Bt(kbd.down_bitmap,SC_SHIFT)) {
	      world_edit.ceil_height-=world_edit.ms_scroll_delta;
	      world_edit.ms_scroll_delta=0;
	    } else if(!Bt(kbd.down_bitmap,SC_CTRL)) {
	      world_edit.floor_height-=world_edit.ms_scroll_delta;
	      world_edit.ms_scroll_delta=0;
	    } else {
	      world_edit.ceil_height2=MaxI64(1,world_edit.ceil_height2-world_edit.ms_scroll_delta);
	      world_edit.ms_scroll_delta=0;
	    }
	  }
        Refresh;
        goto next;
      case MSG_MS_MOVE:
        world_edit.ms_x=m1;
        world_edit.ms_y=m2;
        world_edit.at_x=world_edit.base_x+m1;
        world_edit.at_y=world_edit.base_y+m2;
        break;
      case MSG_MS_L_DOWN:
        world_edit.ms_left_down=TRUE;
        break;
      case MSG_MS_L_UP:
//We use dont_modify_tiles when holding down the mouse
        world_edit.dont_modify_tiles->cnt=0;
        world_edit.ms_left_down=FALSE;
        break;
      case MSG_MS_R_DOWN:
        world_edit.ms_right_down=TRUE;
        break;
      case MSG_MS_R_UP:
//We use dont_modify_tiles when holding down the mouse
        world_edit.dont_modify_tiles->cnt=0;
        world_edit.ms_right_down=FALSE;
        break;
      start:
        switch(m2.u8[0]) {
	  case SC_CURSOR_UP: which_key=&world_edit.kbd_up_down;break;
	  case SC_CURSOR_DOWN: which_key=&world_edit.kbd_down_down; break;
	  case SC_CURSOR_LEFT: which_key=&world_edit.kbd_left_down; break;
	  case SC_CURSOR_RIGHT: which_key=&world_edit.kbd_right_down; break;
	  default: which_key=NULL;
        }
        case MSG_KEY_DOWN:
	  if(m1==CH_CTRLT) {
            EditLevelTransition(blob,&world_edit.level_transition);
	  } else if(m2.u8[0]==SC_F1) {
	    HelpMenu;
	  } if(m1==CH_CTRLZ) {
	    WorldEditUndo;
	  } else if(m1=='F') {
	    world_edit.flat_mode^=TRUE;
	  } else if(m1==CH_CTRLS) { //Save
save:
	    if(!world_edit.filename) {
	      old_flat=world_edit.flat_mode;
	      world_edit.flat_mode=TRUE;
	      world_edit.filename=PopUpFileName("Untitled.WORLD");
	      world_edit.flat_mode=old_flat;
	    }
	    LevelEditorExport(blob,world_edit.filename);
	  } else if(m1==CH_CTRLA) { //Save as
	    old_flat=world_edit.flat_mode;
	    world_edit.flat_mode=TRUE;
	    if(str=BlobFileSelect(blob)) {
	      Free(world_edit.filename);
	      world_edit.filename=str;
	    }
	    LevelEditorExport(blob,world_edit.filename);
	    world_edit.flat_mode=old_flat;
	  } else if(m1==CH_ESC) { //Quit and save
	    continue=FALSE;
	    Fs->draw_it=NULL;
	    goto save;
	  } else if(m1==CH_SHIFT_ESC) { //Quit no save
	    continue=FALSE;  
	  } else if(m1==CH_CTRLS) {
	    LevelEditorExport(blob,world_edit.filename);
	  } else if(m1==CH_CTRLO) { //Load texture
//Load wall texture
	    old_flat=world_edit.flat_mode;
	    world_edit.flat_mode=TRUE;
	    str=BlobFileSelect(blob);
	    if(str) {
	      Free(world_edit.filename);
	      world_edit.filename=NULL;
	      LoadWorld(blob,str);
	    } else {
	      PopUpOk("Unable to open file!!!");
	    }
	    world_edit.flat_mode=old_flat;
	    Free(str);
	  } else if(m2&0xff==SC_PAGE_DOWN) {
	    world_edit.cam_height-=5;
	  } else if(m2&0xff==SC_PAGE_UP) {
	    world_edit.cam_height+=5;
	  }
	  if(which_key) *which_key=TRUE;
	  break;
        case MSG_KEY_UP:
	  if(which_key) *which_key=FALSE;
	  break;
      end:
        break;
    }
    if(world_edit.kbd_left_down) {
      world_edit.base_x+=8;
    } else if(world_edit.kbd_right_down) {
      world_edit.base_x-=8;
    } else if(world_edit.kbd_up_down) {
      world_edit.base_y+=8;
    } else if(world_edit.kbd_down_down) {
      world_edit.base_y-=8;
    }
    world_edit.at_x=world_edit.base_x+world_edit.ms_x;
    world_edit.at_y=world_edit.base_y+world_edit.ms_y;
    if(Bt(kbd.down_bitmap,Char2ScanCode('t'))) {
      MouseToPos(world_edit.ms_x,world_edit.ms_y,&tx,&ty);
//Right click will decrease/increase ceil2 height or make/erase a ceiling
      tx=FloorI64(tx,16)/16;
      ty=FloorI64(ty,16)/16;
      tile.i32[0]=tx;
      tile.i32[1]=ty;
      segment=GetSegmentForPos(tx,ty);
      if(segment) {
        for(thing=segment->things.next;thing!=&segment->things;thing=thing->next) {
	  if(ToI64(thing->x)-1.5<=tx<ToI64(thing->x)+1.5)
	    if(ToI64(thing->y)-1.5<=ty<ToI64(thing->y)+1.5) {
//TODO undo
	      old_flat=world_edit.flat_mode;
	      world_edit.flat_mode=TRUE;
	      activate=PopUpGetI64("Activate tag on death:",INVALID_PTR,I32_MIN,I32_MAX);
	      if(activate==INVALID_PTR)
	        StrCpy(thing->data.activate_tag,"");
	      else
	        StrPrint(thing->data.activate_tag,"%d",activate);
	      world_edit.flat_mode=old_flat;
	      break;
	    }
        }
      } 

    } else if(Bt(kbd.down_bitmap,Char2ScanCode('q'))) {
      MouseToPos(world_edit.ms_x,world_edit.ms_y,&tx,&ty);
//Right click will decrease/increase ceil2 height or make/erase a ceiling
      tx=FloorI64(tx,16)/16;
      ty=FloorI64(ty,16)/16;
      tile.i32[0]=tx;
      tile.i32[1]=ty;
      segment=GetSegmentForPos(tx,ty);
      if(segment) {
        for(thing=segment->things.next;thing!=&segment->things;thing=thing->next) {
	  if(ToI64(thing->x)-1.5<=tx<ToI64(thing->x)+1.5)
	    if(ToI64(thing->y)-1.5<=ty<ToI64(thing->y)+1.5) {
//TODO undo
	      old_flat=world_edit.flat_mode;
	      world_edit.flat_mode=TRUE;
	      if(thing->data.chat_bot_name[0]) {
	        StrCpy(thing->data.chat_bot_name,"");
		if(PopUp2("Change Quest",TRUE,"Remove Quest",FALSE))
	          QuestEditor(,thing->data.chat_bot_name);
	      } else {
	        StrCpy(thing->data.chat_bot_name,"");
	        QuestEditor(,thing->data.chat_bot_name);
	      }
	      world_edit.flat_mode=old_flat;
	      break;
	    }
        }
      } 
    } else if(Bt(kbd.down_bitmap,Char2ScanCode('s'))) {
      MouseToPos(world_edit.ms_x,world_edit.ms_y,&tx,&ty);
      tx=FloorI64(tx,GRID_SZ)/16;
      ty=FloorI64(ty,GRID_SZ)/16;
      SexyCeiling(tx,ty);
    } else if(Bt(kbd.down_bitmap,Char2ScanCode('i'))) {
      MouseToPos(world_edit.ms_x,world_edit.ms_y,&tx,&ty);
      tx=FloorI64(tx,GRID_SZ)/16;
      ty=FloorI64(ty,GRID_SZ)/16;
      segment=GetSegmentForPos(tx,ty);
      if(segment) {
        for(thing=segment->things.next;thing!=&segment->things;thing=thing->next) {
	  if(ToI64(thing->x)-1.5<=tx<ToI64(thing->x)+1.5)
	    if(ToI64(thing->y)-1.5<=ty<ToI64(thing->y)+1.5) {
//TODO undo
	      old_flat=world_edit.flat_mode;
	      world_edit.flat_mode=TRUE;
	      if(!thing->data.drop_item_name[0]) {
		str=PopUpGetStr("Drop Item class name:");
		if(str)
	          StrCpy(thing->data.drop_item_name,str);
		Free(str);
	      } else if(PopUpNoYes("Remove item for thing?")){
	        StrCpy(thing->data.drop_item_name,"");
	      }
	      world_edit.flat_mode=old_flat;
	      break;
	    }
        }
      }
    } else if(Bt(kbd.down_bitmap,Char2ScanCode('d'))) {
      MouseToPos(world_edit.ms_x,world_edit.ms_y,&tx,&ty);
      tx=FloorI64(tx,GRID_SZ)/16;
      ty=FloorI64(ty,GRID_SZ)/16;
      segment=GetSegmentForPos(tx,ty); 
      if(Bt(kbd.down_bitmap,SC_SHIFT)) {
        door=segment->doors.next;
        while(door!=&segment->doors) {
	  if(door->x==tx&&door->y==ty) {
	    edit_door=CAlloc(sizeof(CLevelSegmentEditDoor),world_edit.mem_task);
	    edit_door->type='DoorDel';
	    edit_door->x=door->x;
	    edit_door->y=door->y;
	    edit_door->flags=door->flags;
	    edit_door->ceil_rise=door->ceil_rise;
	    edit_door->act_as_tile=door->act_as_tile;
	    QueIns(edit_door,world_edit.edits.last);
	    QueRem(door);
	    Free(door);
	    goto door_pass;
	  }
	  door=door->next;
        }
      }
      InsertDoor(tx,ty,TRUE,TRUE);
door_pass:;
    } else if(Bt(kbd.down_bitmap,Char2ScanCode('f'))){
      if(Bt(kbd.down_bitmap,SC_SHIFT)) {
//This is for toggling the "flat mode" then
      } else {
        if(world_edit.ms_y<Fs->pix_height-THING_BAR_HEIGHT-8)
	  if(SIDEBAR_WIDTH<=world_edit.ms_x<Fs->pix_width-SIDEBAR_WIDTH) {
	    MemSet(&fill_opts,FALSE,sizeof fill_opts);
	    old=world_edit.flat_mode;
	    PopUpForm(&fill_opts);
	    world_edit.flat_mode=old;
	    MouseToPos(world_edit.ms_x,world_edit.ms_y,&tx,&ty);
	    tx=FloorI64(tx,GRID_SZ)/16;
	    ty=FloorI64(ty,GRID_SZ)/16;
	    idx=world_edit.floor_height;
	    idx2=world_edit.wall_texture;
	    if(fill_opts.ceil) {
	      idx=world_edit.ceil_height;
	      idx2=world_edit.ceil_texture;
	    }
	    if(fill_opts.same_height) {
	      FloodFill(tx,
		  ty,
		  idx2,
		  I64_MAX,
		  WorldGetHeightAt(tx,ty),
		  idx,
		  ,
		  TRUE,
		  fill_opts.ceil);
	    } else {
	      FloodFill(tx,
		  ty,
		  idx2,
		  I64_MAX,
		  I64_MAX,
		  idx,
		  ,
		  TRUE,
		  fill_opts.ceil);
	    }
	    floor_fill=FALSE;
	  }
      }
    } else if(world_edit.ms_left_down) {
      if(world_edit.ms_y<Fs->pix_height-THING_BAR_HEIGHT-8)
        if(SIDEBAR_WIDTH<=world_edit.ms_x<Fs->pix_width-SIDEBAR_WIDTH) {
	  if(Bt(kbd.down_bitmap,SC_SHIFT)) {
//Place a thing
	    world_edit.ms_left_down=FALSE;
	    thingt=world_edit.thing_templates[world_edit.cur_thing_template_idx];
	    MouseToPos(world_edit.ms_x,world_edit.ms_y,&tx,&ty);
	    segment=GetSegmentForPos(FloorI64(tx,16)/16,FloorI64(ty,16)/16);
	    if(thingt&&segment) {
	      thing=CAlloc(sizeof(CLevelThing),world_edit.mem_task);
	      thing->x=ToF64(tx)/GRID_SZ;
	      thing->y=ToF64(ty)/GRID_SZ;
	      thing->thing_template_idx=thingt->idx;
	      edit_thing=CAlloc(sizeof(CLevelSegmentEditThing),world_edit.mem_task);
	      edit_thing->type='ThingIns';
	      edit_thing->x=thing->x;
	      edit_thing->y=thing->y;
	      edit_thing->rot=thing->rot;
	      edit_thing->thing_template_idx=thing->thing_template_idx;
	      QueIns(edit_thing,world_edit.edits.last);
	      QueIns(thing,&segment->things);
	    }
	  } else  {
//Place a tile
	    MouseToPos(world_edit.ms_x,world_edit.ms_y,&tx,&ty);
	    tx=FloorI64(tx,16)/16;
	    ty=FloorI64(ty,16)/16;
	    tile.i32[0]=tx;
	    tile.i32[1]=ty;
	    if(!I64SetHas(world_edit.dont_modify_tiles,tile)) {
	      I64SetAdd(world_edit.dont_modify_tiles,tile);
	      segment=GetSegmentForPos(tx,ty);
	      edit_ins=NULL;
	      if(segment) {
	        edit_ins=CAlloc(sizeof(CLevelSegmentEditIns),world_edit.mem_task);
	        edit_ins->type='Insert';
	        edit_ins->xoff=tx;
	        edit_ins->yoff=ty;
	        edit_ins->data=segment->data[tx-segment->xoff][ty-segment->yoff];
	        edit_ins->height=segment->heights[tx-segment->xoff][ty-segment->yoff];
	        edit_ins->ceil=segment->ceil_heights[tx-segment->xoff][ty-segment->yoff];
	        edit_ins->ceil2=segment->ceil_heights2[tx-segment->xoff][ty-segment->yoff];
	      }
	      WorldInsertTileAt(
		    tx,
		    ty,
		    world_edit.wall_texture
		    );
	      if(edit_ins) {
	        if(IsUndoNecescary(edit_ins))
		  QueIns(edit_ins,world_edit.edits.last);
	        else
		  Free(edit_ins);
	      }
	    }
	  }
        }
    } else if(world_edit.ms_right_down) {     
      if(world_edit.ms_y<Fs->pix_height-THING_BAR_HEIGHT-8)
        if(SIDEBAR_WIDTH<=world_edit.ms_x<Fs->pix_width-SIDEBAR_WIDTH) {
	  MouseToPos(world_edit.ms_x,world_edit.ms_y,&tx,&ty);
//Right click will decrease/increase ceil2 height or make/erase a ceiling
	  tx=FloorI64(tx,16)/16;
	  ty=FloorI64(ty,16)/16;
	  tile.i32[0]=tx;
	  tile.i32[1]=ty;
	  segment=GetSegmentForPos(tx,ty);
	  edit_ins=NULL;
	  if(segment) {
	    if(segment) {
	      edit_ins=CAlloc(sizeof(CLevelSegmentEditIns),world_edit.mem_task);
	      edit_ins->xoff=tx;
	      edit_ins->type='Insert';
	      edit_ins->yoff=ty;
	      edit_ins->data=segment->data[tx-segment->xoff][ty-segment->yoff];
	      edit_ins->height=segment->heights[tx-segment->xoff][ty-segment->yoff];
	      edit_ins->ceil=segment->ceil_heights[tx-segment->xoff][ty-segment->yoff];
	      edit_ins->ceil2=segment->ceil_heights2[tx-segment->xoff][ty-segment->yoff];
	    }
	    if(segment->ceil_heights[tx-segment->xoff][ty-segment->yoff]==I8_MAX) {
//Add a new ceil
	      if(!Bt(kbd.down_bitmap,SC_SHIFT)) {
	        if(!I64SetHas(world_edit.dont_modify_tiles,tile)) {
		  I64SetAdd(world_edit.dont_modify_tiles,tile);
		  WorldInsertTileAt(
		        tx,
		        ty,
		        world_edit.ceil_texture,
		        1
		        );
//Set Ceil-height2
		  WorldInsertTileAt(
		        tx,ty,
		        world_edit.ceil_texture,
		        2
		        );
	        } else {
		  Free(edit_ins);
		  edit_ins=NULL;
	        }
	      } else {
	        if(segment) {
// Look For for things second
		  for(thing=segment->things.next;thing!=&segment->things;thing=thing->next) {
		    if(ToI64(thing->x)-1.5<=tx<ToI64(thing->x)+1.5)
		      if(ToI64(thing->y)-1.5<=ty<ToI64(thing->y)+1.5) {
		        edit_thing=CAlloc(sizeof(CLevelSegmentEditThing),world_edit.mem_task);
		        edit_thing->type='ThingDel';
		        edit_thing->x=thing->x;
		        edit_thing->y=thing->y;
		        edit_thing->rot=thing->rot;
		        edit_thing->thing_template_idx=thing->thing_template_idx;
		        QueIns(edit_thing,world_edit.edits.last);
		        QueRem(thing);
		        Free(thing);
		        goto next;
		      }
		  }
	        }
	      }
	    } else { //Remove ceiling(if pressrent)
	      if(segment->ceil_heights[tx-segment->xoff][ty-segment->yoff]!=I8_MAX) {
	        if(!I64SetHas(world_edit.dont_modify_tiles,tile)) {
		  I64SetAdd(world_edit.dont_modify_tiles,tile);
		  ch2=world_edit.ceil_height2;
		  old=world_edit.ceil_height;
		  world_edit.ceil_height2=0;
		  world_edit.ceil_height=I8_MAX;
		  WorldInsertTileAt(
		        tx,ty,
		        world_edit.ceil_texture,
		        1
		        );
		  WorldInsertTileAt(
		        tx,ty,
		        world_edit.ceil_texture,
		        2
		        );
		  world_edit.ceil_height2=ch2;
		  world_edit.ceil_height=old;
	        } else {
		  Free(edit_ins);
		  edit_ins=NULL;
	        }
	      }
	    }
	    if(edit_ins) {
	      if(IsUndoNecescary(edit_ins))
	        QueIns(edit_ins,world_edit.edits.last);
	      else
	        Free(edit_ins);
	    }
	  }
next:;
        }
    }
  }
  Fs->draw_it=NULL;
  DCDel(world_edit.scrn);
  FreeEditorData;
  SettingsPop;
}

  //
  // Part for making sexy ceilings
  //
Bool IsPerimeterCeil(I64 x,I64 y) {
  I64 xoff,yoff;
  for(xoff=-1;xoff<2;xoff++) 
    for(yoff=-1;yoff<2;yoff++)
      if(xoff^^yoff)
        if(I8_MAX==WorldGetCeilAt(x+xoff,y+yoff))
	  return TRUE;
  return FALSE;
}
U0 SexyCeiling(I64 x,I64 y) {
  I64 old=world_edit.flat_mode;
  world_edit.flat_mode=1;
  I64 rise_by=PopUpRangeI64(0,10,,"Steepness of the Ceiling.\n","Pick 0 for flat ceiling\n");
  CI64Set *ceil_tiles=I64SetNew;
  CI64Set *working_set=I64SetNew,*working_set2=I64SetNew;
  CI64Set *done=I64SetNew,*affected_segments=I64SetNew;
  CLevelSegment *seg;
  CLevelSegmentEditFill *edit_ff;
  I64 tile,idx2,tile2;
  I64 xoff,yoff,idx,lowest,h,highest;
  F64 ts=tS;
  tile.i32[0]=x;
  tile.i32[1]=y;
  I64SetAdd(working_set,tile);
  I64SetAdd(ceil_tiles,tile);
  highest=WorldGetCeilAt(x,y);
  while(working_set->cnt>0) {
    tile=working_set->body[--working_set->cnt];
    for(xoff=-1;xoff<2;xoff++)
      for(yoff=-1;yoff<2;yoff++) {
        tile2.i32[0]=tile.i32[0]+xoff;
        tile2.i32[1]=tile.i32[1]+yoff;
        idx=WorldGetCeilAt(tile2.i32[0],tile2.i32[1]);
        idx2=WorldGetCeilRiseAt(tile2.i32[0],tile2.i32[1]);
        if(idx!=I8_MAX&&
	      idx>=h&&idx2) {
	  if(!I64SetHas(ceil_tiles,tile2)) {
	    I64SetAdd(working_set,tile2);
	    I64SetAdd(ceil_tiles,tile2);
	    seg=GetSegmentForPos(tile2.i32[0],tile2.i32[1]);
	    if(!I64SetHas(affected_segments,seg))
	      I64SetAdd(affected_segments,seg);
	    highest=MaxI64(highest,idx);
	  }
        }
      }
  }
//Make an undo action for the poo poo sauce
  for(idx=0;idx!=affected_segments->cnt;idx++) {
    seg=affected_segments->body[idx];
    edit_ff=CAlloc(sizeof(CLevelSegmentEditFill));
    edit_ff->tS=ts;
    edit_ff->xoff=seg->xoff;
    edit_ff->yoff=seg->yoff;
    edit_ff->type='FldFill';
    MemCpy(edit_ff->data,seg->data,2*SEGMENT_SZ*SEGMENT_SZ);
    MemCpy(edit_ff->heights,seg->heights,SEGMENT_SZ*SEGMENT_SZ);
    MemCpy(edit_ff->ceil_heights,seg->ceil_heights,SEGMENT_SZ*SEGMENT_SZ);
    MemCpy(edit_ff->ceil_heights2,seg->ceil_heights2,SEGMENT_SZ*SEGMENT_SZ);
    QueIns(edit_ff,world_edit.edits.last);
  }
//Start with permimeter tiles 
  working_set->cnt=0;
  for(idx=0;idx!=ceil_tiles->cnt;idx++) {
    tile=ceil_tiles->body[idx];
    x=tile.i32[0];
    y=tile.i32[1];    
    if(IsPerimeterCeil(x,y))  {
      I64SetAdd(working_set,tile);
      I64SetAdd(done,tile);
    }
    seg=GetSegmentForPos(x,y);
    x-=seg->xoff;
    y-=seg->yoff;
    seg->ceil_heights2[x][y]=highest-seg->ceil_heights[x][y]+MaxI64(rise_by,1);
  }
//Go away from perimeter(center?)
  while(working_set->cnt) {
    working_set2->cnt=0;
    for(idx=0;idx!=working_set->cnt;idx++)
      I64SetAdd(done,working_set->body[idx]);
    for(idx=0;idx!=working_set->cnt;idx++) {
      tile=working_set->body[idx];
      lowest=I8_MAX;
//Pick lowest+1 of done adjacent tiles
      for(xoff=-1;xoff<2;xoff++)
        for(yoff=-1;yoff<2;yoff++) {
	  if(xoff^^yoff) {
	    tile=working_set->body[idx];
	    tile.i32[0]+=xoff;
	    tile.i32[1]+=yoff;
	    if(I64SetHas(done,tile)) {
	      if(I64SetHas(ceil_tiles,tile)) {
	        h=WorldGetCeilRiseAt(tile.i32[0],tile.i32[1])+WorldGetCeilAt(tile.i32[0],tile.i32[1]);
	        lowest=MinI64(lowest,h);
	      }
	    } else if(I64SetHas(ceil_tiles,tile)&&!I64SetHas(working_set2,tile))
	      I64SetAdd(working_set2,tile);
	  }
        }
      tile=working_set->body[idx];
      if(lowest!=I8_MAX&&!IsPerimeterCeil(tile.i32[0],tile.i32[1])) {
        x=tile.i32[0];
        y=tile.i32[1];
        seg=GetSegmentForPos(x,y);
        h=seg->ceil_heights[x-seg->xoff][y-seg->yoff];
	seg->ceil_heights2[x-seg->xoff][y-seg->yoff]=lowest+rise_by-h;
      }
    }
    working_set->cnt=0;
    for(idx=0;idx!=working_set2->cnt;idx++)
      I64SetAdd(working_set,working_set2->body[idx]);
  }

  I64SetDel(ceil_tiles);
  I64SetDel(working_set);
  I64SetDel(working_set2);
  I64SetDel(affected_segments);
  I64SetDel(done);
  world_edit.flat_mode=old;
}

WorldEdit("ASS");
