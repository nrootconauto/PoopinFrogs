F64 Sigmoid(F64 f) {
  if(-20.<=f<=20.)
    return 1./(1.+Exp(-f));
  else if(f>=20.)
    return 1.;
  return -1.;
} 

F64 CumSum(I64 cnt,CFrogNum **a,CFrogNum **b) {
  F64 r=0;
  while(--cnt>=0) {
     r+=AsF64(*a++)*AsF64(*b++);
  }
  return r;
}
#ifdef __AIWNIOS__
#ifdef TARGET_X86
asm {
_CUM_SUM::
    PUSH RBP
    MOV RBP,RSP
    XORPD XMM0,XMM0
    MOV RCX,SF_ARG1[RBP];
    MOV RAX,SF_ARG2[RBP]
    MOV RDX,SF_ARG3[RBP]
@@loop:
    CVTSS2SD XMM1,U32 4[RAX]
    CVTSS2SD XMM2,U32 4[RDX]
    MULSD XMM1,XMM2
    ADDSDXMM0,XMM1
    ADD RAX,16
    ADD RDX,16
    DEC RCX
    JNE @@loop
    MOVQ RAX,XMM0
    POP RBP
    RET1 3*8
};
_extern _CUM_SUM F64 CumSum(I64 cnt,U8 **a,U8 **b);
#endif
#endif
CFrogArray *MutateNN(CFrogArray *nn,I64 **argv,I64 argc) {
  I64 l,w,i;
  CFrogArray *ret=FrogArrayNew,*r1,*r2;
  CI64Set *layers=nn->items,*weights,*inps;
  for(l=0;l!=layers->cnt;l++) {
    weights=layers->body[l];
    r2=FrogArrayNew;
    if(ThingHasClass(weights,"CFrogArray")) {
      weights=weights(CFrogArray*)->items;
      for(w=0;w!=weights->cnt;w++) {
        inps=weights->body[w];
        r1=FrogArrayNew;
        if(ThingHasClass(inps,"CFrogArray")) {
	  inps=inps(CFrogArray*)->items;
	  for(i=0;i!=inps->cnt;i++) {
	    if(Rand<.1) {
	      I64SetAdd(r1->items,FrogNumNew((Rand-.5)*2.));
	    } else
	      I64SetAdd(r1->items,inps->body[i]);
	  }
	}
       I64SetAdd(r2->items,r1);
      }
    }
   I64SetAdd(ret->items,r2);
  }
  return ret;
}
AddMethod("CFrogArray","mutateNN",&MutateNN);

CFrogArray *RunNN(CFrogArray *nn,I64 **argv,I64 argc) {
  CFrogArray *inputs=argv[0];
  if(!ThingHasClass(inputs,"CFrogArray")) {
PrintI("ass",1);
    return FROG_SMALL_NIL;
  }
  CFrogArray *results=FrogArrayCopy(inputs);
  CFrogArray *tmp=FrogArrayNew,*weights;
  CI64Set *layers=nn->items,*out;
  CFrogNum **raw;
  I64 layer,w;
  F64 c;
  for(layer=0;layer!=layers->cnt;layer++) {
//For a 1 for hidden layers
    if(layer) {
      out=results->items;
      if(out->cnt)
        out->body[out->cnt-1]=FrogNumNew(1.);
    }
    weights=layers->body[layer];
    if(!ThingHasClass(weights,"CFrogArray")) {
PrintI("dimebage",1);
      return FROG_SMALL_NIL;
    }
    for(w=0;w!=weights->items->cnt;w++) {
      raw=weights->items->body[w];
      if(!ThingHasClass(raw,"CFrogArray")) {
PrintI("dimebage",2);
        return FROG_SMALL_NIL;
      }
      raw=raw(CFrogArray*)->items->body;
      c=Sigmoid(CumSum(results->items->cnt,results->items->body,raw));
      I64SetAdd(tmp->items,FrogNumNew(c));
    }
    SwapI64(&results,&tmp);
    tmp->items->cnt=0;
  }
  return results;
//Force neregs,tihs gets messyt with GC
  try {} catch;
}

AddMethod("CFrogArray","runNN:",&RunNN);
