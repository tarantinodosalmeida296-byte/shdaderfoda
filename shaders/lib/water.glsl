// ReMorganShaded v1.0 - Water Library
// Funções de água otimizadas para performance
// Reflexões, refrações, normais e efeitos

#ifndef WATER_GLSL
#define WATER_GLSL

#include "common.glsl"
#include "noise.glsl"

// ============================================================================
// CONSTANTES DE ÁGUA
// ============================================================================

const vec3 WATER_BASE_COLOR = vec3(0.05, 0.15, 0.25);
const vec3 WATER_DEEP_COLOR = vec3(0.02, 0.08, 0.15);
const float WATER_FOG_DENSITY = 0.02;
const float WATER_SPECULAR_INTENSITY = 1.0;

// ============================================================================
// GERADOR DE NORMAIS DE ÁGUA
// Combina ondas senoidais com noise para aparência natural
// Tudo no fragment shader, mas otimizado
// ============================================================================

vec3 generateWaterNormals(vec2 uv, float time) {
    // Múltiplas escalas de ondas
    vec3 normal = vec3(0.0, 0.0, 1.0);
    
    // Onda 1 - Grande escala (lenta)
    float wave1 = sin(uv.x * 2.0 + time * 0.5) * cos(uv.y * 1.5 + time * 0.3);
    normal.xy += vec2(wave1 * 0.1);
    
    // Onda 2 - Média escala
    float wave2 = sin(uv.x * 4.0 - time * 0.4) * cos(uv.y * 3.0 + time * 0.6);
    normal.xy += vec2(wave2 * 0.05);
    
    // Onda 3 - Pequena escala (rápida)
    float wave3 = sin((uv.x + uv.y) * 8.0 + time * 0.8);
    normal.xy += vec2(wave3 * 0.025);
    
    // Adicionar noise para variação natural
    float n = fbm2D(uv * 3.0, 2);
    normal.xy += (n - 0.5) * 0.05;
    
    // Normalizar
    return normalize(normal);
}

// Versão mais barata (vertex shader friendly)
vec3 generateWaterNormalsLow(vec2 uv, float time) {
    float wave1 = sin(uv.x * 2.0 + time * 0.5);
    float wave2 = sin(uv.y * 3.0 - time * 0.4);
    
    vec3 normal = normalize(vec3(wave1 * 0.1, wave2 * 0.1, 1.0));
    return normal;
}

// ============================================================================
// FRESNEL SCHLICK PARA ÁGUA
// Determina reflexão vs refração baseado no ângulo
// ============================================================================

float waterFresnel(float cosTheta) {
    // Água tem IOR ~1.33
    const float F0 = 0.02; // Reflectância em incidência normal
    
    return fresnelSchlick(cosTheta, F0);
}

// ============================================================================
| REFLEXÃO SCREEN-SPACE SIMPLIFICADA (SSR)
// Ray march na tela para encontrar reflexões
// Limitado a 8 steps para performance
// ============================================================================

vec3 screenSpaceReflection(vec2 uv, vec3 viewDir, vec3 normal, sampler2D depthTex, sampler2D colorTex) {
    #if SSR_STEPS > 0
    // Calcular direção refletida
    vec3 reflectDir = reflect(viewDir, normal);
    
    // Só processar se refletindo para baixo (em direção à água)
    if (reflectDir.y > 0.0) {
        return vec3(0.0);
    }
    
    // Projetar direção na tela
    vec3 projReflect = (gbufferProjection * vec4(reflectDir, 0.0)).xyz;
    vec2 screenStep = normalize(projReflect.xy / abs(projReflect.z)) * 0.02;
    
    vec2 currentUV = uv;
    float currentDepth = texture2D(depthTex, uv).r;
    vec3 reflectedColor = vec3(0.0);
    float hitWeight = 0.0;
    
    // Ray march limitado
    for (int i = 0; i < SSR_STEPS; i++) {
        currentUV += screenStep;
        
        // Check bounds
        if (currentUV.x < 0.0 || currentUV.x > 1.0 || 
            currentUV.y < 0.0 || currentUV.y > 1.0) {
            break;
        }
        
        float sampleDepth = texture2D(depthTex, currentUV).r;
        
        // Check se o raio intersectou geometria
        float depthDiff = sampleDepth - currentDepth;
        
        if (depthDiff < 0.01 && depthDiff > -0.01) {
            // Hit! Pegar cor
            vec3 sampleColor = texture2D(colorTex, currentUV).rgb;
            reflectedColor += sampleColor;
            hitWeight += 1.0;
            
            // Early exit após primeiro hit
            break;
        }
        
        currentDepth += (screenStep.y * 0.1);
    }
    
    // Fade baseado na distância
    float distFade = 1.0 - (float(SSR_STEPS) / float(SSR_STEPS));
    
    return reflectedColor * hitWeight * distFade;
    #else
    return vec3(0.0);
    #endif
}

