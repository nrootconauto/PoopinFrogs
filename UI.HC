#ifndef UI
#define UI
//This a not a finished file,DO NOT USE 3/20/24
/*

$BK,1$
.########..##.....##..######..##.....##.####.##....##....########.
.##.....##.##.....##.##....##.##.....##..##..###...##....##.....##
.##.....##.##.....##.##.......##.....##..##..####..##....##.....##
.########..##.....##..######..#########..##..##.##.##....########.
.##........##.....##.......##.##.....##..##..##..####....##.......
.##........##.....##.##....##.##.....##..##..##...###....##.......
.##.........#######...######..##.....##.####.##....##....##.......
$BK,0$
*/

CTask *ui_task=Fs;
#include "AnimDC.HC";
#include "SmallTalk/Load.HC"
#define UI_GRID_DRAG_FPTR "UIDragItem"
#define UI_FOCUS_FPTR "UIFocusItem"

#if 0
//These are defined in the ASS.BLOB SmallTalk header lump
class CUIElem:CFrogThing {
 //Negative means from side of parent/window
  I64 x,y;
  I64 sz_x,sz_y;
//x/y is where to draw the stuff
//These cordnates are realtive to the element
  CFrogBlock *ms_ldown;
  CFrogBlock *ms_lup;
  CFrogBlock *ms_rdown;
  CFrogBlock *ms_rup;
  CFrogBlock *kbd_up;
  CFrogBlock *kbd_down;
  CFrogBlock *drag_start;
  CFrogBlock *drag_end;
  CFrogBlock *ms_move;
  CFrogArray *sub_elems;
//
  I64 computed_x,computed_y;
  Bool dont_draw_children;
  Bool update_parent_first;
  Bool focus;
  Bool dont_draw,pad[4];
};
class CUIChatLog:CUIElem {
  U8 *constructor dft "UIChatLogInit";
  U8 *draw_it dft "UIChatLogDraw";
  CFrogArray *lines;
  I64 max_cnt;
  U8 bg_color,fg_color;
};
class CUIBackground:CUIElem {
  U8 *draw_it dft "UIBackgroundDraw";
  U8 *constructor dft "UIElemInit";
  I64 bg_color;
};
class CUILabel:CUIElem {
  U8 *draw_it dft "UILabelDraw";
  U8 *constructor dft "UILabelInit";
  I64 color;
  CFrogStr *label;
};
class CUIButton:CUIElem {
  U8 *draw_it dft "UIButtonDraw";
  U8 *constructor dft "UIButtonInit";  
  I64 fg_color;
  I64 bg_color;
  CFrogStr *label;
};
class CUIMeter:CUIElem {
  U8 *draw_it dft "UIMeterDraw";
  U8 *constructor dft "UIMeterInit";  
  I64 max,value;
  I64 bg_color;
  I64 fg_color;
  I64 text_color;
  I64 border_color;
  CFrogStr *str;
};
class CUITextBar:CUIElem {
  CFrogStr *buf;
  U8 *constructor dft "UITextBarInit";
  U8 *draw_it dft "UITextBarDraw";
  I64 view_pos,cur_pos;
  U8 bg_color,fg_color,border_color;
};
class CUIScrollBars:CUIElem {
  U8 *constructor dft "UIElemInit";
  U8 *draw_it dft "UIScrollBarsDraw";
  I64 x_scroll,y_scroll,bg_color;
};
class CUICenter:CUIElem {
  U8 *constructor dft 6"UIElemInit";
  U8 *draw_it dft "UICenterDraw";
  CUIElem *parent; 
  Bool x_center,y_center;
};

class CUIGridItem:CUIElem {
  CFrogStr *name;
  CDC *graphics;
  I64 cnt; //0 for none
  CFrogThing *parent;
  U8 *draw_it dft "UIGridItemDraw";
};

