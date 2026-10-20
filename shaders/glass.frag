#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uStrength;
uniform sampler2D uBackdrop;
out vec4 fragColor;
void main(){
  vec2 uv=FlutterFragCoord().xy/uSize;
  #ifdef IMPELLER_TARGET_OPENGLES
  uv.y=1.0-uv.y;
  #endif
  vec2 p=uv*2.0-1.0;
  float edge=pow(max(abs(p.x),abs(p.y)),6.0);
  vec2 shift=p*edge*uStrength*0.018;
  vec4 c=texture(uBackdrop,clamp(uv-shift,0.001,0.999));
  float shine=pow(max(0.0,1.0-length(uv-vec2(.16,.03))),8.0)*.12;
  fragColor=vec4(c.rgb+shine,c.a);
}
