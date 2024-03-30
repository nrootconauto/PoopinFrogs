/*
  THIS IS A WIP FILE!!!
*/

#include "AnimDC.HC"
#include "BlobFile.HC"
#define GRID_SZ 16
#define DIST_SCALE (GRID_SZ*2200)

#define SEGMENT_SZ 32
#define GRID_SZ 16
#define THING_WIDTH (16*8)
#define THING_HEIGHT (32*8)
#define THING_WIDTH_SCALED 16
#define THING_HEIGHT_SCALED 32
class CLevelSegment:CQue {
  CLevelSegment *top,*bottom,*left,*right;
  I64 xoff,yoff;
  CQue things;
  //>0 for wall
  //<0 for floor
  I16 data[SEGMENT_SZ][SEGMENT_SZ];
  I8 heights[SEGMENT_SZ][SEGMENT_SZ];
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
};
class CLevelTexture:CQue {
  I64 idx;
//These are the top dc
  CDC *orig_dc; //The unscaled DC
  CDC *dc; //The scaled DC for use with drawing the level
  U8 wall_blob_name[STR_LEN];
  U8 floor_blob_name[STR_LEN];
};
#define EDITOR_TOOL_SQUARE 0b10
#define EDITOR_TOOL_CIRLCE 0b110
//See grow_force
#define EDITOR_TOOLF_RADIUS 1 //This will grow depending on the radius
class CWorldEditor {
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
  I64 floor_texture_scroll;
//This isnt a multiple of 3 Dude
  I64 thingbar_scroll;
//Currently selected
  I64 wall_texture;
  I64 floor_texture;
  I64 cur_thing_template_idx;
  I64 ms_x,ms_y,ms_scroll_delta;
  U8 *tooltip_text;
  CQue segments;
  CLevelTexture *edit_texture;
  CLevelThingTemplate *edit_thing_template;
  F64 grow_force,cam_height;
  U8 *filename;
  Bool ms_left_down;
  Bool ms_right_down;
  Bool kbd_left_down;
  Bool kbd_right_down;
  Bool kbd_up_down;
  Bool kbd_down_down;
  Bool ms_wheel_down;
  Bool ms_wheel_up;
  Bool flat_mode;
  I8 wall_height,floor_height;
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
  if(!(s%SEGMENT_SZ)) return s;
  if(s>=0) return s/SEGMENT_SZ*SEGMENT_SZ;
  return s/SEGMENT_SZ*SEGMENT_SZ-SEGMENT_SZ;
}
F64 Lerp(F64 per,F64 min,F64 max) {
  F64 t;
  return Clamp(min+(max-min)*per,Min(min,max),Max(max,min));
}
CDC *ScaleDC(CDC *from_dc,I64 w=GRID_SZ,I64 h=GRID_SZ) {
  I64 x,y,cnt,idx;
  CDC *ret=CAlloc(((cnt=AnimDCCnt(from_dc))+1)*sizeof(CDC),world_edit.mem_task);
  CDC *scaled;
  for(idx=0;idx!=cnt;idx++) {
    scaled=DCNew(w,h,world_edit.mem_task);
    for(x=0;x!=w;x++)
      for(y=0;y!=h;y++) {
        scaled->color=GrPeek0(from_dc+idx,
	      ToF64(x)/w*from_dc->width,
	      ToF64(y)/h*from_dc->height
        );
        GrPlot0(scaled,x,y);
      }
    MemCpy(ret+idx,scaled,sizeof(CDC));
    Free(scaled);
  }
  return ret;
}
CLevelTexture *LoadTexture(CDC *from_dc,I64 idx) {
  I64 len,x;
  I64 greatest=0;
  CDC *scaled;
  CLevelTexture *new=CAlloc(sizeof CLevelTexture),*cur;
  if(from_dc) {
    new->orig_dc=AnimDCCopy(from_dc,world_edit.mem_task);
    scaled=ScaleDC(from_dc);
  } else {
    new->orig_dc=DCNew(128,128,world_edit.mem_task);
    scaled=DCNew(GRID_SZ,GRID_SZ,world_edit.mem_task);
    DCFill(scaled,TRANSPARENT);
  }

  new->idx=idx;
  new->dc=scaled;
  world_edit.textures[new->idx-I16_MIN]=new;
  QueIns(new,&world_edit.textures_que);
  return new;
}
U0 WorldExtents(I64 *minx,I64 *maxx,I64 *miny,I64 *maxy) {
  CLevelSegment *cur=world_edit.segments.next;
  *minx=0;
  *miny=0;
  *maxx=0;
  *maxy=0;
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
class CFileThing {
  U16 thing_template_idx;
//x/y are in tiles 
  F64 x,y,rot;
}
class CFileTexture {
  I64 idx;
  U8 floor_blob_name[STR_LEN];
  U8 wall_blob_name[STR_LEN];
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
  I8 *ptr=world->data(I8*)+(world->w*world->h)*sizeof(U16);
  I64 x,y;
  for(y=0;y!=SEGMENT_SZ;y++) {
    for(x=0;x!=SEGMENT_SZ;x++) {
      *ptr++=seg->heights[x][y];
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
  U8 *fptr,save,*fptr2;
  WorldExtents(&minx,&maxx,&miny,&maxy);
  I64 textures_sz=0,tsz,templates_sz=0,things_sz=0;
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
  }
  textures_sz=sizeof(CFileTexture)*QueCnt(&world_edit.textures_que);
  I64 w=maxx-minx,h=maxy-miny;
  I64 fsz=(w*h)+2*(w*h)+sizeof(CWorld)+textures_sz+templates_sz+things_sz;
  CWorld *data=CAlloc(fsz);
  data->startx=minx;
  data->starty=miny;
  data->w=w,data->h=h;
  data->data=data+1;
  data->textures=data->data(U8*)+(w*h)*3;
  data->thing_templates=data->textures(U8*)+textures_sz;
  data->things=data->thing_templates(U8*)+sizeof(CFileThingTemplate)*QueCnt(&world_edit.thing_templates_que);
  fptr2=data->things(U8*)+things_sz;
  for(cur=world_edit.segments.next;cur!=&world_edit.segments;cur=cur->next) {
    _DumpSegment(data,cur);
    _DumpSegmentHeight(data,cur);
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
    fptr(CFileTexture*)++;
  }
  if(fptr-data->textures(U8*)!=sizeof(CFileTexture)*QueCnt(&world_edit.textures_que))
    throw('Save');
  for(
	template=world_edit.thing_templates_que.next;
	template!=&world_edit.thing_templates_que;
	template=template->next) {
    fptr(CFileThingTemplate*)->idx=template->idx;
    PrintI(template->name,1);
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
    }
  }
  if(fptr-data->things(U8*)!=things_sz) {
    throw('Save');
  }
  data->textures_where.ptr=data->textures(U8*)-data(U8*);
  data->textures_where.len=sizeof(CFileTexture)*QueCnt(&world_edit.textures_que);
  data->thing_templates_where.ptr=data->thing_templates(U8*)-data(U8*);
  data->thing_templates_where.len=sizeof(CFileThingTemplate)*QueCnt(&world_edit.thing_templates_que);
  data->things_where.ptr=data->things(U8*)-data(U8*);
  data->things_where.len=things_sz;
  data->data=w*h;
  BlobFileAddLump(blob,filename,data,fsz,'LEVEL');
  Free(data);
}
CLevelSegment *LevelEditorNewSegment(I64 at_x,I64 at_y) {
  at_x=SegmentRoundDown(at_x);
  at_y=SegmentRoundDown(at_y);
  CLevelSegment *new=CAlloc(sizeof(CLevelSegment),world_edit.mem_task),*cur;
  QueInit(&new->things);
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
  if(at_x==at_x_cache)
    if(at_y==at_y_cache)
      if(ret_cache)
        return ret_cache;
  CLevelSegment *cur;
  for(cur=world_edit.segments.next;cur!=&world_edit.segments;cur=cur->next) {
    if(cur->xoff<=at_x<=cur->xoff+SEGMENT_SZ)
      if(cur->yoff<=at_y<=cur->yoff+SEGMENT_SZ) {
        ret_cache=cur;
        at_x_cache=at_x;
        at_y_cache=at_y;
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
    cur_scroll=&world_edit.floor_texture_scroll;
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
        if(idx==world_edit.floor_texture) {
	  goto paint_selected;
        }
      }
      if(t=world_edit.textures[idx-I16_MIN]) {
        if(world_edit.ms_left_down)
	  if(x<=world_edit.ms_x<x+8+GRID_SZ)
	    if(y<=world_edit.ms_y<y+8+GRID_SZ) {
	      Free(world_edit.tooltip_text);
	      world_edit.tooltip_text=MStrPrint("Floor:%d",t->idx);
	      if(!right_side)
	        world_edit.wall_texture=idx;
	      else
	        world_edit.floor_texture=idx;
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
	THING_HEIGHT_SCALED);
  template->back_dc=ScaleDC(template->back_orig_dc,
	THING_WIDTH_SCALED,
	THING_HEIGHT_SCALED);
  template->front_dc=ScaleDC(template->front_orig_dc,
	THING_WIDTH_SCALED,
	THING_HEIGHT_SCALED);
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
  y=task->pix_height-THING_BAR_HEIGHT+8+4-8; //-8 for status bar
  //Scroll
  if(world_edit.ms_scroll_delta)
  if(SIDEBAR_WIDTH<=world_edit.ms_x<task->pix_width-SIDEBAR_WIDTH) {
    idx=0;
    for(
	template=world_edit.thing_templates_que.next;
	template!=&world_edit.thing_templates_que;
	template=template->next
	) {
       idx=MaxI64(idx,template->idx);
    }
    world_edit.thingbar_scroll=ClampI64(
	world_edit.thingbar_scroll+world_edit.ms_scroll_delta,
	0,
	idx);
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
U0 DrawThingSexy(CDC *dc,I64 dispx,I64 dispy,F64 x,F64 y,CDC *thing) {
  CLevelSegment *segment=GetSegmentForPos(x/GRID_SZ,y/GRID_SZ);
  I64 height=segment->heights[x/GRID_SZ-segment->xoff][y/GRID_SZ-segment->yoff];
  I64 idist=(world_edit.cam_height-height)*GRID_SZ+1024;
  F64 width=DIST_SCALE/ToF64(idist);
  x=(x-GR_WIDTH/2+dispx)*width/16+GR_WIDTH/2;
  y=(y-GR_HEIGHT/2+dispy)*width/16+GR_HEIGHT/2;
  GrBlot(dc,x-thing->width/2,y-thing->height/2,thing); 
}
U0 DrawThingDumb(CDC *dc,I64 dispx,I64 dispy,I64 x,I64 y,CDC *thing) {
  GrBlot(dc,x-thing->width/2+dispx,y-thing->height/2+dispy,thing); 
}
U0 DrawSegmentThings(CTask *t,CDC *dc) {
  CLevelSegment *segment;
  CLevelThing *thing;
  CLevelThingTemplate *template;
  I64 x,y,xspan,yspan;
  I64 tx=world_edit.base_x/GRID_SZ,ty=world_edit.base_y/GRID_SZ;
  for(xspan=tx-GRID_SZ*2;xspan<=tx+GRID_SZ*2;xspan+=GRID_SZ) {
    for(yspan=ty-GRID_SZ*2;yspan<=ty+GRID_SZ*2;yspan+=GRID_SZ) {
      segment=GetSegmentForPos(xspan,yspan);
      if(segment) {
        thing=segment->things.next;
        while(thing!=&segment->things) {
	  template=world_edit.thing_templates[thing->thing_template_idx];
	  if(template->front_dc) {
	    if(world_edit.flat_mode) {
	      DrawThingDumb(dc,world_edit.base_x,world_edit.base_y,thing->x*GRID_SZ,thing->y*GRID_SZ,template->front_dc);
	    } else 
	      DrawThingSexy(dc,world_edit.base_x,world_edit.base_y,thing->x*GRID_SZ,thing->y*GRID_SZ,template->front_dc);
	  }
	  dc->color=WHITE;
//	  GrPutS(dc,x-StrLen(template->name)*8/2,y+16-4,template->name);
	  thing=thing->next;
        }
      }
    }
  }
}
#define GRID_SZ 16
#define DIST_SCALE (GRID_SZ*2200)
U0 DrawTexturedQuad(CDC *dc,CD3I32 *poly,CDC *texture=NULL) {
  dc->color=BLUE;
  GrFillTri0(dc,poly,poly+2,poly+1);
  GrFillTri0(dc,poly,poly+2,poly+3);
}
// xoff/yoff specify which wall
U0 DrawWall(CDC *dc,I64 dispx,I64 dispy,I64 tx,I64 ty,I64 xoff,I64 yoff,CDC *side,F64 height) {
  if(xoff&&yoff) return;
  I64 idist=(world_edit.cam_height-height)*GRID_SZ+1024;
  F64 width=DIST_SCALE/ToF64(idist);

  F64 h,w,width2;
  I64 x=(tx*16-GR_WIDTH/2+dispx)*width/16+GR_WIDTH/2;
  I64 y=(ty*16-GR_HEIGHT/2+dispy)*width/16+GR_HEIGHT/2;
  CLevelSegment *seg=GetSegmentForPos(tx+xoff,ty+yoff);
  if(!seg)
    return;
  h=seg->heights[(tx+xoff)-seg->xoff][(ty+yoff)-seg->yoff];
  width2=DIST_SCALE/((world_edit.cam_height-h)*GRID_SZ+1024);
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
    DrawTexturedQuad(dc,points);
  } else if(xoff==-1&&x>GR_WIDTH/2) {
    points[0].x=sx;
    points[1].x=sx;
    points[2].x=ex2; 
    points[3].x=ex2;
    points[0].y=ey;
    points[1].y=sy;
    points[2].y=sy2;
    points[3].y=ey2;
    DrawTexturedQuad(dc,points);
  } else if(yoff==1&&y<GR_HEIGHT/2) {
    points[0].y=ey;
    points[1].y=ey;
    points[2].y=sy2; 
    points[3].y=sy2;
    points[0].x=sx;
    points[1].x=ex;
    points[2].x=ex2;
    points[3].x=sx2;
    DrawTexturedQuad(dc,points);
  } else if(yoff==-1&&y>GR_HEIGHT/2) {
    points[0].y=sy;
    points[1].y=sy;
    points[2].y=ey2; 
    points[3].y=ey2;
    points[0].x=ex;
    points[1].x=sx;
    points[2].x=sx2;
    points[3].x=ex2;
    DrawTexturedQuad(dc,points);
  }
}
U0 DrawTileSexy(CDC *dc,I64 dispx,I64 dispy,F64 height,CDC *top,CDC *side,I64 tx,I64 ty) {
  I64 idist=(world_edit.cam_height-height)*GRID_SZ+1024,wi;
  F64 width=DIST_SCALE/ToF64(idist);
  I64 x=(tx*16-GR_WIDTH/2+dispx)*width/16+GR_WIDTH/2;
  I64 y=(ty*16-GR_HEIGHT/2+dispy)*width/16+GR_HEIGHT/2;
  I64 sx=x-width/2; 
  I64 sy=y-width/2; 
  I64 ex=x+width/2,ey=y+width/2;
  I64 xoff,yoff;
  U8 *base,*base2;
  wi=top->width_internal;
  for(yoff=sy;yoff<ey;yoff++) {
    base=&top->body[ToI64((yoff-sy)/width*top->height)*wi];
    for(xoff=sx;xoff<ex;xoff++) {
      dc->color=base[ToI64((xoff-sx)/width*top->width)];
      GrPlot3(dc,xoff,yoff,idist);
    }
  }
  for(xoff=-1;xoff<2;xoff++)
    for(yoff=-1;yoff<2;yoff++)
      DrawWall(dc,dispx,dispy,tx,ty,xoff,yoff,side,height);
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
    if(_x) *_y=ms_y-dispy;
    return;
  }
  for(height=I8_MAX;height>=I8_MIN;height--) {
    idist=(world_edit.cam_height-height)*GRID_SZ+1024;
    width=DIST_SCALE/ToF64(idist);
    x=((ms_x+width/2-GR_WIDTH/2)*16/width-dispx+GR_WIDTH/2)/16;
    y=((ms_y+width/2-GR_HEIGHT/2)*16/width-dispy+GR_HEIGHT/2)/16;
        if(seg=GetSegmentForPos(x,y)) {
	  if(seg->heights[ToI64(x)-seg->xoff][ToI64(y)-seg->yoff]==height) {
	    if(_x) *_x=x*16;
	    if(_y) *_y=y*16;
	    return;
	  }
        }
  }
  if(_x) *_x=x;
  if(_x) *_y=y;
}
U0 LevelEditorDraw(CTask *t,CDC *dc) {
  DCDepthBufAlloc(dc);
  CLevelSegment *seg;
  CLevelTexture *texture;
  F64 theight;
//Tile offsets
  I64 t_xoff=world_edit.base_x/GRID_SZ,t_yoff=world_edit.base_y/GRID_SZ;
  I64 x,y;
  U8 *str;
  for(x=-64;x!=64;x++) {
    for(y=-64;y!=64;y++) {
      seg=GetSegmentForPos(x+t_xoff,y+t_yoff);
      if(!seg) goto next;
      texture=world_edit.textures[seg->data
	[(t_xoff+x)-seg->xoff]
	[(t_yoff+y)-seg->yoff]-I16_MIN];
      theight=seg->heights[(t_xoff+x)-seg->xoff][(t_yoff+y)-seg->yoff];
      if(texture) {
	if(!world_edit.flat_mode)
	  DrawTileSexy(dc,world_edit.base_x,world_edit.base_y,theight,texture->orig_dc,texture->orig_dc,t_xoff+x,t_yoff+y);
	else
	  DrawTileDumb(dc,world_edit.base_x,world_edit.base_y,texture->dc,t_xoff+x,t_yoff+y);
      }
next:;
    }
  }
  DrawSidebar(dc,0);
  DrawSidebar(dc,t->pix_width-SIDEBAR_WIDTH,TRUE);
  dc->color=BLUE;
  GrRect(dc,SIDEBAR_WIDTH,t->pix_height-8,t->pix_width-SIDEBAR_WIDTH*2,8);
  str=MStrPrint("Floor Height(%d),Wall Height(%d)(Shift+Wheel == Change Floor Height)",
	world_edit.floor_height,
	world_edit.wall_height
  );
  DrawSegmentThings(t,dc);
  DrawThingBar(dc,t);
  dc->color=YELLOW;
  GrPutS(dc,SIDEBAR_WIDTH,t->pix_height-8,str);
  Free(str);
  Free(dc->depth_buf);
  dc->depth_buf=NULL;
}
Bool EditDC(U8 *blob,U8 *name,I64 dft_h,I64 dft_w) {
//TempleOS lexer gets rid of rest of line after #include
  Bool old_flat=world_edit.flat_mode;
  world_edit.flat_mode=TRUE;
  PopUpPrint(
        "Cd(\"%Q\");\n"
	"#include \"TextureEditor.HC\";\n"
	"StrCpy(%d,TextureEdit(\"%Q\",,%d,%d));\n",
	__DIR__,
        name,blob,dft_w,dft_h
        );
  world_edit.flat_mode=old_flat;
//TODO ensure lump exists
  return TRUE;
}
U0 EditThingTemplate(U8 *blob,CLevelThingTemplate *template) {
enter:;
  CDoc *what=DocNew(blkdev.tmp_filename);
  CLevelThingTemplate *head,*cur;
  I64 resp,idx,len;
  U8 *str;
  DocPrint(what,"$$TX+CX,\"Welcome to thing edit\"$$\n");
  DocPrint(what,"\n\n$$BT,\"Change Name\",LE=1$$\n");
  DocPrint(what,"\n\n$$BT,\"Edit Front\",LE=2$$\n");
  DocPrint(what,"\n\n$$BT,\"Edit Back\",LE=3$$\n");
  DocPrint(what,"\n\n$$BT,\"Edit Side\",LE=4$$\n");
  DocPrint(what,"\n\n$$BT,\"Use Front for All Sides\",LE=5$$\n");
  if(!StrOcc(template->name,'/')) DocPrint(what,"\n\n$$BT,\"Add State\",LE=6$$\n");
  DocPrint(what,"\n\n$$BT,\"Done\",LE=-1$$\n");
  resp=PopUpMenu(what);
  switch(resp) {
    case -1:
      break;
    case 1:
//Name
      str=PopUpGetStr("Thing Title:");
      StrCpy(template->name,str);
      Free(str);
      break;
    case 2:
//Front
      EditDC(blob,template->blob_front_name,150,275);
      AnimDCDel(template->front_orig_dc);
      template->front_orig_dc=LoadGr(blob,template->blob_front_name);
      AnimDCDel(template->front_dc);
      template->front_dc=ScaleDC(template->front_orig_dc,
	    THING_WIDTH_SCALED,
	    THING_HEIGHT_SCALED);
      break;
    case 3:
//Back
      EditDC(blob,template->blob_back_name,150,275);
      AnimDCDel(template->back_orig_dc);
      template->back_orig_dc=LoadGr(blob,template->blob_back_name);
      template->back_dc=ScaleDC(template->back_orig_dc,
	    THING_WIDTH_SCALED,
	    THING_HEIGHT_SCALED);
      break;
    case 4:
//Side
      EditDC(blob,template->blob_side_name,150,275);
      AnimDCDel(template->side_orig_dc);
      template->side_orig_dc=LoadGr(blob,template->blob_side_name);
      template->side_dc=ScaleDC(template->side_orig_dc,
	    THING_WIDTH_SCALED,
	    THING_HEIGHT_SCALED);
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
        for(idx=U16_MAX/2;idx<I16_MAX;idx++) {
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
  DocDel(what);
}
CLevelTexture *LevelEditorLoadTexture(U8 *blob,I64 idx) {
  Bool wall=PopUp2("Wall",1,"Floor",0,"Wall or floor texture");
  U8 *filename=BlobFileSelect(blob),*body;
  U64 type;
  CDC *loaded;
  CLevelTexture *texture;
  body=LoadGr(blob,filename);
  if(!body) {
    PopUpOk("Not a graphics Lump? try again\n");
    loaded=DCNew(1,1);
  } else
    loaded=body;
  texture=LoadTexture(loaded,idx);
  if(wall)
    StrCpy(texture->wall_blob_name,filename);
  else
    StrCpy(texture->floor_blob_name,filename);
  Free(body);
  AnimDCDel(loaded);
fin:
  Free(filename);
  return texture;
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
PrintI(template->name,123);
    template=template->next;
  }
PrintI("1",1);
  QueDel(&world_edit.thing_templates_que);
PrintI("2",2);

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
  QueInit(&world_edit.segments);
  QueInit(&world_edit.textures_que);
}
U0 WorldInsertTileAt(I64 x,I64 y,I64 thing) {
  CLevelSegment *seg=GetSegmentForPos(x,y);
  if(!seg)
    seg=LevelEditorNewSegment(x,y);
  x-=seg->xoff;
  y-=seg->yoff;
  if(thing>0) {
    seg->data[x][y]=thing;
    seg->heights[x][y]=world_edit.wall_height;
  } else {
    seg->data[x][y]=-thing;
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
U0 LoadWorld(U8 *blob,U8 *filename) {
  U8 *str;
  U8 *textures;
  U8 *templates;
  I8 *heightmap;
  I64 width,height,cap;
  I64 x,y,oldf=world_edit.floor_height,oldw=world_edit.wall_height;
  U64 type;
  I64 tsz;
  CLevelThingTemplate *template;
  CFileTexture *f_texture;
  CFileThingTemplate *f_template;
  CFileThing *f_thing,*things;
  CLevelThing *thing;
  CLevelSegment *segment;
  CLevelTexture *texture;
  CWorld *w=NULL;
  w=BlobFileGetLump(blob,filename,,&type);
  if(!w||type!='LEVEL') {
    PopUpOk(str=MStrPrint("Can't open world %s!!!",filename));
    Free(str);
    goto fail;
  }
  FreeEditorData;
  world_edit.filename=StrNew(filename);
  width=w->w;
  height=w->h;
  w->data=w+1;
  textures=w(U8*)+w->textures_where.ptr;
  templates=w(U8*)+w->thing_templates_where.ptr;
  heightmap=w->data(I16*)+(width*height);
  for(x=0;x!=width;x++)
    for(y=0;y!=height;y++) {
      world_edit.wall_height=heightmap[x+y*width];
      world_edit.floor_height=world_edit.wall_height;
      WorldInsertTileAt(x,y,w->data[x+y*width]);
    }
  f_texture=textures;
  cap=w->textures_where.len;
  while(f_texture<textures(U8*)+cap) {
    str=LoadGr(blob,f_texture->floor_blob_name);
    texture=LoadTexture(str,f_texture->idx);
    StrCpy(texture->wall_blob_name,f_texture->wall_blob_name);
    StrCpy(texture->floor_blob_name,f_texture->floor_blob_name);
    Free(str);
    f_texture++;
  }
  f_template=templates;
  cap=w->thing_templates_where.len;
  while(f_template<templates(U8*)+cap) {
    template=CreateNewThingTemplate(f_template->idx);
    template->front_orig_dc=LoadGr(blob,f_template->blob_front_name);
    template->back_orig_dc=LoadGr(blob,f_template->blob_back_name);
    template->side_orig_dc=LoadGr(blob,f_template->blob_side_name);
    StrCpy(template->blob_side_name,f_template->blob_side_name);
    StrCpy(template->blob_front_name,f_template->blob_front_name);
    StrCpy(template->blob_back_name,f_template->blob_back_name);
    template->side_dc=ScaleDC(template->side_orig_dc,
	  THING_WIDTH_SCALED,
	  THING_HEIGHT_SCALED);
    template->back_dc=ScaleDC(template->back_orig_dc,
	  THING_WIDTH_SCALED,
	  THING_HEIGHT_SCALED);
    template->front_dc=ScaleDC(template->front_orig_dc,
	  THING_WIDTH_SCALED,
	  THING_HEIGHT_SCALED);
    StrCpy(template->name,f_template->name);
    f_template++;
  }
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
      QueIns(thing,&segment->things);
    }
    f_thing++;
  }
fail: 
  Free(w);
  world_edit.floor_height=oldf;
  world_edit.wall_height=oldw;
}
class CFloodFillAt {
  I64 at_x,at_y;
};
I16 *GetTilePtrAt(I64 at_x,I64 at_y) {
  CLevelSegment *seg=GetSegmentForPos(at_x,at_y);
  if(!seg) return NULL;
  return &seg->data[at_x-seg->xoff][at_y-seg->yoff];
}
U0 FloodFillFloor(I64 at_x,I64 at_y,I64 with,I64 target_tile=I64_MAX) {
  CLevelSegment *segment=GetSegmentForPos(at_x,at_y);
  if(!segment) return;
  I64 stk_sz=0x100000,stk_ptr=0,x,y;
  I16 *ptr;
  CFloodFillAt *stk;
  if(target_tile==I64_MAX) target_tile=segment->data[at_x-segment->xoff][at_y-segment->yoff];
  else if(target_tile!=segment->data[at_x-segment->xoff][at_y-segment->yoff]) return;
  stk=CAlloc(stk_sz*sizeof(CFloodFillAt));
  if(target_tile==with) goto fin;
  stk[stk_ptr].at_x=at_x;
  stk[stk_ptr].at_y=at_y;
  stk_ptr++;
  while(stk_ptr) {
    stk_ptr--;
    
    at_x=stk[stk_ptr].at_x;
    at_y=stk[stk_ptr].at_y;
    *GetTilePtrAt(at_x,at_y)=with;
    if(stk_sz<=stk_ptr+4) {
      FloodFillFloor(at_x+1,at_y,with,target_tile);
      FloodFillFloor(at_x-1,at_y,with,target_tile);
      FloodFillFloor(at_x,at_y-1,with,target_tile);
      FloodFillFloor(at_x,at_y+1,with,target_tile);
      goto next;
    }
    if((ptr=GetTilePtrAt(at_x-1,at_y))&&*ptr==target_tile) {
      stk[stk_ptr].at_x=at_x-1;
      stk[stk_ptr].at_y=at_y;
      stk_ptr++;
    }
    if((ptr=GetTilePtrAt(at_x+1,at_y))&&*ptr==target_tile) {
      stk[stk_ptr].at_x=at_x+1;
      stk[stk_ptr].at_y=at_y;
      stk_ptr++;
    }
    if((ptr=GetTilePtrAt(at_x,at_y-1))&&*ptr==target_tile) {
      stk[stk_ptr].at_x=at_x;
      stk[stk_ptr].at_y=at_y-1;
      stk_ptr++;
    }
    if((ptr=GetTilePtrAt(at_x,at_y+1))&&*ptr==target_tile) {
      stk[stk_ptr].at_x=at_x;
      stk[stk_ptr].at_y=at_y+1;
      stk_ptr++;
    }
next:
  }
fin:
  Free(stk);
}
U0 WorldEdit(U8 *blob,U8 *filename=NULL) {
  I64 m1,m2;
  I64 tx,ty;
  I64 last_wheel=ms.pos.z;
  CLevelTexture *texture;
  CLevelSegment *segment;
  CLevelThingTemplate *thingt;
  CLevelThing *thing;
  U8 *str;
  Bool continue=TRUE,*which_key,floor_fill=FALSE;
  MemSet(&world_edit,0,sizeof(CWorldEditor));
  world_edit.cam_height=16;
  world_edit.mem_task=Fs;
  QueInit(&world_edit.textures_que);
  QueInit(&world_edit.thing_templates_que);
  QueInit(&world_edit.segments);
  SettingsPush;
  WinMax;
  DocClear;
  if(filename)
    world_edit.filename=StrNew(filename);
  Fs->draw_it=&LevelEditorDraw;
//See WinQueIPMsgs,needed to avoid waiting for dbl click
  Bts(&(Fs->win_inhibit),WIf_FOCUS_TASK_MS_L_D);
  Bts(&(Fs->win_inhibit),WIf_FOCUS_TASK_MS_R_D);
  while(continue) {
    if(texture=world_edit.edit_texture) {
      world_edit.ms_right_down=FALSE;
      if(PopUp2("Wall",1,"Floor",0,"Edit the wall or Floor?")) {
        EditDC(blob,texture->wall_blob_name,128,128);
      } else
        EditDC(blob,texture->floor_blob_name,128,128);
      texture->orig_dc=LoadGr(blob,texture->floor_blob_name);
      AnimDCDel(texture->dc);
      texture->dc=ScaleDC(texture->orig_dc);
      world_edit.edit_texture=NULL;
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
	if(SIDEBAR_WIDTH<world_edit.ms_x<=Fs->pix_width-SIDEBAR_WIDTH) {
	  if(Bt(kbd.down_bitmap,SC_SHIFT))
	    world_edit.floor_height-=world_edit.ms_scroll_delta;
          else
	    world_edit.wall_height-=world_edit.ms_scroll_delta;
	  world_edit.ms_scroll_delta=0;
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
        world_edit.ms_left_down=FALSE;
        break;
      case MSG_MS_R_DOWN:
        world_edit.ms_right_down=TRUE;
        break;
      case MSG_MS_R_UP:
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
	  if(m1=='F') {
	    world_edit.flat_mode^=TRUE;
	  } else if(m1==CH_CTRLS) { //Save
save:
	    if(!world_edit.filename) {
	      world_edit.filename=PopUpFileName("Untitled.WORLD");
	    }
	    LevelEditorExport(blob,world_edit.filename);
	  } else if(m1==CH_CTRLA) { //Save as
	    world_edit.filename=PopUpPickFile();
	    LevelEditorExport(blob,world_edit.filename);
	  } else if(m1==CH_ESC) { //Quit and save
	    continue=FALSE;
	    Fs->draw_it=NULL;
	    goto save;
	  } else if(m1==CH_SHIFT_ESC) { //Quit no save
	    continue=FALSE;  
	  } else if(m1==CH_CTRLO) { //Load texture
//Load wall texture
	    str=BlobFileSelect(blob);
	    if(str) {
	      Free(world_edit.filename);
	      world_edit.filename=NULL;
	      LoadWorld(blob,str);
	    } else {
	      PopUpOk("Unable to open file!!!");
	    }
	    Free(str);
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
    if(Bt(kbd.down_bitmap,Char2ScanCode('f'))){
      if(Bt(kbd.down_bitmap,SC_SHIFT)) {
//This is for toggling the "flat mode" then
      } else {
      if(world_edit.ms_y<Fs->pix_height-THING_BAR_HEIGHT-8)
        if(SIDEBAR_WIDTH<=world_edit.ms_x<Fs->pix_width-SIDEBAR_WIDTH) {
	  MouseToPos(world_edit.ms_x,world_edit.ms_y,&tx,&ty);
	  tx/=16;
	  ty/=16;
	  FloodFillFloor(tx,
	        ty,
	        world_edit.floor_texture); 
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
	    segment=GetSegmentForPos(tx/GRID_SZ,ty/GRID_SZ);
	    if(thingt&&segment) {
	      thing=CAlloc(sizeof(CLevelThing),world_edit.mem_task);
	      thing->x=ToF64(tx)/GRID_SZ;
	      thing->y=ToF64(ty)/GRID_SZ;
	      thing->thing_template_idx=thingt->idx;
	      QueIns(thing,&segment->things);
	    }
	  } else  {
//Place a tile
	    MouseToPos(world_edit.ms_x,world_edit.ms_y,&tx,&ty);
	    tx/=16;
	    ty/=16;
	    WorldInsertTileAt(
		  tx,
		  ty,
		  world_edit.wall_texture
		  );
	  }
        }
    } else if(world_edit.ms_right_down) {
      if(world_edit.ms_y<Fs->pix_height-THING_BAR_HEIGHT-8)
        if(SIDEBAR_WIDTH<=world_edit.ms_x<Fs->pix_width-SIDEBAR_WIDTH) {
	  MouseToPos(world_edit.ms_x,world_edit.ms_y,&tx,&ty);
	  if(Bt(kbd.down_bitmap,SC_SHIFT)) {
//Eraser
	    //For for things first
	    segment=GetSegmentForPos(tx/GRID_SZ,ty/GRID_SZ);
	    if(segment) {
	      for(thing=segment->things.next;thing!=&segment->things;thing=thing->next) {
	        if(ToI64(thing->x)<=tx/16<ToI64(thing->x)+16)
		  if(ToI64(thing->y)<=ty/16<ToI64(thing->y)+32) {
		    QueRem(thing);
		    Free(thing);
		    goto next;
		  }
	      }
	    }
	  } else {
	    tx/=16;
	    ty/=16;
	    WorldInsertTileAt(
		  tx,
		  ty,
		  -world_edit.floor_texture
		  );
	  }
        }
    }
next:;
  }
  Fs->draw_it=NULL;
  FreeEditorData;
  SettingsPop;
}
WorldEdit("ASS");