class CUIGrid:CUIElem {
  I64  grid_w,grid_h;
  CFrogArray *mat;
  CUIGridItem *active;
  U8 *draw_it dft "UIGridDraw";
};
#endif
U0 RenderUI(CDC *dc,CUIElem *e,I64 left_x=0,I64 left_y=0,I64 right_x=GR_WIDTH,I64 right_y=GR_HEIGHT) {
  if(!ThingHasClass(e,"CUIElem")) return;
  CUIElem *draw,**body=e->sub_elems->items->body;
  I64 x,y;
  U8 *draw_it;
  I64 cnt;
  CHashFun *fun;
  U0 (*fptr)(CDC*,I64 x,I64 y,CUIElem*);
  draw=e;
  if(draw->x<0) x=draw->x+right_x;
  else x=draw->x+left_x;
  if(draw->y<0) y=draw->y+right_y;
  else y=draw->y+left_y;
  draw->computed_x=x;
  draw->computed_y=y;

  if(dc&&!(draw->dont_draw)) {
    draw_it=GetClassMemberValI64(e,"draw_it");
    if(draw_it) {
      fun=HashFind(draw_it,frog_mem_task->hash_table,HTT_FUN);
      if(fun) {
        fptr=fun->exe_addr;
	(*fptr)(dc,x,y,draw);
      }
    }
  }
  if(!draw->dont_draw_children)
    for(cnt=e->sub_elems->items->cnt-1;cnt>=0;cnt--)
      RenderUI(dc,body[cnt],x,y,x+draw->sz_x,y+draw->sz_y); 
}
U0 UIOnKillElem(CUIElem *e) {
  CUIElem **body=e->sub_elems->items->body;
  I64 cnt;
  if(FramePtr(UI_FOCUS_FPTR,ui_task)==e)
    FramePtrDel(e);
}
U0 UIFocusElem(CUIElem *e) {
  if(FramePtr(UI_FOCUS_FPTR,ui_task))
    FramePtrDel(UI_FOCUS_FPTR,ui_task);
  FramePtrAdd(UI_FOCUS_FPTR,e,ui_task);
}
U0 UIUnFocus() {
  FramePtrDel(UI_FOCUS_FPTR,ui_task);
}
//Do not Free
I64 *UpdateUI(CUIElem *update,I64 msg_type,I64 m1,I64 m2,I64 right_x=GR_WIDTH,I64 right_y=GR_HEIGHT) {
  CUIElem *chain,**body=update->sub_elems->items->body,*drag;
  I64 x,y,got,cnt=update->sub_elems->items->cnt,idx;
  U8 *cb;
  static I64 ret_code=0,drag_start_x=0,drag_start_y=0;
  ret_code=0;
//Keyboard events only happen on focused elems
  switch(msg_type) {
    case MSG_MS_MOVE:
    case MSG_MS_L_DOWN:
    case MSG_MS_R_DOWN:
    case MSG_MS_L_UP:
    case MSG_MS_R_UP:
//All is good;
      break;
    start:
      cb=NULL;
      case MSG_KEY_UP:
        if(update&&update->kbd_up)
	  cb=update->kbd_up;
        break;
      case MSG_KEY_DOWN:
        if(update&&update->kbd_down) {
	  cb=update->kbd_down;
        }
        break;
    end:
//These are handled by the focused silly sauce
      if(update==FramePtr(UI_FOCUS_FPTR)&&ThingHasClass(cb,"CFrogBlock")) {
        ThingDel(FrogBlockValue(cb,update,FrogChrNew(m1),FrogNumNew(m2&0xff)));
        ret_code=TRUE;
        return &ret_code;
      }
      goto pass;
  }
  x=update->computed_x;
  y=update->computed_y;
  if(x<=m1<=x+update->sz_x)
    if(y<=m2<=y+update->sz_y) {
      goto pass;
    }
  goto fail;
pass:
  if(!(update->update_parent_first))
    for(idx=0;idx!=cnt;idx++) {
      if(chain=UpdateUI(body[idx],msg_type,m1,m2,x+body[idx]->sz_x,y+body[idx]->sz_y)) {
        return chain;
      }
    }
  cb=NULL;
  switch(msg_type) {
    case MSG_MS_MOVE:
      cb=update->ms_move;
      if(ms.lb&&update->ms_ldown)
        cb=update->ms_ldown;
      else if(ms.rb&&update->ms_rdown)
        cb=update->ms_rdown;
      goto ms_cb;
    case MSG_MS_L_UP:
      FramePtrDel(UI_FOCUS_FPTR);
      if(ThingHasClass(update->drag_end,"CFrogBlock")) {
        if(m1!=drag_start_x||m2!=drag_start_y) {
	  if(drag=FramePtr(UI_GRID_DRAG_FPTR)) {
	    ThingDel(FrogBlockValue(update->drag_end,
		  FrogIncRefCnt(update),
		  FrogNumNew(m1-x),
		  FrogNumNew(m2-y),
		  drag
		  ));
	    FramePtrDel(UI_GRID_DRAG_FPTR);
	    ret_code=TRUE;
	    return &ret_code;
	  }
        } else  {
	  if(drag=FramePtr(UI_GRID_DRAG_FPTR)) {
	    cb=drag->ms_lup;
	    FramePtrDel(UI_GRID_DRAG_FPTR);
	    goto ms_cb;
	  }
	}
      } else if(ThingHasClass(update,"CUITextBar")) {
	FramePtrAdd(UI_FOCUS_FPTR,update);
        ret_code=TRUE;
        return &ret_code;
      }
      cb=update->ms_lup;
      goto ms_cb;
    case MSG_MS_L_DOWN:
      if(ThingHasClass(update->drag_start,"CFrogBlock")) {
        if(!FramePtr(UI_GRID_DRAG_FPTR)) {
	  FramePtrDel(UI_GRID_DRAG_FPTR);
	  drag=FrogBlockValue(update->drag_start,
	        FrogIncRefCnt(update),
	        FrogNumNew(m1-x),
	        FrogNumNew(m2-y)
	  );
	  drag_start_x=m1;
	  drag_start_y=m2;
	  if(ThingHasClass(drag,"CUIGridItem"))
	    FramePtrAdd(UI_GRID_DRAG_FPTR,drag);
	  else
	    ThingDel(drag);
	  ret_code=TRUE;
	  return &ret_code;
        }
      }
      cb=update->ms_ldown;
      goto ms_cb;
    case MSG_MS_R_UP:
      cb=update->ms_rup;
      goto ms_cb;
    case MSG_MS_R_DOWN:
      cb=update->ms_rdown;
ms_cb:
      if(ThingHasClass(cb,"CFrogBlock")) {
        ThingDel(FrogBlockValue(cb,
	      FrogIncRefCnt(update),
	      FrogNumNew(m1-x),
	      FrogNumNew(m2-y)
        ));
        ret_code=TRUE;
        return &ret_code;
      }

  }
  if(update->update_parent_first) {
    for(idx=0;idx!=cnt;idx++) {
      update=body[idx];
      if(chain=UpdateUI(update,msg_type,m1,m2,x+update->sz_x,y+update->sz_y)) {
        return chain;
      }
    }
  }
fail:;
  return NULL;
}
//
// Chat Log section
//
U0 UIChatLogInit(CUIChatLog *log)  {
  log->lines=FrogArrayNew;
  log->sub_elems=FrogArrayNew;
}
U0 UIChatLogDraw(CDC *dc,I64 xoff,I64 yoff,CUIChatLog *log) {
  I64 cnt=log->lines->items->cnt,idx=0,cap_x=log->sz_x/8,total;
  I64 xoff2,idx2,yoff2,lines,line_idx;
  CFrogStr *ln;
  U8 *ln_text;
  if(log->bg_color!=TRANSPARENT) {
    dc->color=log->bg_color;
    GrRect(dc,xoff,yoff,log->sz_x,log->sz_y);
  }
  yoff2=log->sz_y/8;
  dc->color=log->fg_color;
  for(line_idx=0;line_idx!=cnt;line_idx++) {
    ln=log->lines->items->body[line_idx];
    ln_text=AsString(ln);
    total=StrLen(ln_text);
    lines=total/cap_x;
    if(total%cap_x)
      lines++;
    yoff2-=lines;
    if(yoff2+lines<=0) {
      Free(ln_text);
      break;
    }
    xoff2=0;
    dc->color=log->fg_color;
    for(idx2=0;idx2!=StrLen(ln_text);idx2++) {
      if(yoff2>=0)
        GrPutChar(dc,xoff+8*xoff2,yoff+8*yoff2,ln_text[idx2]);
      xoff2++;
      if(xoff2>=cap_x) {
        xoff2=0;
        yoff2++;
      }
    }
    if(total%cap_x)
      yoff2++;
    yoff2-=lines;
    Free(ln_text);
    idx++;
  }
fin:;
}
//
// Background section
//
U0 UIElemInit(CUIElem *log)  {
  log->sub_elems=FrogArrayNew;
}
U0 UIBackgroundDraw(CDC *dc,I64 xoff,I64 yoff,CUIBackground *bg) {
  dc->color=bg->bg_color;
  GrRect(dc,xoff,xoff,bg->sz_x,bg->sz_y);
}

