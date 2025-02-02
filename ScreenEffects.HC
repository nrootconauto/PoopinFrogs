//Piss/Blood streams on the screen
// Spits sometimes like rain
//$SP,"<1>",BI=1$;













class CScreenLiquid:CQue {
  F64 start_tS;
  F64 end_tS;
  F64 split_prob;
  F64 x,y;
  F64 x2,y2;
  F64 dx,dy;
  I64 color,drop_color,thick;
  I64 no_split;
};

class CScreenSplater:CQue {
  CFrogImg *img;
  F64 start_tS;
  F64 end_tS;
  F64 x,y;
  F64 dx,dy;
};
U0 UpdateScreenSplats(CDC *dc,CScreenSplater *head) {
  CScreenSplater *cur,*new,*next;
  F64 t=Frog_tS;
  for(cur=head->next;cur!=head;cur=next) {
    next=cur->next;
    cur->x+=cur->dx;
    cur->y+=cur->dy;
    if(ThingHasClass(cur->img,"CFrogImg")) {
      AnimDCBlot(dc,cur->x,cur->y,cur->img->dc);
    }
    if(t>cur->end_tS) {
      QueRem(cur);
      Free(cur);
    }
  }
}
U0 UpdateScreenLiquids(CDC *dc,CScreenLiquid *head) {
  CScreenLiquid *cur,*new,*next;
  F64 t=Frog_tS,grav=1.+3*Rand,xgrav=1.*(Rand-Rand);
  dc->thick=4;
  for(cur=head->next;cur!=head;cur=next) {
    next=cur->next;
    cur->x2+=cur->dx;
    cur->y2+=cur->dy;
    dc->color=cur->color;
    GrLine3(dc,cur->x,cur->y,0,cur->x2,cur->y2,0);
    dc->color=cur->drop_color;
    GrPlot3(dc,cur->x2,cur->y2,0);
    if(Rand<cur->split_prob) {
      if(cur->no_split)
	goto stop;
      new=CAlloc(sizeof(CScreenLiquid),frog_mem_task);
      new->x=cur->x2;
      new->y=cur->y2;
      new->x2=cur->x2;
      new->y2=cur->y2;
//Opposite direction
      if(cur->dx>0)
        new->dx=-3-Rand*3;
      else
        new->dx=3+Rand*3;
      new->dy=cur->dy;
      new->split_prob=cur->split_prob;
      if(Rand<.5)
        new->no_split=TRUE;
      new->start_tS=t;
      new->end_tS=cur->end_tS;
      new->color=cur->color;
      new->drop_color=cur->drop_color;
      new->thick=cur->thick;
      QueIns(new,head);
    } else if(Rand<cur->split_prob) {
stop:;
      cur->dx=0;
      cur->dy=0;
      cur->split_prob=0;
    }
    cur->y+=grav;
    cur->y2+=grav;
    cur->x+=xgrav;
    cur->x2+=xgrav;
    if(t>cur->end_tS) {
      QueRem(cur);
      Free(cur);
    }
  }
}
CScreenLiquid *NewScreenDrop(CScreenLiquid *head,I64 color) {
  CScreenLiquid *new=CAlloc(sizeof(CScreenLiquid),frog_mem_task);
  new->x=Rand*GR_WIDTH*.8+GR_WIDTH*.1;
  new->y=Rand*GR_HEIGHT*.6;
  new->x2=new->x;
  new->y2=new->y;
  new->dx=0;
  new->dy=0;
  new->color=color;
  new->drop_color=color;
  new->start_tS=Frog_tS;
  new->end_tS=Frog_tS+1.5;
  QueIns(new,head);
  return new;
}
CScreenLiquid *NewScreenLiquid(CScreenLiquid *head,I64 color,I64 drop_color=-1) {
  CScreenLiquid *new=CAlloc(sizeof(CScreenLiquid),frog_mem_task);
  new->x=Rand*GR_WIDTH*.8+GR_WIDTH*.1;
  new->y=Rand*GR_HEIGHT*.6;
  new->color=color;
  new->split_prob=(.25+Rand*.75)/7.;
  if(drop_color<0) 
    new->drop_color=color;
  else
    new->drop_color=drop_color;
  new->start_tS=Frog_tS;
  new->end_tS=Frog_tS+1.5;
  new->x2=new->x;
  new->y2=new->y;
  new->dy=3+Rand*3;
  if(Rand<.5)
    new->dx=-3-Rand*3;
  else
    new->dx=3+Rand*3;
  QueIns(new,head);
  return new;
}
CScreenSplater *NewScreenSplat(CScreenSplater *head,CFrogImg *img) {
  CScreenSplater *new=CAlloc(sizeof(CScreenSplater),frog_mem_task);
  new->x=Rand*GR_WIDTH*.8+GR_WIDTH*.1;
  new->y=Rand*GR_HEIGHT*.6;
  new->dy=3+Rand*3;
  new->start_tS=Frog_tS;
  new->end_tS=Frog_tS+1.5;
  new->img=img;
  QueIns(new,head);
  return new;
}        W            4      I   2   w   Z      X   ?   I   a   \   n      ?   #   .   A    