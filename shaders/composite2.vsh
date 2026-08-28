// ReMorganShaded v1.0 - Composite2 Vertex Shader (Pass 3)
// Terceiro passe de pós-processamento
// Bloom upscale + Tone Mapping + Color Grade + TAA

#version 120

#define COMPOSITE2_VERTEX

#include "common.glsl"

varying vec2 texCoord;
varying vec2 halfResTexCoord;

void main() {
    // Full-screen quad
    gl_Position = ftransform();
    
    // Full resolution UV
    texCoord = gl_MultiTexCoord0.xy;
    
    // Half resolution UV (para bloom upscale)
    halfResTexCoord = gl_MultiTexCoord0.xy * 0.5;
}
