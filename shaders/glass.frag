#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uStrength;
uniform float uRadius;
uniform float uLensMode;
uniform vec2 uLensCenter;
uniform sampler2D uBackdrop;
out vec4 fragColor;
void main(){
  vec2 point=FlutterFragCoord().xy;
  vec2 uv=point/uSize;
  #ifdef IMPELLER_TARGET_OPENGLES
  uv.y=1.0-uv.y;
  #endif
  vec2 halfSize=uSize*.5;
  float radius=min(uRadius,min(halfSize.x,halfSize.y));
  vec2 p=point-halfSize;
  vec2 corner=abs(p)-(halfSize-vec2(radius));
  float distance=length(max(corner,0.0))+min(max(corner.x,corner.y),0.0)-radius;
  vec2 gradient=sign(p)*normalize(max(corner,vec2(.001)));
  if(corner.x<0.0&&corner.y<0.0){
    gradient=sign(p)*(corner.x>corner.y?vec2(1.0,0.0):vec2(0.0,1.0));
  }
  float edge=1.0-smoothstep(0.0,max(1.0,radius*.65),-distance);
  vec2 shift=gradient*edge*edge*uStrength*min(radius,14.0)/uSize;
  if(uLensMode>.5){
    vec2 delta=point-uLensCenter;
    float relative=clamp(length(delta)/max(uRadius,1.0),0.0,1.0);
    float bend=1.0-sqrt(max(0.0,1.0-relative*relative));
    shift=delta*min(bend,.85)*uStrength/uSize;
  }
  #ifdef IMPELLER_TARGET_OPENGLES
  shift.y=-shift.y;
  #endif
  vec4 c=texture(uBackdrop,clamp(uv-shift,0.001,0.999));
  float shine=edge*max(0.0,dot(gradient,normalize(vec2(-.6,-1.0))))*.06;
  fragColor=vec4(c.rgb+shine,c.a);
}
