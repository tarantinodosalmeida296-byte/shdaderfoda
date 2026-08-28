// ReMorganShaded v1.0 - Atmosphere Library
// Funções de atmosfera e céu otimizadas
// Modelo Preetham/Hosek simplificado com LUTs

#ifndef ATMOSPHERE_GLSL
#define ATMOSPHERE_GLSL

#include "lib/common.glsl"
#include "lib/noise.glsl"

// ============================================================================
// MODELO DE CÉU SIMPLIFICADO (Preetham-like)
// Evita cálculos físicos caros, usa aproximações artísticas
// ============================================================================

// Cores base do céu (dia)
const vec3 SKY_ZENITH_COLOR = vec3(0.4, 0.6, 1.0);
const vec3 SKY_HORIZON_COLOR = vec3(0.8, 0.9, 1.0);
const vec3 SUN_COLOR = vec3(1.0, 0.95, 0.8);
const vec3 MOON_COLOR = vec3(0.9, 0.95, 1.0);

// Cores do céu (noite)
const vec3 NIGHT_SKY_COLOR = vec3(0.02, 0.02, 0.08);
const vec3 NIGHT_HORIZON_COLOR = vec3(0.05, 0.05, 0.1);

// Cores do pôr do sol
const vec3 SUNSET_COLOR = vec3(1.0, 0.4, 0.2);
const vec3 SUNSET_HORIZON = vec3(0.8, 0.3, 0.1);

// ============================================================================
// FUNÇÃO DE DISTRIBUIÇÃO DO CÉU
// Calcula a cor do céu baseada no ângulo de visão
// ============================================================================

vec3 getSkyColor(vec3 viewDir, float sunFactor, float timeOfDay) {
    // Normalizar direção da vista
    viewDir = normalize(viewDir);
    
    // Calcular altura do sol acima do horizonte
    float sunHeight = dot(normalize(sunPosition), vec3(0.0, 1.0, 0.0));
    
    // Interpolação dia/noite
    float dayFactor = clamp(sunHeight * 2.0 + 0.5, 0.0, 1.0);
    float nightFactor = 1.0 - dayFactor;
    
    // Fator do pôr do sol (quando sol está perto do horizonte)
    float sunsetFactor = clamp(1.0 - abs(sunHeight) * 3.0, 0.0, 1.0);
    
    // Cor base do céu (zenith ao horizon)
    float height = viewDir.y;
    vec3 zenithColor = mix(NIGHT_SKY_COLOR, SKY_ZENITH_COLOR, dayFactor);
    vec3 horizonColor = mix(NIGHT_HORIZON_COLOR, SKY_HORIZON_COLOR, dayFactor);
    
    // Adicionar cor do pôr do sol
    zenithColor = mix(zenithColor, SUNSET_COLOR, sunsetFactor * 0.5);
    horizonColor = mix(horizonColor, SUNSET_HORIZON, sunsetFactor);
    
    // Interpolar entre zenith e horizon baseado na altura
    float t = pow(clamp(height, 0.0, 1.0), 0.5);
    vec3 skyColor = mix(horizonColor, zenithColor, t);
    
    // Adicionar contribuição do sol/lua
    float sunDot = max(dot(viewDir, normalize(sunPosition)), 0.0);
    float moonDot = max(dot(viewDir, normalize(moonPosition)), 0.0);
    
    // Glow ao redor do sol/lua
    float sunGlow = pow(sunDot, 64.0) * sunFactor;
    float moonGlow = pow(moonDot, 64.0) * (1.0 - sunFactor);
    
    skyColor += SUN_COLOR * sunGlow * 2.0;
    skyColor += MOON_COLOR * moonGlow * 1.5;
    
    // Estrelas à noite (hash procedural)
    if (nightFactor > 0.5) {
        float stars = hash(floor(viewDir.xy * 500.0));
        stars = step(0.997, stars) * nightFactor;
        skyColor += vec3(stars);
    }
    
    return skyColor;
}

// ============================================================================
// ATMOSPHERIC SCATTERING SIMPLIFICADO
// Rayleigh scattering approximation (sem Mie scattering caro)
// ============================================================================

vec3 atmosphericScattering(vec3 viewDir, vec3 lightDir, float altitude) {
    // Rayleigh scattering coefficient
    const vec3 rayleighCoeff = vec3(5.5e-6, 13.0e-6, 22.4e-6);
    
    // Phase function para Rayleigh
    float cosTheta = dot(viewDir, lightDir);
    float phase = 0.75 * (1.0 + cosTheta * cosTheta);
    
    // Optical depth baseado na altitude
    float opticalDepth = exp(-altitude * 0.0001);
    
    // Scatter
    vec3 scatter = rayleighCoeff * phase * opticalDepth;
    
    return scatter * 10.0; // Intensidade
}

// ============================================================================
// FOG ATMOSFÉRICO EXPONENCIAL
// Mais barato que volumetric fog real
// ============================================================================

vec3 exponentialFog(vec3 color, vec3 viewDir, float depth, float density) {
    // Fog baseado na distância
    float fogFactor = 1.0 - exp(-depth * density);
    fogFactor = clamp(fogFactor, 0.0, 1.0);
    
    // Cor do fog (baseada na cor do céu)
    vec3 fogColor = mix(SKY_HORIZON_COLOR, SKY_ZENITH_COLOR, 
                        max(viewDir.y, 0.0));
    
    return mix(color, fogColor, fogFactor);
}

