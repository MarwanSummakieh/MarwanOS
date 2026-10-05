#include "source/trunc/FdmControllerInput.h"
#include <iostream>
#include <stdexcept>
using namespace fdm_controller;
static void check(bool ok,const char*name){if(!ok)throw std::runtime_error(name);std::cout<<"PASS "<<name<<"\n";}
int main(){try{
 Input i; Sample s; i.Update(s,true,true,0); s.buttons=A;
 check(i.Update(s,true,true,1)==std::vector<Action>{Accept},"accept edge");
 check(i.Update(s,true,true,2).empty(),"held accept is not repeated");
 i.Update(s,true,false,3);check(i.Update(s,true,true,4).empty(),"focus regain suppresses held accept");
 s.buttons=0;i.Update(s,true,true,5);s.buttons=A;check(i.Update(s,true,true,6)==std::vector<Action>{Accept},"neutral re-arms input");
 i.Update(s,false,true,7);check(i.Update(s,true,true,8).empty(),"reconnect suppresses held buttons");
 s={};i.Update(s,true,true,9);s.x=5000;check(i.Update(s,true,true,10).empty(),"stick dead zone");
 s.x=20000;check(i.Update(s,true,true,20)==std::vector<Action>{Right},"stick navigation");
 check(i.Update(s,true,true,200).empty(),"repeat delay");
 check(i.Update(s,true,true,380)==std::vector<Action>{Right},"navigation repeat");
 s={};i.Update(s,true,true,400);s.buttons=A|B;check(i.Update(s,true,true,401)==std::vector<Action>{Back},"back wins over accept");
 s={};i.Update(s,true,true,402);s.buttons=X;check(i.Update(s,true,true,403)==std::vector<Action>{Torrent},"torrent shortcut");
 s={};i.Update(s,true,true,404);s.buttons=Y;check(i.Update(s,true,true,405)==std::vector<Action>{Link},"link shortcut");
 s={};i.Update(s,true,true,406);s.buttons=RB;check(i.Update(s,true,true,407)==std::vector<Action>{NextFilter},"filter shortcut");
 s={};i.Update(s,true,true,408);s.x=32767;s.y=32767;check(Input::Direction(s)==Up,"maximum stick values do not overflow");
 return 0;
}catch(const std::exception&e){std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}}
