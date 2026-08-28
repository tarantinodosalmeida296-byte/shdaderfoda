// ReMorganShaded v1.0 - Shadow Vertex Shader
// Renderiza depth da perspectiva da luz para shadow map
// Otimizado: cálculo mínimo, pré-cálculo no vertex

#version 120

#define SHADOW_VERTEX

#include "lib/common.glsl"

// Atributos do Minecraft
attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

// Varyings para fragment shader
varying float distanceFromLight;
varying vec2 texCoord;

uniform int shadowMapIndex;

void main() {
    // Posição do vértice em world space
    vec4 position = gl_ModelViewMatrix * gl_Vertex;
    
    // Transformar para light space (shadow map space)
    gl_Position = shadowProjection * shadowModelView * position;
    
    // Calcular distância da luz para fade das sombras
    distanceFromLight = length((shadowModelView * position).xyz);
    
    // UV coordinates
    texCoord = (gl_MultiTexCoord0).xy;
    
    // Bias para evitar shadow acne
    gl_Position.z -= 0.0001;
}