//
// Label
//
U0 UILabelInit(CUILabel *label) {
  label->label=FrogStrNew("");
  UIElemInit(label);
}
U0 UILabelDraw(CDC *dc,I64 xoff,I64 yoff,CUILabel *label) {
  U8 *str=AsString(label->label);
  dc->color=label->color;
  GrPutS(dc,xoff,yoff,str);
  label->sz_x=StrLen(str)*8;
  label->sz_y=8;
  Free(str);
}
//
//Button
//
U0 UIButtonInit(CUIButton *btn) {
  btn->label=FrogStrNew("");
  UIElemInit(btn);
}
U0 UIButtonDraw(CDC *dc,I64 xoff,I64 yoff,CUIButton *button) {
   U8 *str=AsString(button->label);
   I64 sw=StrLen(str)*8;
   dc->color=button->bg_color;
//Perhaps not assigned
   if(button->sz_x<sw+12) button->sz_x=sw+12;
   if(!button->sz_y) button->sz_y=12;
   GrRect(dc,xoff,yoff,button->sz_x,button->sz_y);
   dc->color=button->fg_color;
   GrPutS(dc,
	xoff+button->sz_x/2-sw/2,
	yoff+button->sz_y/2-8/2,
	str
	);
   Free(str);
}
//
// Health Meter section
//
U0 UIMeterInit(CUIMeter *meter) {
  meter->str=FrogStrNew("");
  meter->sz_x=100;
  meter->sz_y=100;
  UIElemInit(meter);
}
U0 UIMeterDraw(CDC *dc,I64 xoff,I64 yoff,CUIMeter *meter) {
  I64 h,w,x,y,xoff2;
  U8 *str;
  F64 rad;
  dc->color=meter->border_color;
  dc->thick=4;
  x=xoff;
  y=yoff;
  GrFillCircle(dc,x,y,,meter->sz_x);
  dc->color=meter->bg_color;
  GrFillCircle(dc,x,y,,meter->sz_x-4);
  h=MaxI64((meter->sz_y-4)*meter->value/ToF64(meter->max),0);
  y=yoff+meter->sz_x-4;
  rad=(meter->sz_x-4)/2;
  dc->color=meter->fg_color;
  y=yoff;
  xoff2=0;
  while(GrPeek(dc,x+xoff2,rad+y-h)==meter->bg_color)
    xoff2++;
  dc->color=meter->fg_color;
  GrLine(dc,xoff2+x,rad+y-h,x-xoff2,rad+y-h); 
  if(h)
   GrFloodFill(dc,x,MaxI64(rad+y-1,rad+y-h/2-1));
  dc->color=meter->text_color;
  y=yoff;
  x=xoff;
  if(str=AsString(meter->str))
    GrPutS(dc,x-StrLen(str)*8/2,y-4,str);
  Free(str);
}
//
// TextBar section
//
//
U0 UITextBarInit(CUITextBar *bar) {
  bar->buf=FrogStrNew("");
  UIElemInit(bar);
}
U0 UITextBarDraw(CDC *dc,I64 xoff,I64 yoff,CUITextBar *bar) {
  U8 *p,*buf=AsString(bar->buf);
  I64 len;
  dc->color=bar->bg_color;
  GrRect(dc,xoff,yoff,bar->sz_x,bar->sz_y);
  if(bar->view_pos<=StrLen(buf)) {
    dc->color=bar->fg_color;
    p=MAlloc(bar->sz_x/8+1);
    len=MinI64(bar->sz_x/8,StrLen(buf+bar->view_pos));
    MemCpy(p,buf+bar->view_pos,len);
    p[len]=0;
    GrPutS(dc,xoff,yoff,p);
    Free(p);
enter:
    if(bar->view_pos<=bar->cur_pos<=bar->view_pos+bar->sz_x/8) {
      dc->color=ROP_XOR|0xf;
      GrRect(dc,xoff+8*(bar->cur_pos-bar->view_pos),yoff,8,8);
    } else {
       bar->view_pos=bar->cur_pos;
       goto enter;
    }
  }
  if(bar->border_color!=TRANSPARENT) {
    dc->color=bar->border_color;
    dc->thick=4;
//Left
    GrLine3(dc,xoff-2,yoff-2,0,xoff-2,yoff+bar->sz_y+2,0);
//Right
    GrLine3(dc,bar->sz_x+xoff+2,yoff-2,0,bar->sz_x+xoff+2,yoff+bar->sz_y+2,0);
//Top
    GrLine3(dc,xoff-2,yoff-2,0,xoff+bar->sz_x+2,yoff-2,0);
//Bottom
    GrLine3(dc,xoff-2,yoff+bar->sz_y+2,0,xoff+bar->sz_x,yoff+bar->sz_y+2,0);
    dc->thick=1;
  }
  Free(buf);
}
// ScrollBar sectiob
//
U0 UIScrollBarsDraw(CDC *dc,I64 xoff,I64 yoff,CUIScrollBars *scroll) {
  I64 w=0,h=0,sx,sy,cnt;
  I64 mat[16];
  Mat4x4IdentEqu(mat);
  F64 sbh,sbw;
  CUIElem **body=scroll->sub_elems->items->body,*sub;
  I64 elem_cnt=scroll->sub_elems->items->cnt;
  CDC *dummy=DCNew(scroll->sz_x,scroll->sz_y);
  DCFill(dummy,scroll->bg_color);
  for(cnt=0;cnt!=elem_cnt;cnt++) {
    sub=body[cnt];
    w=MaxI64(w,sub->x+sub->sz_x);
    h=MaxI64(h,sub->y+sub->sz_y);
  }
  sx=MaxI64(scroll->x_scroll,0);
  sy=MaxI64(scroll->y_scroll,0);
  if(w<=scroll->sz_x) {
    sx=0;
  } else if(sx>w-scroll->sz_x) {
    sx=w-scroll->sz_x;
  }
  scroll->x_scroll=sx;

  if(h<=scroll->sz_y) {
    sy=0;
  } else if(sy>h-scroll->sz_y) {
    sy=h-scroll->sz_y;
  }
  scroll->y_scroll=sy;

  for(cnt=0;cnt!=elem_cnt;cnt++) {
    sub=body[cnt];
    RenderUI(dummy,sub,
	-sx,
	-sy,
	scroll->sz_x,scroll->sz_y);
  }
  GrBlot(dc,xoff,yoff,dummy);
  DCDel(dummy);
  if(h>scroll->sz_y) {
    sbh=ToF64(scroll->sz_y)/h*scroll->sz_y;
    dc->color=YELLOW;
    GrRect(dc,xoff+scroll->sz_x-8,yoff+scroll->sz_y*(sy/ToF64(h)),8,sbh);
  }
  if(w>scroll->sz_x) {
    sbw=w/ToF64(scroll->sz_x);
    dc->color=YELLOW;
    GrRect(dc,xoff+scroll->sz_x*(sx/ToF64(w))-sbw,yoff+scroll->sz_y-8,8,sbw);
  }
}
//
// Center Section
//
U0 UICenterDraw(CDC *dc,I64 xoff,I64 yoff,CUICenter *center) {
  I64 x,y,w=0,h=0,i;
  CUIElem **body=center->sub_elems->items->body,*sub;
  I64 elem_cnt=center->sub_elems->items->cnt;
  for(x=0;x!=elem_cnt;x++) {
    sub=body[x];
    w=MaxI64(w,sub->x+sub->sz_x);
    h=MaxI64(w,sub->y+sub->sz_y);
  }
  if(center->x_center) {
    if(center->parent) {
      x=center->parent->sz_x/2-w/2;
    } else {
      x=Fs->pix_width/2-w/2;
    }
  } else
    x=0;
  if(center->y_center) {
    if(center->parent) {
      y=center->parent->sz_y/2-h/2;
    } else {
      y=Fs->pix_height/2-h/2;
    }
  } else
    y=0;
  x=center->computed_x=xoff+x;
  y=center->computed_y=yoff+y;
  center->sz_x=w;
  center->sz_y=h;
  for(i=0;i!=elem_cnt;i++) {
    RenderUI(dc,body[i],x,y,x+w,y+h);
  }
}
//
// Item Grid Section
//
#define UI_GRID_WIDTH 32
#define UI_GRID_PAD 8
CFrogThing *UIGridItemSetGr(CUIGridItem *self,...) {
  CFrogStr *who=argv[0];
  U8 *name=AsString(who),*l;
  CDC *raw;
  l=BlobFileGetLump("ASS",name);
  if(self->graphics) AnimDCDel(self->graphics);
  raw=AnimDCLoad(l);
  self->graphics=ScaleDC(raw,24,24,frog_mem_task);
  Free(l);
  Free(name);
  AnimDCDel(raw);
  ThingDel(who);
  return FROG_SMALL_NIL;
}
AddMethod("CUIGridItem","setGraphics:",&UIGridItemSetGr);
U0 UIGridItemDel(CUIGridItem *i) {
  AnimDCDel(i->graphics);
  Free(i);
}
U0 UIGridItemDraw(CDC *dc,I64 x,I64 y,CUIGridItem *self) {
  U8 *str;
  if(ThingHasClass(self->parent,"CUIGrid"))
    if(self->parent(CUIGrid*)->active==self) {
      if(Blink)
        dc->color=RED;
      else
        dc->color=BLUE;
      GrRect(dc,x+UI_GRID_PAD/2,y+UI_GRID_PAD/2,UI_GRID_WIDTH-UI_GRID_PAD,UI_GRID_WIDTH-UI_GRID_PAD);
    }
  if(self->graphics)
    AnimDCBlot(dc,x+UI_GRID_PAD/2,y+UI_GRID_PAD/2,self->graphics);
  if(self->cnt) {
    str=MStrPrint("%d",self->cnt);
    x=x+UI_GRID_WIDTH/2-StrLen(str)*8/2;
   y=y+UI_GRID_WIDTH-4;
    dc->color=WHITE;
    GrPutS(dc,x,y,str);
    Free(str);
  }
}

