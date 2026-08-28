// ReMorganShaded v1.0 - G-Buffer Entities Vertex Shader
// Renderiza entidades (mobs, jogadores, items)
// Otimizado: mínimo processamento extra

#version 120

#define GBUFFERS_ENTITIES_VERTEX

#include "lib/common.glsl"

varying vec2 texCoord;
varying vec3 normal;
varying vec3 viewDir;
varying vec4 position;
varying vec4 color;
varying float distanceFromCamera;

attribute vec4 mc_Entity;

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
    
    // Distance da câmera
    distanceFromCamera = length(worldPos.xyz);
}
