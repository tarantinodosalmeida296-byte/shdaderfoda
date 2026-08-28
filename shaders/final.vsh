// ReMorganShaded v1.0 - Final Vertex Shader
// Passe final de output
// Vinheta + Film Grain + Dithering

#version 120

#define FINAL_VERTEX

#include "lib/common.glsl"

varying vec2 texCoord;

void main() {
    // Full-screen quad
    gl_Position = ftransform();
    
    // Texture coordinates
    texCoord = gl_MultiTexCoord0.xy;
}
