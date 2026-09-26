#pragma once
#include <cmath>

// Digital eight-way movement keeps the original game's diagonal speed rules.
// Coordinates are relative to the stick center, in UIKit points (down is +Y).
enum TH09JoystickDirection : unsigned {
    TH09JoystickLeft=1, TH09JoystickUp=2, TH09JoystickDown=4, TH09JoystickRight=8
};
inline unsigned TH09JoystickDirections(float x,float y,float deadZone){
    if(x*x+y*y<=deadZone*deadZone)return 0;
    constexpr float diagonalThreshold=.41421356237f; // tan(22.5 degrees)
    const float ax=std::fabs(x),ay=std::fabs(y);unsigned directions=0;
    if(ax>=ay*diagonalThreshold)directions|=x<0?TH09JoystickLeft:TH09JoystickRight;
    if(ay>=ax*diagonalThreshold)directions|=y<0?TH09JoystickUp:TH09JoystickDown;
    return directions;
}