// ============================================================================
// REFRACÇÃO FAKE VIA DISTORÇÃO DE UV
// Baseada nas normais da água
// ============================================================================

vec2 refractUV(vec2 uv, vec3 normal, float strength) {
    // Distorcer UV baseado na componente XY da normal
    vec2 distortion = normal.xy * strength;
    return uv + distortion;
}

// ============================================================================
// CÁUSTICAS FAKE
// Textura procedural animada projetada no fundo
// ============================================================================

vec3 fakeCaustics(vec2 uv, float time, float depth) {
    // Padrão de cáusticas usando interference de ondas
    float caustic = 0.0;
    
    // Múltiplas camadas de padrões
    for (int i = 1; i <= 3; i++) {
        float freq = float(i) * 2.0;
        float speed = time * (0.5 + float(i) * 0.3);
        
        vec2 pos = uv * freq;
        float wave = sin(pos.x + speed) * cos(pos.y - speed);
        caustic += wave / float(i);
    }
    
    // Intensificar picos
    caustic = pow(max(caustic, 0.0), 2.0);
    
    // Atenuar com profundidade
    caustic *= exp(-depth * 0.5);
    
    // Cor das cáusticas (ciano/azul)
    vec3 causticColor = vec3(0.3, 0.7, 0.8) * caustic * 2.0;
    
    return causticColor;
}

// ============================================================================
// ESPUMA NAS BORDAS
// Baseada na diferença de depth
// ============================================================================

float foamAtEdge(float depth, float waterDepth, float threshold) {
    // Detectar transições bruscas de depth (bordas)
    float depthDiff = abs(depth - waterDepth);
    
    // Foam onde há transição
    float foam = smoothstep(0.0, threshold, depthDiff);
    
    // Adicionar noise para variação
    foam *= fbm2D(gl_FragCoord.xy * 0.05, 2);
    
    return foam;
}

// Espuma baseada em depth difference do terrain
float generateFoam(vec2 uv, float waterDepth, float terrainDepth) {
    // Onde terrain está perto da superfície da água
    float depthDiff = terrainDepth - waterDepth;
    
    // Foam quando terrain está logo abaixo da água
    float foam = smoothstep(0.0, 0.1, depthDiff);
    
    // Quebrar padrão com noise
    foam *= fbm2D(uv * 10.0 + frameTimeCounter * 2.0, 2) * 0.5 + 0.5;
    
    return clamp(foam, 0.0, 1.0);
}

// ============================================================================
// COR DA ÁGUA COM FOG SUBMARINO
// ============================================================================

vec3 waterColorWithFog(vec3 baseColor, float depth, float density) {
    // Beer-Lambert law simplificada
    vec3 attenuation = exp(-baseColor * depth * density * 10.0);
    return attenuation;
}

// ============================================================================
// ILUMINAÇÃO ESPECULAR DA ÁGUA (GGX simplificado)
// ============================================================================

