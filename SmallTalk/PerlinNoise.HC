F64 Lerp(F64 r,F64 lo,F64 hi) {
  return r*(hi-lo)+lo;
}
F64 SmoothStep(F64 x) {
  return 3*x*x-2*x*x*x;
}
F64 Closest(F64 r,F64 a,F64 b) {
  return Lerp(r,a,b);
}
F64 PerlinCell(CFrogArray *arr,F64 x,F64 y) {
  static I64 arr_at=UniverseAddClass("at:");
  F64 rx=x%1.;
  F64 ry=y%1.;
  CFrogArray *row1=CallScriptUniverse(arr_at,arr,FrogNumNew(y));
  CFrogArray *row2=CallScriptUniverse(arr_at,arr,FrogNumNew(y+1));
  F64 a,b,c,d;
  a=AsF64(CallScriptUniverse(arr_at,row1,FrogNumNew(x)));
  b=AsF64(CallScriptUniverse(arr_at,row1,FrogNumNew(x+1)));
  c=AsF64(CallScriptUniverse(arr_at,row2,FrogNumNew(x)));
  d=AsF64(CallScriptUniverse(arr_at,row2,FrogNumNew(x+1)));
  
  F64 g1=rx*Cos(a)+ry*Sin(a);
  F64 g2=(1-rx)*Cos(b)+ry*Sin(b);
  F64 g3=rx*Cos(c)+(1-ry)*Sin(c);
  F64 g4=(1-rx)*Cos(d)+(1-ry)*Sin(d);
  return Lerp(ry,Lerp(rx,g1,g2),Lerp(rx,g3,g4));
}

CFrogNum *FrogArrayPerlin(CFrogArray *arr,I64 *argv,I64 argc) {
  return FrogNumNew(PerlinCell(arr,AsF64(argv[0]),AsF64(argv[1])));
}
AddMethod("CFrogArray","perlinNoiseAtX:atY:",&FrogArrayPerlin);