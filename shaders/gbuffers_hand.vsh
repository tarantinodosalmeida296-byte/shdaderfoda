// ReMorganShaded v1.0 - G-Buffer Hand Vertex Shader
// Renderiza a mão do jogador e items segurados
// Otimizado: mínimo processamento

#version 120

#define GBUFFERS_HAND_VERTEX

#include "lib/common.glsl"

varying vec2 texCoord;
varying vec3 normal;
varying vec3 viewDir;
varying vec4 position;
varying vec4 color;

void main() {
    // Posição em world space
    vec4 worldPos = gl_ModelViewMatrix * gl_Vertex;
    
    // Transformar para clip space
    gl_Position = gl_ProjectionMatrix * worldPos;
    
    // Posição em view space
    position = worldPos;
    
    // Normal em view space
    normal = gl_NormalMatrix * gl_Normal;
    
    // Direction to camera
    viewDir = normalize(-worldPos.xyz);
    
    // Texture coordinates
    texCoord = (gl_MultiTexCoord0).xy;
    
    // Vertex color
    color = gl_Color;
}
