// ReMorganShaded v1.0 - Composite Vertex Shader (Pass 1)
// Primeiro passe de pós-processamento
// SSAO + Fog atmosférico

#version 120

#define COMPOSITE_VERTEX

#include "common.glsl"

varying vec2 texCoord;
varying vec2 halfResTexCoord;

void main() {
    // Full-screen quad
    gl_Position = ftransform();
    
    // Full resolution UV
    texCoord = gl_MultiTexCoord0.xy;
    
    // Half resolution UV (para SSAO)
    halfResTexCoord = gl_MultiTexCoord0.xy * 0.5;
}
