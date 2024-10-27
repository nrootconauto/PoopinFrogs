#exe {Cd(__DIR__);};;
#include "3D.HC";
CallScript("connectToGameAt:atPort:",FrogSymbol("world")->value,FrogStrNew("0.0.0.0"),FrogNumNew(10999));
C3DWorldShell *shell=ConstructThing("C3DWorldShell");
CallScript("init",shell);
UIShellRun(shell);
