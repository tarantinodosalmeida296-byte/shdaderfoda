// ReMorganShaded v1.0 - G-Buffer Sky Textured Fragment Shader
// Renderiza sol e lua com glow adicional
// Otimizado: glow barato via radial gradient

#version 120

#define GBUFFERS_SKYTEXTURED_FRAGMENT

#include "lib/common.glsl"
#include "lib/atmosphere.glsl"

varying vec2 texCoord;
varying vec4 color;
varying vec3 viewDir;

uniform sampler2D texture;
uniform int isSun; // 1 = sol, 0 = lua

void main() {
    // Texture sampling
    vec4 texColor = texture2D(texture, texCoord);
    
    // Aplicar vertex color
    vec3 celestialBody = texColor.rgb * color.rgb;
    
    // Determinar cor base (sol ou lua)
    vec3 baseColor = isSun == 1 ? SUN_COLOR : MOON_COLOR;
    celestialBody *= baseColor;
    
    // Glow adicional ao redor do sol/lua
    // Calcular distância do centro da textura
    vec2 centerUV = texCoord - 0.5;
    float distFromCenter = length(centerUV);
    
    // Glow interno brilhante
    float innerGlow = pow(1.0 - smoothstep(0.0, 0.5, distFromCenter), 8.0);
    
    // Glow externo suave
    float outerGlow = pow(1.0 - smoothstep(0.0, 0.8, distFromCenter), 4.0) * 0.3;
    
    // Combinar glow com textura
    vec3 finalColor = celestialBody + baseColor * (innerGlow + outerGlow);
    
    // Alpha da textura
    float alpha = texColor.a * color.a;
    
    gl_FragData[0] = vec4(finalColor, alpha);
}