vec3 waterSpecular(vec3 normal, vec3 viewDir, vec3 lightDir, vec3 lightColor) {
    // Half vector
    vec3 halfVec = normalize(lightDir + viewDir);
    
    // NDF GGX aproximado
    float NdotH = max(dot(normal, halfVec), 0.0);
    float roughness = 0.1; // Água é bem lisa
    
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    
    float denom = NdotH * NdotH * (alpha2 - 1.0) + 1.0;
    float ndf = alpha2 / (PI * denom * denom);
    
    // Geometria simplificada (Schlick-GGX)
    float VdotH = max(dot(viewDir, halfVec), 0.0);
    float geometry = 1.0 / (VdotH * VdotH * (alpha2 - 1.0) + 1.0);
    
    // Fresnel
    float F = fresnelSchlick(VdotH, 0.02);
    
    // Specular final
    vec3 specular = (ndf * geometry * F) / (4.0 * max(dot(normal, lightDir), 0.001) * max(dot(normal, viewDir), 0.001));
    
    return specular * lightColor * WATER_SPECULAR_INTENSITY;
}

// ============================================================================
// ONDULAÇÃO NO VERTEX SHADER
// Para waving da água sem custo no fragment
// ============================================================================

float vertexWave(vec3 position, float time) {
    float wave = 0.0;
    
    // Onda principal
    wave += sin(position.x * 0.5 + time) * 0.1;
    wave += cos(position.z * 0.3 + time * 0.8) * 0.15;
    
    // Ondas menores
    wave += sin(position.x * 2.0 - time * 1.5) * 0.05;
    wave += sin(position.z * 1.5 + time * 1.2) * 0.05;
    
    return wave;
}

// ============================================================================
// CHUVA NA SUPERFÍCIE DA ÁGUA
// Perturbações circulares
// ============================================================================

#ifdef RAIN_EFFECTS
float rainOnWater(vec2 uv, float time) {
    float perturbation = 0.0;
    
    // Gotas de chuva pseudo-aleatórias
    for (int i = 0; i < 4; i++) {
        float dropTime = mod(time + float(i) * 0.3, 1.0);
        vec2 dropPos = hash22(vec2(float(i), floor(time)));
        
        float dist = distance(uv, dropPos);
        float ripple = sin(dist * 50.0 - dropTime * 10.0) * exp(-dist * 5.0);
        ripple *= dropTime * (1.0 - dropTime) * 4.0;
        
        perturbation += ripple * 0.1;
    }
    
    return perturbation;
}
#endif

// ============================================================================
// FUNÇÃO PRINCIPAL DE RENDERIZAÇÃO DE ÁGUA
// Combina todos os efeitos
// ============================================================================

vec3 renderWater(
    vec2 uv,
    vec3 viewDir,
    vec3 normal,
    float time,
    sampler2D depthTex,
    sampler2D colorTex,
    vec3 lightDir,
    vec3 lightColor,
    float depth
) {
    // Gerar normais detalhadas
    vec3 waterNormal = generateWaterNormals(uv, time);
    
    // Combinar com normal geométrica
    waterNormal = normalize(waterNormal + normal * 0.5);
    
    // Fresnel
    float fresnel = waterFresnel(max(dot(viewDir, waterNormal), 0.0));
    
    // Reflexão SSR
    vec3 reflection = screenSpaceReflection(uv, viewDir, waterNormal, depthTex, colorTex);
    
    // Refração fake
    vec2 refractedUV = refractUV(uv, waterNormal, 0.02);
    vec3 refraction = texture2D(colorTex, refractedUV).rgb;
    
    // Specular do sol/lua
    vec3 specular = waterSpecular(waterNormal, viewDir, lightDir, lightColor);
    
    // Cáusticas
    vec3 caustics = fakeCaustics(uv, time, depth);
    
    // Cor base da água
    vec3 waterBase = WATER_BASE_COLOR;
    
    // Composição final
    vec3 result = mix(refraction, reflection, fresnel);
    result += specular;
    result += caustics;
    result = mix(result, waterBase, 0.2); // Tint leve
    
    return result;
}

#endif // WATER_GLSL
