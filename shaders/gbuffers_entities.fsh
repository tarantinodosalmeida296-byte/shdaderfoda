// ReMorganShaded v1.0 - G-Buffer Entities Fragment Shader
// Renderiza entidades com iluminação básica
// Otimizado: sem efeitos caros

#version 120

#define GBUFFERS_ENTITIES_FRAGMENT

#include "lib/common.glsl"

varying vec2 texCoord;
varying vec3 normal;
varying vec3 viewDir;
varying vec4 position;
varying vec4 color;
varying float distanceFromCamera;

uniform sampler2D texture;
uniform int blockEntityId;

void main() {
    // Texture sampling
    vec4 texColor = texture2D(texture, texCoord);
    
    // Aplicar vertex color
    vec3 albedo = texColor.rgb * color.rgb;
    float alpha = texColor.a * color.a;
    
    // Normal
    vec3 norm = normalize(normal);
    
    // Iluminação simples para entidades
    vec3 lightDir = normalize(sunPosition);
    float NdotL = max(dot(norm, lightDir), 0.0);
    
    // Ambient
    float ambient = 0.5;
    
    // Diffuse
    vec3 diffuse = albedo * NdotL;
    
    // Combinar
    vec3 lighting = diffuse + albedo * ambient;
    
    // Detectar entidades emissivas (creeper em pânico, etc)
    float emissive = 0.0;
    
    // Adicionar emissivo
    lighting += albedo * emissive;
    
    gl_FragData[0] = vec4(lighting, alpha);
    gl_FragData[1] = vec4(norm * 0.5 + 0.5, 1.0);
}
