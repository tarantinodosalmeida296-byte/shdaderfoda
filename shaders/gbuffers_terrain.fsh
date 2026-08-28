// ReMorganShaded v1.0 - G-Buffer Terrain Fragment Shader
// Renderiza blocos sólidos com PBR simplificado
// Otimizado: usa mediump, evita branches caros

#version 120

#define GBUFFERS_TERRAIN_FRAGMENT

#include "lib/common.glsl"
#include "lib/noise.glsl"

varying vec2 texCoord;
varying vec2 midTexCoord;
varying vec3 normal;
varying vec3 viewDir;
varying vec4 position;
varying vec4 color;
varying float distanceFromCamera;

uniform sampler2D texture;
uniform int blockEntityId;

// PBR simplificado constants
const float METALLIC_DEFAULT = 0.0;
const float ROUGHNESS_DEFAULT = 0.8;

void main() {
    // Texture sampling
    vec4 texColor = texture2D(texture, texCoord);
    
    // Aplicar vertex color
    vec3 albedo = texColor.rgb * color.rgb;
    float alpha = texColor.a * color.a;
    
    // Normal mapping simples (se disponível no resource pack)
    vec3 norm = normalize(normal);
    
    // Detectar blocos emissivos (tocha, lava, etc) baseado em brightness
    float emissive = 0.0;
    
    // Lava e blocos brilhantes
    if (blockEntityId == 10 || blockEntityId == 11) {
        emissive = 1.0;
    }
    
    // Subsurface scattering FAKE para folhas/plantas
    float sss = 0.0;
    if (mc_Entity.x > 0.5) {
        // SSS fake baseado em dot(light, view)
        float lightDotView = dot(normalize(sunPosition), normalize(-viewDir));
        sss = max(0.0, lightDotView) * 0.3;
    }
    
    // Calcular roughness baseada no tipo de bloco
    float roughness = ROUGHNESS_DEFAULT;
    float metallic = METALLIC_DEFAULT;
    
    // Blocos metálicos (minérios, etc)
    if (blockEntityId >= 20 && blockEntityId <= 30) {
        metallic = 0.3;
        roughness = 0.4;
    }
    
    // GGX Specular aproximado
    vec3 lightDir = normalize(sunPosition);
    vec3 halfVec = normalize(lightDir + viewDir);
    
    float NdotL = max(dot(norm, lightDir), 0.0);
    float NdotH = max(dot(norm, halfVec), 0.0);
    float NdotV = max(dot(norm, viewDir), 0.0);
    
    // Specular GGX simplificado
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    
    float denom = NdotH * NdotH * (alpha2 - 1.0) + 1.0;
    float ndf = alpha2 / (3.14159 * denom * denom);
    
    // Fresnel Schlick
    vec3 F0 = mix(vec3(0.02), albedo, metallic);
    vec3 F = F0 + (1.0 - F0) * pow(1.0 - NdotV, 5.0);
    
    // Geometria simplificada
    float geometry = 1.0 / ((NdotV + 0.001) * 2.0);
    
    // Specular final
    vec3 specular = ndf * geometry * F;
    specular = specular / (4.0 * NdotL + 0.001);
    
    // Diffuse (Lambert)
    vec3 diffuse = albedo / 3.14159;
    
    // Combinar diffuse + specular
    vec3 lighting = (diffuse + specular) * NdotL;
    
    // Adicionar emissivo
    lighting += albedo * emissive;
    
    // Adicionar SSS
    lighting += albedo * sss;
    
    // Ambient term
    float ambient = 0.3;
    lighting += albedo * ambient;
    
    gl_FragData[0] = vec4(lighting, alpha);
    gl_FragData[1] = vec4(norm * 0.5 + 0.5, 1.0); // Normal buffer
    gl_FragData[2] = vec4(albedo, 1.0); // Albedo buffer
}