U0 UIGridDraw(CDC *dc,I64 x,I64 y,CUIGrid *self) {
  dc->color=DKGRAY;
  GrRect(dc,x,y,self->sz_x,self->sz_y);
  I64 gx=0,gy=0;
  for(gx=0;gx!=self->grid_w;gx++) {
    for(gy=0;gy!=self->grid_h;gy++) {
      dc->color=BLACK;
      GrRect(dc,
	x+gx*UI_GRID_WIDTH+UI_GRID_PAD/2,
	y+gy*UI_GRID_WIDTH+UI_GRID_PAD/2,
	UI_GRID_WIDTH-UI_GRID_PAD,
	UI_GRID_WIDTH-UI_GRID_PAD);      
    }
  }
}
FrogSymbol("ui_root");
U0 DrawUIRoot(CTask *t,CDC *dc) {
  CFrogSymbol *s=FrogSymbol("ui_root");
  CUIElem *e;
  I64 oldx,oldy;
  if(ThingHasClass(s->value,"CUIElem")) {
    RenderUI(dc,s->value,0,0,t->pix_width,t->pix_height);
  }
  if(e=FramePtr(UI_GRID_DRAG_FPTR,t)) {
    oldx=e->x;
    oldy=e->y;
    e->x=0;
    e->y=0;
    RenderUI(dc,e,ms.pos.x-t->pix_left,ms.pos.y-t->pix_top,t->pix_width,t->pix_height);
    e->x=oldx;
    e->y=oldy;
  }
}

