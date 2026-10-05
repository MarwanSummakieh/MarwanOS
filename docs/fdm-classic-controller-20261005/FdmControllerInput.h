#pragma once
#include <vector>
#include <cstdint>
#include <cstdlib>

namespace fdm_controller {
enum Action { Up, Down, Left, Right, Accept, Back, Torrent, Link, PreviousFilter, NextFilter, Desktop };
enum Button { A=1, B=2, X=4, Y=8, LB=16, RB=32, Menu=64, DUp=128, DDown=256, DLeft=512, DRight=1024 };
struct Sample { unsigned buttons=0; int x=0,y=0; };
class Input {
    bool gated=true;
    unsigned previous=0;
    int previousDirection=-1;
    uint32_t repeatAt=0;
public:
    static int Direction(const Sample&s) {
        if(s.buttons&DUp)return Up; if(s.buttons&DDown)return Down;
        if(s.buttons&DLeft)return Left; if(s.buttons&DRight)return Right;
        if(int64_t(s.x)*s.x+int64_t(s.y)*s.y<12000LL*12000)return -1;
        return std::abs(s.x)>std::abs(s.y)?(s.x>0?Right:Left):(s.y>0?Up:Down);
    }
    std::vector<Action> Update(const Sample&s,bool connected,bool focused,uint32_t now) {
        std::vector<Action> out; int direction=Direction(s);
        if(!connected||!focused){gated=true;previous=s.buttons;previousDirection=direction;return out;}
        if(gated){previous=s.buttons;previousDirection=direction;if(s.buttons==0&&direction<0)gated=false;return out;}
        unsigned pressed=s.buttons&~previous; previous=s.buttons;
        if(direction>=0&&(direction!=previousDirection||int32_t(now-repeatAt)>=0)) {
            out.push_back(Action(direction)); repeatAt=now+(direction!=previousDirection?360:140);
        }
        previousDirection=direction;
        // Back wins over Accept when controls are pressed together.
        if(pressed&B)out.push_back(Back);
        else if(pressed&A)out.push_back(Accept);
        else if(pressed&X)out.push_back(Torrent);
        else if(pressed&Y)out.push_back(Link);
        else if(pressed&LB)out.push_back(PreviousFilter);
        else if(pressed&RB)out.push_back(NextFilter);
        else if(pressed&Menu)out.push_back(Desktop);
        return out;
    }
};
}