// Height fog - mais denso perto do chão
vec3 heightFog(vec3 color, vec3 viewDir, float depth, float height) {
    // Density aumenta perto do ground
    float heightDensity = exp(-abs(height) * 0.1);
    float baseDensity = 0.0005;
    float totalDensity = baseDensity + heightDensity * 0.001;
    
    return exponentialFog(color, viewDir, depth, totalDensity);
}

// ============================================================================
// NUVENS VOLUMÉTRICAS FAKE
// Usa 2-3 camadas de noise 2D com parallax scrolling
// MUITO mais barato que ray marching 3D
// ============================================================================

float fakeVolumetricClouds(vec3 viewDir, float time) {
    // Projeção da direção de vista em um plano horizontal
    vec2 cloudUV = viewDir.xz / (abs(viewDir.y) + 0.1);
    
    // Altura das nuvens (só aparecem acima de certo ângulo)
    float cloudHeight = clamp(viewDir.y * 5.0, 0.0, 1.0);
    
    // Múltiplas camadas de nuvens com velocidades diferentes
    float clouds = 0.0;
    
    // Camada 1 - Base (lenta)
    clouds += cloudNoise(cloudUV * 0.5 + vec2(time * 0.01, 0.0), time) * 0.6;
    
    // Camada 2 - Detalhe (rápida)
    clouds += cloudNoise(cloudUV * 1.0 - vec2(time * 0.02, 0.0), time) * 0.3;
    
    // Camada 3 - Parallax (muito rápida, pequena escala)
    clouds += cloudNoise(cloudUV * 2.0 + vec2(time * 0.03, 0.0), time) * 0.1;
    
    // Suavizar e threshold
    clouds = smoothstep(0.4, 0.8, clouds);
    
    // Fade nas bordas
    clouds *= cloudHeight;
    
    return clouds;
}

// Renderiza nuvens com cor e sombra básica
vec3 renderFakeClouds(vec3 viewDir, vec3 lightDir, float time) {
    float cloudCoverage = fakeVolumetricClouds(viewDir, time);
    
    // Cor base das nuvens
    vec3 cloudColor = vec3(1.0);
    
    // Sombra simples baseada na direção da luz
    float lighting = max(dot(viewDir, lightDir) * 0.5 + 0.5, 0.3);
    cloudColor *= lighting;
    
    // Misturar com o céu
    return cloudColor * cloudCoverage;
}

// ============================================================================
| HALO/GLOW DO SOL E LUA
// Radial gradient barato
// ============================================================================

vec3 sunHalo(vec3 viewDir, vec3 sunDir, vec3 sunColor) {
    float sunDot = dot(normalize(viewDir), normalize(sunDir));
    
    // Halo interno brilhante
    float innerHalo = pow(max(sunDot, 0.0), 256.0);
    
    // Halo externo suave
    float outerHalo = pow(max(sunDot, 0.0), 16.0) * 0.1;
    
    // Ring (anel)
    float ring = sin(sunDot * 50.0) * 0.02;
    ring = max(ring, 0.0) * pow(max(sunDot, 0.0), 8.0);
    
    vec3 halo = sunColor * (innerHalo * 5.0 + outerHalo + ring);
    
    return halo;
}

// ============================================================================
| CREPUSCULO RAYS (God Rays) FAKE
// Screen-space rays baseados em shadow occlusion
// ============================================================================

vec3 fakeGodRays(vec2 uv, vec3 lightDir, float shadowOcclusion) {
    // Direção dos raios na tela
    vec2 sunPos = (lightDir.xy / abs(lightDir.z)) * 0.5 + 0.5;
    vec2 dir = uv - sunPos;
    float dist = length(dir);
    dir = normalize(dir);
    
    // Sample ao longo do raio (poucas amostras para performance)
    float rays = 0.0;
    float weight = 1.0;
    
    for (int i = 0; i < 8; i++) {
        float sampleDist = float(i) / 8.0 * dist;
        vec2 sampleUV = uv - dir * sampleDist * 0.5;
        
        // Simple check se está na direção do sol
        rays += weight * (1.0 - shadowOcclusion);
        weight *= 0.7;
    }
    
    rays *= 0.1;
    
    return vec3(rays) * vec3(1.0, 0.9, 0.7);
}

// ============================================================================
// TRANSIÇÃO DIA/NOITE SUAVE
// ============================================================================

float getDayNightFactor(float sunHeight) {
    // Transição suave entre dia e noite
    float day = clamp(sunHeight * 4.0 + 0.5, 0.0, 1.0);
    float night = 1.0 - day;
    return day;
}

vec3 blendDayNight(vec3 dayColor, vec3 nightColor, float sunHeight) {
    float factor = getDayNightFactor(sunHeight);
    return mix(nightColor, dayColor, factor);
}

// ============================================================================
// AURORA BOREAL (opcional, custo extra)
// Só ativa em altas latitudes (simulado)
// ============================================================================

#ifdef ENABLE_AURORA
vec3 auroraBorealis(vec3 viewDir, float latitude) {
    // Só aparece em altas latitudes
    if (latitude < 0.7) return vec3(0.0);
    
    vec2 auroraUV = viewDir.xz / (viewDir.y + 0.1);
    
    // Noise alongado na direção norte-sul
    float aurora = fbm2D(auroraUV * vec2(1.0, 3.0) + vec2(0.0, frameTimeCounter * 0.05), 3);
    aurora = smoothstep(0.5, 0.8, aurora);
    
    // Cor verde característica
    vec3 auroraColor = vec3(0.2, 1.0, 0.5) * aurora;
    
    return auroraColor * latitude;
}
#endif

#endif // ATMOSPHERE_GLSL
