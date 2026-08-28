// ReMorganShaded v1.0 - G-Buffer Water Vertex Shader
// Renderiza água com waving no vertex shader
// Otimizado: pré-calcular ondas no vertex

#version 120

#define GBUFFERS_WATER_VERTEX

#include "lib/common.glsl"
#include "lib/water.glsl"

varying vec2 texCoord;
varying vec3 normal;
varying vec3 viewDir;
varying vec4 position;
varying vec4 color;
varying float distanceFromCamera;
varying float waveHeight;

uniform sampler2D texture;

void main() {
    // Posição em world space
    vec4 worldPos = gl_ModelViewMatrix * gl_Vertex;
    
    // Aplicar ondas da água no vertex (custo zero no fragment!)
    float time = frameTimeCounter;
    float wave = vertexWave(worldPos.xyz, time);
    
    // Modificar posição Y baseado na onda
    worldPos.y += wave;
    waveHeight = wave;
    
    // Transformar para clip space
    gl_Position = gl_ProjectionMatrix * worldPos;
    
    // Posição em view space
    position = worldPos;
    
    // Normal modificada pelas ondas
    // Calcular normal baseada no gradiente das ondas
    vec3 tangent = vec3(1.0, 0.0, 0.0);
    vec3 bitangent = vec3(0.0, 1.0, 0.0);
    
    // Aproximação da normal das ondas
    float dx = vertexWave(worldPos.xyz + vec3(0.1, 0.0, 0.0), time);
    float dz = vertexWave(worldPos.xyz + vec3(0.0, 0.0, 0.1), time);
    
    vec3 waveNormal = normalize(vec3(wave - dx, 0.15, wave - dz));
    normal = waveNormal;
    
    // Direction to camera
    viewDir = normalize(-worldPos.xyz);
    
    // Texture coordinates
    texCoord = (gl_MultiTexCoord0).xy;
    
    // Vertex color
    color = gl_Color;
    
    // Distance da câmera
    distanceFromCamera = length(worldPos.xyz);
}
