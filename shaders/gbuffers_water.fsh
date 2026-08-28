// ReMorganShaded v1.0 - G-Buffer Water Fragment Shader
// Renderiza água com efeitos otimizados
// Reflexão, refração, fresnel, espuma

#version 120

#define GBUFFERS_WATER_FRAGMENT

#include "common.glsl"
#include "water.glsl"

varying vec2 texCoord;
varying vec3 normal;
varying vec3 viewDir;
varying vec4 position;
varying vec4 color;
varying float distanceFromCamera;
varying float waveHeight;

uniform sampler2D texture;
uniform sampler2D gbufferDepth;
uniform sampler2D gbufferColor;
uniform int isEyeInWater;

void main() {
    // Tempo para animação
    float time = frameTimeCounter;
    
    // Gerar normais detalhadas da água
    vec3 waterNormal = generateWaterNormals(texCoord * 5.0, time);
    
    // Combinar com normal geométrica
    waterNormal = normalize(waterNormal + normal * 0.3);
    
    // Cor base da água
    vec3 waterColor = WATER_BASE_COLOR;
    
    // Fresnel para mistura reflexão/refração
    float cosTheta = max(dot(normalize(-viewDir), waterNormal), 0.0);
    float fresnel = waterFresnel(cosTheta);
    
    // Profundidade atual
    float depth = gl_FragCoord.z;
    
    // Specular do sol/lua
    vec3 lightDir = normalize(sunPosition);
    vec3 specular = waterSpecular(waterNormal, normalize(-viewDir), lightDir, vec3(1.0));
    
    // Cáusticas fake
    vec3 caustics = fakeCaustics(texCoord * 3.0, time, depth * 10.0);
    
    // Espuma baseada em altura da onda
    float foam = smoothstep(0.08, 0.15, abs(waveHeight));
    foam *= fbm2D(texCoord * 20.0 + time, 2) * 0.5 + 0.5;
    
    // Composição da cor da água
    vec3 result = waterColor;
    
    // Adicionar specularity
    result += specular * WATER_SPECULAR_INTENSITY;
    
    // Adicionar cáusticas
    result += caustics * 0.3;
    
    // Adicionar espuma
    result = mix(result, vec3(1.0), foam * 0.3);
    
    // Aplicar vertex color
    result *= color.rgb;
    
    // Fog submarino se estiver debaixo d'água
    if (isEyeInWater > 0) {
        float fogDensity = WATER_FOG_DENSITY;
        float fogFactor = 1.0 - exp(-distanceFromCamera * fogDensity);
        result = mix(result, waterColor * 1.5, fogFactor);
    }
    
    // Alpha para transparência
    float alpha = 0.8;
    
    gl_FragData[0] = vec4(result, alpha);
    gl_FragData[1] = vec4(waterNormal * 0.5 + 0.5, 1.0);
}
