#exe {Cd(__DIR__);};;
#include"3D.HC";
CallScript("newLandscapeWithWidth:withHeight:",FrogSymbol("world")->value,FrogNumNew(100),FrogNumNew(100));
CallScript("hostGameAt:atPort:",FrogSymbol("world")->value,FrogStrNew("0.0.0.0"),FrogNumNew(10999));
while(TRUE) {
  CallScript("physics",FrogSymbol("world")->value);
  CallScript("animate",FrogSymbol("world")->value);
  CallScript("update",FrogSymbol("world")->value);
  Sleep(1000/30.);
}