// ReMorganShaded v1.0 - G-Buffer Terrain Vertex Shader
// Renderiza blocos sólidos no G-buffer
// Otimizado: pré-calcular normais e posição no vertex

#version 120

#define GBUFFERS_TERRAIN_VERTEX

#include "lib/common.glsl"

// Atributos do Minecraft
attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

// Varyings para fragment shader
varying vec2 texCoord;
varying vec2 midTexCoord;
varying vec3 normal;
varying vec3 viewDir;
varying vec4 position;
varying vec4 color;
varying float distanceFromCamera;

// Waving de plantas/leaves no vertex shader (custo zero no fragment!)
#ifdef WAVING_PLANTS
uniform float frameTimeCounter;

float wavePlants(vec3 worldPos, float windSpeed) {
    float wave = sin(worldPos.x * 0.5 + frameTimeCounter * windSpeed) * 0.05;
    wave += cos(worldPos.z * 0.3 + frameTimeCounter * windSpeed * 0.8) * 0.05;
    return wave;
}
#endif

void main() {
    // Posição em world space
    vec4 worldPos = gl_ModelViewMatrix * gl_Vertex;
    
    #ifdef WAVING_PLANTS
    // Aplicar waving se for planta/leaf
    if (mc_Entity.x > 0.5) {
        float wave = wavePlants(worldPos.xyz, 2.0);
        worldPos.x += wave;
    }
    #endif
    
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
    midTexCoord = mc_midTexCoord.xy;
    
    // Vertex color
    color = gl_Color;
    
    // Distance da câmera para fog
    distanceFromCamera = length(worldPos.xyz);
}
