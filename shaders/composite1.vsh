// ReMorganShaded v1.0 - Composite1 Vertex Shader (Pass 2)
// Segundo passe de pós-processamento
// Reflexões SSR + Bloom downscale

#version 120

#define COMPOSITE1_VERTEX

#include "common.glsl"

varying vec2 texCoord;
varying vec2 halfResTexCoord;
varying vec2 quarterResTexCoord;

void main() {
    // Full-screen quad
    gl_Position = ftransform();
    
    // Full resolution UV
    texCoord = gl_MultiTexCoord0.xy;
    
    // Half resolution UV
    halfResTexCoord = gl_MultiTexCoord0.xy * 0.5;
    
    // Quarter resolution UV (para bloom)
    quarterResTexCoord = gl_MultiTexCoord0.xy * 0.25;
}
