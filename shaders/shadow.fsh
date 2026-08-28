// ReMorganShaded v1.0 - Shadow Fragment Shader
// Renderiza shadow map com codificação de depth otimizada
// Usa RGBA8 para melhor precisão de depth

#version 120

#define SHADOW_FRAGMENT

#include "lib/common.glsl"

varying float distanceFromLight;
varying vec2 texCoord;

uniform int shadowMapIndex;

// Codificar depth em RGBA para melhor precisão (24-bit effective)
vec4 encodeDepth(float depth) {
    const vec4 bitShift = vec4(1.0, 256.0, 65536.0, 16777216.0);
    const vec4 bitMask = vec4(1.0/256.0, 1.0/256.0, 1.0/256.0, 0.0);
    
    vec4 res = fract(depth * bitShift);
    res -= res.xxyz * bitMask;
    return res;
}

void main() {
    // Depth da perspectiva da luz
    float depth = gl_FragCoord.z;
    
    // Codificar depth em RGBA para precisão
    gl_FragData[0] = encodeDepth(depth);
    
    // Shadow map index para diferenciar blocos
    gl_FragData[1] = vec4(float(shadowMapIndex) / 255.0);
}
