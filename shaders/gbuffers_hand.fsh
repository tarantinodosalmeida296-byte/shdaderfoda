// ReMorganShaded v1.0 - G-Buffer Hand Fragment Shader
// Renderiza mão e items com iluminação simples
// Otimizado: sem efeitos caros, apenas diffuse básico

#version 120

#define GBUFFERS_HAND_FRAGMENT

#include "lib/common.glsl"

varying vec2 texCoord;
varying vec3 normal;
varying vec3 viewDir;
varying vec4 position;
varying vec4 color;

uniform sampler2D texture;

void main() {
    // Texture sampling
    vec4 texColor = texture2D(texture, texCoord);
    
    // Aplicar vertex color
    vec3 albedo = texColor.rgb * color.rgb;
    float alpha = texColor.a * color.a;
    
    // Normal
    vec3 norm = normalize(normal);
    
    // Iluminação simples para a mão
    vec3 lightDir = normalize(sunPosition);
    float NdotL = max(dot(norm, lightDir), 0.0);
    
    // Ambient mais alto para a mão (sempre visível)
    float ambient = 0.6;
    
    // Diffuse
    vec3 diffuse = albedo * NdotL;
    
    // Combinar
    vec3 lighting = diffuse + albedo * ambient;
    
    gl_FragData[0] = vec4(lighting, alpha);
}
