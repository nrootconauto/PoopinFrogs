#ifndef SONIC_HEDGEHOG_HH
#define SONIC_HEDGEHOG_HH
class CFastLookupKey {
  U64 hash;
  I64 len;
  U64 _str64[0];
};
class CFastLookup {
  U8 *value;
  U8 *class_str;
  CFastLookup*next;
  CFastLookupKey key;
};
#define FAST_LOOKUP_SZ 0x4000
CFastLookup *fast_lookup_table[FAST_LOOKUP_SZ];
MemSetU64(fast_lookup_table,NULL,FAST_LOOKUP_SZ);
CTask *fast_lookup_mem_task=Fs;
CFastLookup *FastLookupGetLU(CFastLookupKey *k,U8 *str2) {
  CFastLookup *h=fast_lookup_table[k->hash&(FAST_LOOKUP_SZ-1)];
  I64 idx;
  while(h) {
    if(h->key.hash==k->hash&&h->key.len==k->len) {
      idx=k->len;
      while(--idx>=0) {
	if(h->key._str64[idx]!=k->_str64[idx]) {
	  goto next;
	}
      }
      if(StrCmp(str2,h->class_str))
	goto next;
      return h;
    }
next:
    h=h->next;
  }
  return NULL;
}
CFastLookupKey *FastLookupGet(CFastLookupKey *k,U8 *class_str) {
  CFastLookup *lu=FastLookupGetLU(k,class_str);
  if(lu) return lu->value;
  return NULL;
}
CFastLookupKey *FastLookupKeyNew(U8 *str) {
  I64 len=(StrLen(str)+7+1)&~7;
  CFastLookupKey *k=CAlloc(len+sizeof(CFastLookupKey),fast_lookup_mem_task);
  k->hash=HashStr(str);
  k->len=len/8;
  StrCpy(k->_str64,str);
  return k;
}
U0 ExeKey2StringLiteral(U8 *str) {
  CFastLookupKey *k=FastLookupKeyNew(str);
  I64 blen=sizeof(CFastLookupKey)+8*k->len,idx;
  U8 *ret=CAlloc(4*blen+2);
  CatPrint(ret,"\"");
  for(idx=0;idx!=blen;idx++) {
    CatPrint(ret,"\\x%02x",k(U8*)[idx]);
  }
  CatPrint(ret,"\"");
  Free(k);
  StreamPrint("%s",ret);
  Free(ret);
}
CFastLookup *FastLookupAddValue(U8 *str,U8 *value1,U8 *class_str) {
  CFastLookupKey *k=FastLookupKeyNew(str);
  CFastLookup *fu=CAlloc(sizeof(CFastLookup)+k->len*8),**body;
  MemCpy(&fu->key,k,sizeof(CFastLookupKey)+k->len*8);
  fu->value=value1;
  fu->class_str=StrNew(class_str);
  body=&fast_lookup_table[k->hash&(FAST_LOOKUP_SZ-1)];
  fu->next=*body;
  *body=fu;
  Free(k);
  return fu;
}
U8 *FastLookupByStr(U8 *str,U8 *class_str) {
  CFastLookupKey *k=FastLookupKeyNew(str);
  U8 *ret=FastLookupGet(k,class_str);
  Free(k);
  return ret;
}
#endif