U0 LoadColorSyms() {
  I64 c=0;
  U8 *tmp;
  while(c<16) {
    tmp=MStrPrint("#color_%s _ %d .",DefineSub(c,"ST_COLORS"),c);
    STRunStmt(tmp);
    Free(tmp);
    c++;
  }
}
LoadColorSyms;
#if__CMD_LINE__
STRunStmt("#ui_root _ CUIScrollBars new .\n");
STRunStmt("#ui_root setWidth: 400 ; setHeight: 100 .\n");
STRunStmt("#ui_label _ CUILabel new .\n");
STRunStmt("#ui_label setLabel: 'I was here';setX: 50;setY: 50 .");
STRunStmt("#ui_root addChild: #ui_label .");
STRunStmt("#ui_bttn _ CUIButton new .\n");
STRunStmt("#ui_bttn setX:50 ;setY: 60 ; setLabel: 'Press Me' .\n");
STRunStmt("#ui_bttn onLeftClick: [:s :x :y | #ui_bttn setLabel: 'Pressed' ; setBackgroundColor: #color_LTGREEN  ] .\n");
STRunStmt("#ui_root addChild: #ui_bttn .");
STRunStmt("#ui_meter _ CUIMeter new .\n");
STRunStmt("#ui_meter setMax: 100 ; setValue: 60 ;setLabel: 'abc'.\n");
STRunStmt("#ui_meter setX:20 ;setY: 100 .\n");
STRunStmt("#ui_root addChild: #ui_meter .");
STRunStmt("#ui_grid _ CUIGrid new .");
STRunStmt("#ui_grid setWidth: 5 withHeight: 2 .");
STRunStmt("#ui_grid_item _ CUIGridItem new .");
STRunStmt("#ui_grid_item setCount: 123 .");
STRunStmt("#ui_grid addItem: #ui_grid_item .");
STRunStmt("#ui_grid setX: 200 .");
STRunStmt("#ui_grid setY: 10 .");
STRunStmt("#ui_root addChild: #ui_grid .");
Fs->draw_it=&DrawUIRoot;
I64 msg,m1,m2;;
U0 UITest() {
  while(TRUE) {
    while(msg=ScanMsg(&m1,&m2)) {
      UpdateUI(FrogSymbol("ui_root")->value,msg,m1,m2);
    }
    Refresh;
  }
}
//UITest;
//Uf("RenderUI");
#endif
#endif
