// ReMorganShaded v1.0 - Deferred Lighting Fragment Shader
// Calcula iluminação final com sombras suaves (Vogel Disk PCF)
// Aplica ambient occlusion, diffuse, specular

#version 120

#define DEFERRED_FRAGMENT

#include "lib/common.glsl"
#include "lib/noise.glsl"

varying vec4 colortex;
varying vec2 texCoord;
varying vec4 position;
varying vec3 normal;
varying vec3 viewDir;

// Samplers dos G-buffers
uniform sampler2D gbufferColor;
uniform sampler2D gbufferDepth;
uniform sampler2D gbufferNormal;
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;

// Decodificar depth da shadow map
float decodeDepth(vec4 rgbaDepth) {
    const vec4 bitShift = vec4(1.0, 1.0/256.0, 1.0/65536.0, 1.0/16777216.0);
    return dot(rgbaDepth, bitShift);
}

// Vogel Disk PCF Shadow - 6 samples para suavidade barata
float softShadow(vec3 lightSpacePos) {
    vec2 shadowUV = lightSpacePos.xy * 0.5 + 0.5;
    float currentDepth = lightSpacePos.z;
    
    float visibility = 0.0;
    const float goldenAngle = 2.39996322973;
    
    // 6 samples em padrão Vogel disk
    for (int i = 0; i < 6; i++) {
        float theta = float(i) * goldenAngle;
        float r = sqrt(float(i) + 0.5) / sqrt(6.0);
        
        vec2 offset = vec2(cos(theta), sin(theta)) * r * 0.003;
        
        float sampleDepth = decodeDepth(texture2D(shadowtex0, shadowUV + offset));
        
        // PCF comparison
        visibility += step(currentDepth, sampleDepth + 0.001);
    }
    
    return visibility / 6.0;
}

// Shadow distance fade
float shadowFade(float distance) {
    float fadeStart = SHADOW_DISTANCE * 0.5;
    float fadeEnd = SHADOW_DISTANCE;
    
    return 1.0 - smoothstep(fadeStart, fadeEnd, distance);
}

void main() {
    // Cor base do G-buffer
    vec3 albedo = colortex.rgb;
    
    // Normal do G-buffer
    vec3 worldNormal = texture2D(gbufferNormal, texCoord).rgb * 2.0 - 1.0;
    worldNormal = normalize(worldNormal);
    
    // Depth
    float depth = texture2D(gbufferDepth, texCoord).r;
    
    // Posição em light space para shadows
    vec4 lightSpacePos = shadowProjection * shadowModelView * position;
    lightSpacePos.xyz /= lightSpacePos.w;
    
    // Calcular sombras
    float shadow = 1.0;
    
    // Só calcular sombra se estiver dentro do frustum da luz
    if (lightSpacePos.x > -1.0 && lightSpacePos.x < 1.0 &&
        lightSpacePos.y > -1.0 && lightSpacePos.y < 1.0 &&
        lightSpacePos.z > -1.0 && lightSpacePos.z < 1.0) {
        
        // Soft shadow com Vogel disk
        shadow = softShadow(lightSpacePos.xyz);
        
        // Distance fade
        float distFromLight = length((shadowModelView * position).xyz);
        float fade = shadowFade(distFromLight);
        
        shadow = mix(1.0, shadow, fade);
    }
    
    // Iluminação direcional (sol/lua)
    vec3 lightDir = normalize(sunPosition);
    float NdotL = max(dot(worldNormal, lightDir), 0.0);
    
    // Ambient lighting
    float ambient = 0.4;
    
    // Diffuse lighting com shadow
    vec3 diffuse = albedo * NdotL * shadow;
    
    // Specular simples (Blinn-Phong barato)
    vec3 halfVec = normalize(lightDir + viewDir);
    float NdotH = max(dot(worldNormal, halfVec), 0.0);
    float specular = pow(NdotH, 32.0) * shadow * 0.3;
    
    // Combinar iluminação
    vec3 lighting = vec3(ambient) + diffuse + vec3(specular);
    
    // Aplicar à cor
    vec3 finalColor = albedo * lighting;
    
    // Adicionar luz de sky (ambient colorido)
    finalColor += albedo * skyColor * ambient;
    
    gl_FragData[0] = vec4(finalColor, colortex.a);
}
