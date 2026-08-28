// ReMorganShaded v1.0 - Deferred Lighting Vertex Shader
// Passa de lighting que calcula iluminação com sombras
// Processa geometry G-buffer e aplica shadows

#version 120

#define DEFERRED_VERTEX

#include "common.glsl"

// Varyings para o fragment shader
varying vec4 colortex;
varying vec2 texCoord;
varying vec4 position;
varying vec3 normal;
varying vec3 viewDir;

void main() {
    // Posição em clip space
    gl_Position = ftransform();
    
    // Posição em view space
    position = gl_ModelViewMatrix * gl_Vertex;
    
    // Normal em view space
    normal = gl_NormalMatrix * gl_Normal;
    
    // Direction to camera
    viewDir = normalize(-position.xyz);
    
    // Texture coordinates
    texCoord = (gl_MultiTexCoord0).xy;
    
    // Color
    colortex = gl_Color;
}
