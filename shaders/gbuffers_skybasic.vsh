// ReMorganShaded v1.0 - G-Buffer Sky Basic Vertex Shader
// Renderiza o céu básico (gradiente)
// Otimizado: vertex shader faz todo trabalho

#version 120

#define GBUFFERS_SKYBASIC_VERTEX

#include "lib/common.glsl"
#include "lib/atmosphere.glsl"

varying vec3 viewDir;
varying float sunFactor;

void main() {
    // Posição em world space
    vec4 worldPos = gl_ModelViewMatrix * gl_Vertex;
    
    // Transformar para clip space
    gl_Position = gl_ProjectionMatrix * worldPos;
    
    // Direção de vista (para calcular cor do céu no fragment)
    viewDir = normalize(worldPos.xyz);
    
    // Fator do sol para dia/noite
    float sunHeight = dot(normalize(sunPosition), vec3(0.0, 1.0, 0.0));
    sunFactor = clamp(sunHeight * 2.0 + 0.5, 0.0, 1.0);
}
