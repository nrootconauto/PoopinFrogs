#exe {Cd(__DIR__);}
#include "AnimDC.HC"
#include "BlobFile.HC"
#include "FileBMP.HC";
class CUndoLayer:CQue {
  CDC *anim_dc;
  I64 at_frame;
};
class CCutoutCut:CQue {
  I64 x,y,x2,y2;
};
class CCutout {
  CDC *gr;
};

U0 PasteHelpPopUp() {
  if(!FramePtr("HelpPaste")) {
    FramePtrAdd("HelpPaste",1);
    PopUpOk("Use mouse wheel to rotate paste\n"
    "Use Shift-key and mouse wheel to scale\n");
  }
}
U0 CutHelpPopUp() {
  if(!FramePtr("HelpCut")) {
    FramePtrAdd("HelpCut",1);
    PopUpOk("Use left click to add points to the clipboard polygon\n"
	"Use right click to finish shape.\n");
  }
}

class CTextureEditor {
  CDC *screen;
//This is for tracing against a background image
  CDC *trace_image;
  CQue undo;
  I32 thick,color;
#define TOOL_PAINT 0
#define TOOL_FILL  1
#define TOOL_LINE  2
#define TOOL_COLOR 3
#define TOOL_THICK 4
#define TOOL_PICK_FRAME 5
#define TOOL_SET_BOUNDS 6
#define TOOL_DELETE_FRAME 7
#define TOOL_UNDO 8
#define TOOL_POLY_LINE 9
#define TOOL_ELLIPSE 10
#define TOOL_ERASE 11
#define TOOL_COPY 12
#define TOOL_CUT 13
#define TOOL_PASTE 14
#define TOOL_CNT 15
  I64 cur_tool,last_tool;
//Used with tools
  I64 last_x,last_y; 
  I64 bound_start_x;
  I64 bound_start_y;
  I64 ms_x,ms_y;
  U8 *filename;
  CDC *frames;
  I64 frame_cnt;
  I64 cur_frame;
  I64 disp_frame_onionskin;
  I64 last_ms_z;
  F64 rotation,scale;
  CQue cutout_cuts;
  CCutout *clipboard;
  Bool ms_left_down,ms_right_down;
  Bool last_ms_left_down;
  Bool painting_line;
  Bool setting_bounds;
  Bool drawing_ellipse;
  Bool anim_paused;
} editor;
U0 CutoutDel(CCutout *clip) {
  DCDel(clip->gr);
  Free(clip);
}
CCutout *MakeCutout(CTextureEditor *ed) {
  CCutoutCut *head=&ed->cutout_cuts,*cut;
  CCutout *ret;
  I64 x,y,w,h,c;
  I64 bx,by,bx2,by2; //Bounds
  CDC *mask=DCNew(ed->screen->width_internal+8,ed->screen->height+8);
  CDC *result=DCNew(ed->screen->width,ed->screen->height);
  CDC *cropped;
  U64 *dst,*src,*bitmask;
  Bool on=FALSE;
//No cuts defined so use whole image
  if(QueCnt(head)<=2) {
    DCFill(mask,1);
    ret=CAlloc(sizeof(CCutout),ed->screen->mem_task);
    ret->gr=mask;
    return ret;
  }
  DCFill(mask,0);
  mask->color=1;
  mask->thick=1;
  w=ed->screen->width;
  h=ed->screen->height;
  bx=I32_MAX;
  by=I32_MAX;
  bx2=I32_MIN;
  by2=I32_MIN;
  for(cut=head->next;cut!=head;cut=cut->next) { 
    bx=MinI64(bx,cut->x);
    bx=MinI64(bx,cut->x2);
    by=MinI64(by,cut->y);
    by=MinI64(by,cut->y2);
    bx2=MaxI64(bx2,cut->x);
    bx2=MaxI64(bx2,cut->x2);
    by2=MaxI64(by2,cut->y);
    by2=MaxI64(by2,cut->y2);
    GrLine3(mask,
	  ClampI64(cut->x,0,w),
	  ClampI64(cut->y,0,h),
	  0,
	  ClampI64(cut->x2,0,w),
	  ClampI64(cut->y2,0,h),
	  0);
  }
  w=mask->width;
  h=mask->height;
//2 is empty
  //1 is full
  //0 is undef
  mask->color=2;
  GrFloodFill(mask,w-1,h-1);
  DCColorChg(mask,0,0xff); //0xff is TRANSPARENT
  DCColorChg(mask,1,0xff);
  DCColorChg(mask,2,0x0);
  DCFill(result,TRANSPARENT);
  w=ed->screen->width_internal;
  h=ed->screen->height;
  for(y=0;y!=h;y++) {
    src=&ed->screen->body[ed->screen->width_internal*y];
    bitmask=&mask->body[mask->width_internal*y];
    dst=&result->body[result->width_internal*y];
    for(x=0;x<w/8;x++) {
//~0 is 0xff(TRANSPARENT)
      *dst=(*bitmask&*src)|~*bitmask;
  //If we are cutting,replace with transparent
      if(ed->cur_tool==TOOL_CUT) {
//Mask if filled with 0xff(TRANSPARENT),so just or that shit
        *src|=*bitmask;
      }
      ++src;
      ++dst;
      ++bitmask;
    }
  }
  DCDel(mask);
  cropped=DCNew(bx2-bx+1,by2-by+1,ed->screen->mem_task);
  DCFill(ed->frames+ed->cur_frame,TRANSPARENT);
  GrBlot(ed->frames+ed->cur_frame,0,0,ed->screen);
  DCFill(cropped,TRANSPARENT);
  GrBlot(cropped,-bx,-by,result);
  DCDel(result);
  ret=CAlloc(sizeof(CCutout),ed->screen->mem_task);
  ret->gr=cropped;
  return ret;
}
U0 TextureEditorDrawMs(CDC *dc,I64 x,I64 y) {
  dc->color=ROP_XOR|WHITE;
  GrFillCircle(dc,x,y,0,3);
  dc->color=editor.color;
  dc->thick=1;
  GrCircle3(dc,x,y,0,editor.thick/2);
}
U0 TextureEditorAddUndo(CTextureEditor *ed) {
  CUndoLayer *undo=CAlloc(sizeof(CUndoLayer),ed->screen->mem_task);
  undo->anim_dc=AnimDCCopy(ed->frames,ed->screen->mem_task);
//Froce update the screen to the DC
  GrBlot(undo->anim_dc+ed->cur_frame,0,0,ed->screen);
  undo->at_frame=ed->cur_frame;
  QueIns(undo,ed->undo.last);
}
U0 _TextureEditorAddCut(CTextureEditor *ed,I64 x,I64 y,I64 x2,I64 y2) {
  CCutoutCut *cut=CAlloc(sizeof(CCutoutCut),ed->screen->mem_task);
  cut->x=x,cut->y=y;
  cut->x2=x2,cut->y2=y2;
  QueIns(cut,ed->cutout_cuts.last);
}
U0 TextureEditorUndo(CTextureEditor *ed) {
  if(!QueCnt(&ed->undo))
    return;
  CUndoLayer *layer=ed->undo.last;
  AnimDCDel(ed->frames);
  ed->frames=layer->anim_dc;
  ed->cur_frame=layer->at_frame;
  DCDel(ed->screen);
  ed->screen=DCNew(ed->frames->width,ed->frames->height,ed->frames->mem_task);
  DCFill(ed->screen,TRANSPARENT);
  GrBlot(ed->screen,0,0,ed->frames+ed->cur_frame);
  QueRem(layer);
  Free(layer);
}
U0 TextureEditorDel(CTextureEditor *ed) {
  DCDel(ed->screen);
  Free(ed);
}
#define SIDEBAR_WIDTH 64
U0 DrawSidebar(CTask *t,CDC *dc,CTextureEditor *ed) {
  I64 tool,x,y=0;
  U64 ch;
  dc->color=WHITE;
  GrRect(dc,0,0,SIDEBAR_WIDTH,t->pix_height);
  for(tool=0;tool!=TOOL_CNT;tool++) {
    if(ed->cur_tool==tool) {
      dc->color=BLUE;
      GrRect(dc,0,y,SIDEBAR_WIDTH,8);
      dc->color=RED;
    } else
      dc->color=BLACK;
    switch(tool) {
      case TOOL_PAINT:
	ch='[Paint ]';
	break;
      case TOOL_FILL:
	ch='[Fill  ]';
	break;
      case TOOL_LINE:
	ch='[Line  ]';
	break;
      case TOOL_COLOR:
	ch='[Color ]';
	if(Blink)
	  dc->color=ed->color&0xf;
	break;
      case TOOL_THICK:
	ch='[Thick ]';
	break;
      case TOOL_PICK_FRAME:
	ch='[Frame ]';
	break;
      case TOOL_SET_BOUNDS:
	ch='[SetBnd]';
	break;
      case TOOL_DELETE_FRAME:
	ch='[Delete]';
	break;
      case TOOL_UNDO:
	ch='[Undo  ]';
	break;
      case TOOL_POLY_LINE:
	ch='[PolyLn]';
	break;
      case TOOL_ELLIPSE:
	ch='[Elipse]';
	break;
      case TOOL_ERASE:
	ch='[Erase ]';
	break;
      case TOOL_COPY:
	ch='[Copy  ]';
	break;
      case TOOL_CUT:
	ch='[Cut   ]';
	break;
      case TOOL_PASTE:
        if(!ed->clipboard)
	  dc->color=LTGRAY;
	ch='[Paste ]';
	break;
    }
    GrPrint(dc,0,y,"%c",ch);
    if(ed->ms_left_down)
      if(0<=ed->ms_x<SIDEBAR_WIDTH)
        if(y<=ed->ms_y<y+8) {
	  ed->cur_tool=tool;
	  switch(tool) {
	    case TOOL_PAINT:
	    case TOOL_FILL:
	    case TOOL_LINE:
	    case TOOL_POLY_LINE:
	    case TOOL_ELLIPSE:
	    case TOOL_ERASE:
	    case TOOL_CUT:
	    case TOOL_COPY:
	    case TOOL_PASTE:
	      ed->painting_line=FALSE;
	      ed->setting_bounds=FALSE;
	      ed->drawing_ellipse=FALSE;
	      ed->last_tool=tool;
	      break;
	  }
	}
    y+=8;
  }
  dc->color=LTRED;
  y+=24;
  GrPrint(dc,0,y,"[Frames]");
  y+=8;
  for(tool=0;tool!=3;tool++) {
    switch(tool) {
      case 0:
	dc->color=BLUE;
	ch='[-]Prev ';
	break;
      case 1:
	dc->color=BLUE;
	ch='[+]Next ';
	break;
      case 2:
	if(ed->anim_paused) {
	  dc->color=LTGREEN;
	  ch='[P]Play ';
	} else {
	  dc->color=RED;
	  ch='[P]Pause';
	}
    }
    GrPrint(dc,0,y,"%c",ch);
    y+=8;
  }
}
F64 Lerp(F64 per,F64 min,F64 max) {
  return Clamp(per*(max-min)+min,min,max);
}
U0 DrawEditor(CTask *t,CDC *dc) {
  I64 w,x,y,idx,h,mat[16],w2,x2,y2;
  CTextureEditor *ed=&editor;
  U8 *base;
  CDC *dither_mask,*paste,*alias;
  CUndoLayer *undo_layer;
  CCutoutCut *cut;
  DrawSidebar(t,dc,ed);
  TextRect(t->win_left,t->win_right,t->win_top,t->win_bottom,DKGRAY<<12);
  dc->color=LTGRAY;
  w=t->pix_width-SIDEBAR_WIDTH;
  h=t->pix_height;
  x=SIDEBAR_WIDTH+w/2-ed->screen->width/2;
  y=t->pix_height/2-ed->screen->height/2;
  if(!ed->trace_image) {
    GrRect(dc,
	  x,
	  y,
	  ed->screen->width,
	  ed->screen->height
	  );
  } else {
    alias=ed->trace_image;
      for(y2=0;y2!=ed->screen->height;y2++) {
       for(x2=0;x2!=ed->screen->width;x2++) {
	dc->color=GrPeek(alias,
	  Lerp(x2/ToF64(ed->screen->width),
	    0,
            alias->width),
	  Lerp(y2/ToF64(ed->screen->height),
	    0,
	    alias->height
	  )
	);
	GrPlot(dc,x+x2,y+y2);
      }
    }
  }
  if(ed->anim_paused) {
    GrBlot(dc,x,y,ed->frames+ClampI64(ed->disp_frame_onionskin,0,ed->frame_cnt));
  } else
    AnimDCBlot(dc,x,y,ed->frames);

  dither_mask=DCNew(ed->frames->width,ed->frames->height);
  DCFill(dither_mask,RED);
  dither_mask->color=ROPF_DITHER;
  dither_mask->color.c0.color=TRANSPARENT;
  dither_mask->color.c1.color=LTGRAY;
  GrFloodFill(dither_mask,0,0);

  GrBlot(dc,x,y,dither_mask);
  DCDel(dither_mask);
  GrBlot(dc,x,y,ed->screen);
  if(ed->painting_line&&ed->cur_tool!=TOOL_ERASE) {
    dc->thick=ed->thick;
    dc->color=ed->color;
    GrLine3(dc,
	  ed->ms_x,
	  ed->ms_y,
	  0,
	  ed->last_x,
	  ed->last_y,
	  0
	  );
  }
  if(ed->setting_bounds) {
    dc->color=RED;
    dc->thick=4;
    x=MinI64(ed->bound_start_x,ed->ms_x);
    y=MinI64(ed->bound_start_y,ed->ms_y);
    w=AbsI64(ed->bound_start_x-ed->ms_x);
    h=AbsI64(ed->bound_start_y-ed->ms_y);
    GrBorder(dc,x,y,x+w,y+h);
  }
  if(ed->drawing_ellipse) {
    dc->thick=ed->thick;
    dc->color=ed->color;
    x=MinI64(ed->ms_x,ed->last_x);
    y=MinI64(ed->ms_y,ed->last_y);
    w=AbsI64(ed->last_x-ed->ms_x);
    h=AbsI64(ed->last_y-ed->ms_y);
    GrEllipse3(dc,x+w/2,y+h/2,0,w/2,h/2);
  }
  if(ed->cur_tool==TOOL_CUT||ed->cur_tool==TOOL_COPY) {
    dc->thick=2;
    dc->color=ROP_XOR|WHITE;
    x=SIDEBAR_WIDTH+(t->pix_width-SIDEBAR_WIDTH)/2-ed->screen->width/2;
    y=t->pix_height/2-ed->screen->height/2;
    for(cut=ed->cutout_cuts.next;cut!=&ed->cutout_cuts;cut=cut->next) {
      GrLine3(dc,
	    cut->x+x,
	    cut->y+y,
	    0,
	    cut->x2+x,
	    cut->y2+y,
	    0
	    );
    }
    if(QueCnt(&ed->cutout_cuts)>=2) {
      GrLine3(dc,
	    ed->cutout_cuts.next(CCutoutCut*)->x+x,
	    ed->cutout_cuts.next(CCutoutCut*)->y+y,
	    0,
	    ed->ms_x,
	    ed->ms_y,
	    0
	    );

    }
  }
  if(ed->cur_tool==TOOL_PASTE&&ed->clipboard) {
    paste=ed->clipboard->gr;
    if(paste) {
      w2=MaxI64(paste->height,paste->width);
      alias=DCNew(2*w2*Max(ed->scale,1)+100,2*w2*Max(ed->scale,1)+100);
      DCFill(alias,TRANSPARENT);
      alias->r=mat;
      alias->flags|=DCF_TRANSFORMATION;
      Mat4x4IdentEqu(mat);
      w=paste->width;
      h=paste->height;
      w2=alias->width/2;
      Mat4x4TranslationAdd(mat,-w/2-w2,-h/2-w2,0);
      if(Bt(kbd.down_bitmap,SC_SHIFT))
        Mat4x4RotY(mat,pi);
      Mat4x4RotZ(mat,ed->rotation);
      Mat4x4Scale(mat,ed->scale);
      Mat4x4TranslationAdd(mat,w/2+w2,h/2+w2,0);
      GrBlot3(alias,w2,w2,0,paste);
      alias->r=NULL;
      GrBlot(dc,ed->ms_x-w2,ed->ms_y-w2,alias);
      DCDel(alias);
    }
  }
}
//Takes a list of frames to animate
//Write_name_to will write the name of the lump to(must be STR_LEN bytes long)
U0 _TextureEdit(CDC **_image,U8 *blob_file=NULL,U8 *write_to_name=NULL) {
  CDC*image=*_image,*mask,mat[16];
  I64 w2,w,h,msg;
  CDC *paste,*dummy;
  I64 m1,m2,vis_x,vis_y,x,y,x2,y2,delta;
  Bool continue=TRUE,abort=FALSE;
  U8 *old_draw_ms=gr.fp_draw_ms;
  U8 *trace;
  CTextureEditor *ed=&editor;
  CUndoLayer *undo_layer;
  MemSet(ed,0,sizeof(CTextureEditor));
  CDC *frames=AnimDCCopy(*_image,Fs),*tmp;
  QueInit(&ed->undo);
  QueInit(&ed->cutout_cuts);
  ed->frame_cnt=AnimDCCnt(frames);
  ed->frames=frames;
  ed->last_ms_z=ms.pos.z;
  ed->thick=2;
  ed->color=RED;
  ed->screen=DCCopy(image,image->mem_task);
  SettingsPush;
  gr.fp_draw_ms=&TextureEditorDrawMs;
  MenuPush(
        "File {"
        "  SaveAs(,CH_CTRLA);"
        "  Undo(,CH_CTRLZ);"
        "  Exit(,CH_ESC);"
        "  Abort(,CH_SHIFT_ESC);"
        "}"
        "Frames {"
        "  Next(,'+');"
        "  Prev(,'-');"
        "  Play(,'P');"
        "  Pick(,'F');"
        "  Delete(,'d');"
        "}"
        "Tools {"
        "  SetBounds(,'B');"
        "  Paint(,'p');"
        "  Line(,'l');"
        "  PolyLine(,'L');"
        "  Fill(,'f');"
        "  Color(,'c');"
        "  Thick(,'t');"
        "  Ellipse(,'E');"
        "  Erase(,'e');"
        "}"
        ""
        );
  DocClear;
  Fs->draw_it=&DrawEditor;
//See WinQueIPMsgs,needed to avoid waiting for dbl click
  Bts(&(Fs->win_inhibit),WIf_FOCUS_TASK_MS_L_D);
  Bts(&(Fs->win_inhibit),WIf_FOCUS_TASK_MS_R_D);
  while(continue) {
    vis_x=SIDEBAR_WIDTH+(Fs->pix_width-SIDEBAR_WIDTH)/2-ed->screen->width/2;
    vis_y=Fs->pix_height/2-ed->screen->height/2;
    ed->last_ms_left_down=ed->ms_left_down;
    delta=ms.pos.z-ed->last_ms_z;
    if(ed->cur_tool==TOOL_PASTE&&delta) {
      if(Bt(kbd.down_bitmap,SC_SHIFT)) {
	ed->scale-=delta*1/10.;
      } else 
	ed->rotation+=delta*1/25.;
    }else if(delta)
      ed->thick=MaxI64(ed->thick-delta,1);
    ed->last_ms_z=ms.pos.z;
    while(msg=ScanMsg(&m1,&m2))
    switch(msg) {
      case MSG_MS_MOVE:
        ed->ms_x=m1;
        ed->ms_y=m2;
        break;
      case MSG_MS_R_UP:
        ed->ms_right_down=FALSE;
        break;
      case MSG_MS_R_DOWN:
        ed->ms_right_down=TRUE;
        break;
      case MSG_MS_L_DOWN:
        if(!ed->ms_left_down) {
	  if(
	        ed->cur_tool==TOOL_PAINT
	        ||ed->cur_tool==TOOL_ERASE
	        ||ed->cur_tool==TOOL_LINE
	        ||ed->cur_tool==TOOL_FILL
	  ) {
	    if(0<=m1-vis_x<ed->frames->width)
	      if(0<=m2-vis_y<ed->frames->height)
	        TextureEditorAddUndo(ed);
	    ed->last_x=m1;
	    ed->last_y=m2;
	  }
	  if(
	        (ed->cur_tool==TOOL_POLY_LINE
	        ||ed->cur_tool==TOOL_CUT
	        ||ed->cur_tool==TOOL_COPY
	        )&&!ed->painting_line) {
//POLY_LINE will insert an undo for each line
	    //	    TextureEditorAddUndo(ed);
	    ed->last_x=m1;
	    ed->last_y=m2;
	  }
	  if(ed->cur_tool==TOOL_SET_BOUNDS) {
	    ed->bound_start_x=m1;
	    ed->bound_start_y=m2;
	    ed->setting_bounds=TRUE;
	  } 
	  if(ed->cur_tool==TOOL_LINE
	        ||ed->cur_tool==TOOL_POLY_LINE
	        ||ed->cur_tool==TOOL_CUT
	        ||ed->cur_tool==TOOL_COPY) {
	    ed->painting_line=TRUE;
	  }
	  if(ed->cur_tool==TOOL_ELLIPSE) {
	    ed->drawing_ellipse=TRUE;
	    ed->last_x=m1;
	    ed->last_y=m2;
	  }
        }
        ed->ms_left_down=TRUE;
        break;
      case MSG_MS_L_UP:
        ed->ms_left_down=FALSE;
//Painting will use lines as strokes
        if(ed->cur_tool==TOOL_PAINT||ed->cur_tool==TOOL_ERASE) {
	  ed->painting_line=FALSE;
        }
        break;
      case MSG_KEY_DOWN:
        if(m1==CH_CTRLA) {
	  if(blob_file) {
            if(trace=BlobFileSelect(blob_file)) {
	      StrCpy(write_to_name,trace);
	      Free(trace);
	    }
	  }
        } else if(m1==CH_CTRLZ)
	  TextureEditorUndo(ed);
        else if(m1=='p') {
	  ed->last_tool=ed->cur_tool=TOOL_PAINT;
        }else if(m1=='-'||m1=='_') {
	  ed->disp_frame_onionskin=ClampI64(ed->disp_frame_onionskin-1,0,ed->frame_cnt-1);
        }else if(m1=='+') {
	  ed->disp_frame_onionskin=ClampI64(ed->disp_frame_onionskin+1,0,ed->frame_cnt-1);
        } else if(m1=='P') {
	  ed->anim_paused^=TRUE;
        } else if(m1=='f') {
	  ed->last_tool=ed->cur_tool=TOOL_FILL;
        } else if(m1=='F') {
	  ed->cur_tool=TOOL_PICK_FRAME;
        } else if(m1=='c') {
	  ed->cur_tool=TOOL_COLOR;
        } else if(m1=='t') {
	  ed->cur_tool=TOOL_THICK;
        } else if(m1=='d') {
	  ed->cur_tool=TOOL_DELETE_FRAME;
        } else if(m1=='l') {
	  ed->last_tool=ed->cur_tool=TOOL_LINE;
        } else if(m1=='L') {
	  ed->last_tool=ed->cur_tool=TOOL_POLY_LINE;
        } else if(m1=='B') {
	  ed->last_tool=ed->cur_tool=TOOL_SET_BOUNDS;
        } else if(m1=='E') {
	  ed->last_tool=ed->cur_tool=TOOL_ELLIPSE;
        } else if(m1=='e') {
	  ed->last_tool=ed->cur_tool=TOOL_ERASE;
        } else if(m1==CH_CTRLX) {
	  ed->last_tool=ed->cur_tool=TOOL_CUT;
        } else if(m1==CH_CTRLC) {
	  ed->last_tool=ed->cur_tool=TOOL_COPY;
        } else if(m1==CH_CTRLV) {
	  ed->rotation=0.,ed->scale=1.;
	  ed->last_tool=ed->cur_tool=TOOL_PASTE;
        } else if(m1==CH_CTRLS) {
	  DCFill(ed->frames+ed->cur_frame,TRANSPARENT);
	  GrBlot(ed->frames+ed->cur_frame,0,0,ed->screen);
        } else if(m1==CH_ESC) {
	  DCFill(ed->frames+ed->cur_frame,TRANSPARENT);
	  GrBlot(ed->frames+ed->cur_frame,0,0,ed->screen);
	  continue=FALSE;
	  break;
        } else if(m1==CH_SHIFT_ESC) {
	  abort=TRUE;
	  continue=FALSE;  
	  break;
        } else if(m1==CH_CTRLT) {
          if(trace=PopUpPickFile()) {
	    if(ed->trace_image)
	     DCDel(ed->trace_image);
	    ed->trace_image=BMPRead(trace,TRUE);
	    Free(trace);
	  }
	}
        break;
      default:
        goto next;
    }
    if(!continue)
      break;
    switch(ed->cur_tool) {
      start:
        ed->screen->color=ed->color;
        ed->screen->thick=ed->thick;
        case TOOL_ELLIPSE:
	  if(!ed->ms_left_down&&ed->drawing_ellipse) {
	    TextureEditorAddUndo(ed);
	    ed->drawing_ellipse=FALSE;
	    x=MinI64(ed->ms_x,ed->last_x);
	    y=MinI64(ed->ms_y,ed->last_y);
	    x2=AbsI64(ed->last_x-ed->ms_x);
	    y2=AbsI64(ed->last_y-ed->ms_y);
	    GrEllipse3(ed->screen,x+x2/2-vis_x,y+y2/2-vis_y,0,x2/2,y2/2);
	  }
	  break;
        case TOOL_PASTE:
	  if(ed->ms_left_down) {
	    TextureEditorAddUndo(ed);
	    paste=ed->clipboard->gr;
	    w2=MaxI64(paste->height,paste->width);
	    dummy=DCNew(2*w2*Max(ed->scale,1)+100,2*w2*Max(ed->scale,1)+100);
	    DCFill(dummy,TRANSPARENT);
	    dummy->r=mat;
	    dummy->flags|=DCF_TRANSFORMATION;
	    Mat4x4IdentEqu(mat);
	    w=paste->width;
	    h=paste->height;
	    w2=dummy->width/2;
	    Mat4x4TranslationAdd(mat,-w/2-w2,-h/2-w2,0);
            if(Bt(kbd.down_bitmap,SC_SHIFT))
              Mat4x4RotY(mat,pi);
	    Mat4x4RotZ(mat,ed->rotation);
	    Mat4x4Scale(mat,ed->scale);
	    Mat4x4TranslationAdd(mat,w/2+w2,h/2+w2,0);
	    GrBlot3(dummy,w2,w2,0,paste);
	    dummy->r=NULL;
	    GrBlot(ed->screen,ed->ms_x-vis_x-w2,ed->ms_y-vis_y-w2,dummy);
	    DCDel(dummy);
	  }
	  break;
        case TOOL_ERASE:
	  ed->screen->color=TRANSPARENT;
//Continue into TOOL_PAINT
        case TOOL_PAINT:
	  if(ed->ms_left_down) {
	    if(vis_x<=ed->ms_x<vis_x+ed->screen->width)
	      if(vis_y<=ed->ms_y<vis_y+ed->screen->height) {
	        if(!ed->painting_line) {
		  GrPlot3(ed->screen,ed->ms_x-vis_x,ed->ms_y-vis_y,0);
		  ed->painting_line=TRUE;
	        } else {
		  GrLine3(ed->screen,
		        ed->ms_x-vis_x,
		        ed->ms_y-vis_y,
		        0,
		        ed->last_x-vis_x,
		        ed->last_y-vis_y,
		        0
		        );
	        }
	        ed->last_x=ed->ms_x;
	        ed->last_y=ed->ms_y;
	      }
	  }
	  break;
        case TOOL_FILL:
	  if(ed->ms_left_down)
	    if(vis_x<=ed->ms_x<vis_x+ed->screen->width)
	      if(vis_y<=ed->ms_y<vis_y+ed->screen->height) {
	        GrFloodFill(ed->screen,ed->ms_x-vis_x,ed->ms_y-vis_y);
	      }
	  break;
        case TOOL_POLY_LINE:
	  if(ed->ms_right_down) {
	    ed->painting_line=FALSE;
	  } else if(ed->ms_left_down&&ed->painting_line&&!ed->last_ms_left_down) {
	    if(ed->ms_x!=ed->last_x||ed->ms_y!=ed->last_y) {
	      TextureEditorAddUndo(ed);
	      GrLine3(ed->screen,
		    ed->ms_x-vis_x,
		    ed->ms_y-vis_y,
		    0,
		    ed->last_x-vis_x,
		    ed->last_y-vis_y,
		    0
		    );
	      ed->last_x=ed->ms_x;
	      ed->last_y=ed->ms_y;
	    }
	  }
	  break;
        case TOOL_CUT:
        case TOOL_COPY:
	  if(ed->ms_right_down&&ed->painting_line) {
	    ed->painting_line=FALSE;
//Add a point at our current position
	    _TextureEditorAddCut(ed,
		    ed->last_x-vis_x,
		    ed->last_y-vis_y,
		    ed->ms_x-vis_x,
		    ed->ms_y-vis_y);
//Finish the loop
	    _TextureEditorAddCut(ed,
		  ed->cutout_cuts.next(CCutoutCut*)->x,
		  ed->cutout_cuts.next(CCutoutCut*)->y,
		  ed->cutout_cuts.last(CCutoutCut*)->x2,
		  ed->cutout_cuts.last(CCutoutCut*)->y2
		  );
	    if(ed->clipboard)
	      CutoutDel(ed->clipboard);
	    ed->clipboard=MakeCutout(ed);
	    QueDel(&ed->cutout_cuts);
	    QueInit(&ed->cutout_cuts);
	  } else if(ed->ms_left_down&&ed->painting_line&&!ed->last_ms_left_down) {
	    if(ed->ms_x!=ed->last_x||ed->ms_y!=ed->last_y) {
	      _TextureEditorAddCut(ed,
		    ed->last_x-vis_x,
		    ed->last_y-vis_y,
		    ed->ms_x-vis_x,
		    ed->ms_y-vis_y);
	      ed->last_x=ed->ms_x;
	      ed->last_y=ed->ms_y;
	    }
	  }
	  break;
        case TOOL_LINE:
	  if(!ed->ms_left_down&&ed->painting_line) {
	    GrLine3(ed->screen,
		  ed->ms_x-vis_x,
		  ed->ms_y-vis_y,
		  0,
		  ed->last_x-vis_x,
		  ed->last_y-vis_y,
		  0
		  );
	    ed->painting_line=FALSE;
	  }
      end:
        break;
      case TOOL_DELETE_FRAME:
        if(PopUpNoYes("Would you like to delete the current frame?")) {
	  if(AnimDCCnt(ed->frames)>1) {
	    TextureEditorAddUndo(ed);
	    ed->frame_cnt--;
//3rd argument is exclude
	    tmp=AnimDCCopy(ed->frames,ed->screen->mem_task,ed->cur_frame);
	    if(ed->cur_frame>=ed->frame_cnt)
	      ed->cur_frame--;
	    AnimDCDel(ed->frames);
	    ed->frames=tmp;
	    DCFill(ed->screen,TRANSPARENT);
	    GrBlot(ed->screen,0,0,ed->frames+ed->cur_frame);
	  } else
	    PopUpOk("This is the only Frame!!!");
        }
use_last_tool:;
        if(ed->cur_tool==ed->last_tool)
	  ed->last_tool=TOOL_PAINT;
        ed->cur_tool=ed->last_tool;
        break;
      case TOOL_COLOR:
        ed->color=PopUpColor("Pick a Color\n");
//Dumb hack,prevent mouse from "clicking" against after popup window
	ed->ms_left_down=FALSE;
	goto use_last_tool;
        break;
      case TOOL_THICK:
        ed->thick=PopUpRangeI64(1,16,,"Pick a Thickness\n");
	goto use_last_tool;
        break;
      case TOOL_PICK_FRAME:
        DCFill(ed->frames+ed->cur_frame,TRANSPARENT);
        GrBlot(ed->frames+ed->cur_frame,0,0,ed->screen);
        ed->cur_frame=PopUpRangeI64(1,ed->frame_cnt+1,,"Pick a Frame to Edit\n","Pick Last for a New Frame.")-1;
        if(ed->cur_frame==ed->frame_cnt) {
	  ed->frame_cnt++;
	  frames=CAlloc((ed->frame_cnt+1)*sizeof(CDC),ed->screen->mem_task);
	  tmp=DCNew(ed->screen->width,ed->screen->height,ed->screen->mem_task);
	  DCFill(tmp,TRANSPARENT);
	  MemCpy(frames,ed->frames,(ed->frame_cnt-1)*sizeof(CDC));
	  MemCpy(frames+ed->cur_frame,tmp,sizeof(CDC));
	  Free(ed->frames);
	  ed->frames=frames;
	  GrBlot(ed->frames+ed->cur_frame,0,0,ed->frames+ed->cur_frame-1);
	  Free(tmp);
        }
        DCFill(ed->screen,TRANSPARENT);        
        GrBlot(ed->screen,0,0,ed->frames+ed->cur_frame);
	goto use_last_tool;
      case TOOL_UNDO:
        TextureEditorUndo(ed);
        break;
        break;
      case TOOL_SET_BOUNDS:
        if(!ed->ms_left_down&&ed->setting_bounds) {
	  TextureEditorAddUndo(ed);
	  x=MinI64(ed->bound_start_x,ed->ms_x);
	  y=MinI64(ed->bound_start_y,ed->ms_y);
	  x2=MaxI64(ed->bound_start_x,ed->ms_x);
	  y2=MaxI64(ed->bound_start_y,ed->ms_y);
	  GrBlot(ed->frames+ed->cur_frame,0,0,ed->screen);
	  tmp=AnimDCResize(ed->frames,x2-x,y2-y,-(x-vis_x),-(y-vis_y),ed->screen->mem_task);
	  AnimDCDel(ed->frames);
	  ed->frames=tmp;
	  ed->setting_bounds=FALSE;
	  tmp=DCNew(x2-x,y2-y,ed->screen->mem_task);
	  DCFill(tmp,TRANSPARENT);
	  DCDel(ed->screen);
	  ed->screen=tmp;
	  GrBlot(ed->screen,0,0,ed->frames+ed->cur_frame);
        }
        break;
    }
next:
    Refresh;
  }
  Fs->draw_it=NULL;
  MenuPop;
  gr.fp_draw_ms=old_draw_ms;
  SettingsPop;
  if(!abort)
    *_image=ed->frames;
  else
    AnimDCDel(ed->frames);
  for(undo_layer=ed->undo.next;undo_layer!=&ed->undo;undo_layer=undo_layer->next) {
    AnimDCDel(undo_layer->anim_dc);
  }
  QueDel(&ed->undo);
  DCDel(ed->screen);
}$WW,1$
U8 *TextureEdit(U8 *blob_file,U8 *dft=NULL,I64 dft_w=150,I64 dft_h=275) {
  U8 *lump_name,*data;
  U8 write_to[STR_LEN];
  U64 type;
  I64 len;
  CDC *dc;
  if(dft) {
    lump_name=StrNew(dft);
  } else
    lump_name=BlobFileSelect(blob_file);
  data=BlobFileGetLump(blob_file,lump_name,,&type);
  if(!data) {
new:
    dc=DCNew(dft_w,dft_h);
    DCFill(dc,TRANSPARENT);
  } else if(type=='GR') {
    dc=AnimDCLoad(data);
  } else if(type!='GR') {
    if(PopUpNoYes("This is not a GR lump,overwrite?"))
      goto new;
    goto fin;
  }
  StrCpy(write_to,lump_name);
  _TextureEdit(&dc,blob_file,write_to);
  Free(data);
  data=AnimDCSave(dc,&len);
  BlobFileAddLump(blob_file,write_to,data,len,'GR');
  AnimDCDel(dc);
fin:
  Free(data);
  Free(lump_name);
  return lump_name;
}
#if __CMD_LINE__
TextureEdit("ASS");
#endif