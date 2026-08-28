// ReMorganShaded v1.0 - G-Buffer Sky Textured Vertex Shader
// Renderiza sol e lua (texturas do Minecraft)
// Otimizado: mínimo processamento

#version 120

#define GBUFFERS_SKYTEXTURED_VERTEX

#include "common.glsl"

varying vec2 texCoord;
varying vec4 color;
varying vec3 viewDir;

void main() {
    // Posição em world space
    vec4 worldPos = gl_ModelViewMatrix * gl_Vertex;
    
    // Transformar para clip space
    gl_Position = gl_ProjectionMatrix * worldPos;
    
    // Texture coordinates
    texCoord = (gl_MultiTexCoord0).xy;
    
    // Vertex color
    color = gl_Color;
    
    // Direção de vista
    viewDir = normalize(worldPos.xyz);
}
