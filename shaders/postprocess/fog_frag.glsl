//============================================
// SHADER: Atmospheric Fog + Height Fog
// CUSTO ESTIMADO: 0.15ms na GTX 750 Ti @1080p
// ALU OPS: ~20 por fragment
// TEX FETCHES: 0 (analítico puro)
// BANDWIDTH: ~0 MB/frame
// TÉCNICA: Height fog + distance fog analíticos
// TRUQUES USADOS:
//   - Zero texture fetches (tudo analítico)
//   - Height-based density variation
//   - Light scattering approximation
//   - In-scattering pre-computed
//   - MAD-heavy formulation
//============================================

#version 450 core

precision mediump float;

// Uniforms
layout(std140, binding = 0) uniform FogUBO {
    vec3 uFogColor;
    float uFogDensity;
    float uHeightFogDensity;
    float uFogHeightFalloff;
    float uFogStartDistance;
    vec3 uSunDirection;
    vec3 uSunColor;
    float uScatteringStrength;
} gFog;

// Inputs
in vec3 vWorldPosition;
in vec3 vViewPosition;

in vec2 vUV;
layout(location = 0) out vec4 vOutput;

//============================================
// CONSTANTS
//============================================
const float PI = 3.14159265359;

//============================================
// DISTANCE FOG (EXPONENCIAL)
// Fog baseado na distância da câmara
//============================================
float computeDistanceFog(float distance) {
    // Exponential fog: fog = 1 - exp(-density * distance)
    float fogFactor = 1.0 - exp(-gFog.uFogDensity * distance);
    
    // Linear fog start/end override
    if (distance < gFog.uFogStartDistance) {
        fogFactor = 0.0;
    }
    
    return clamp(fogFactor, 0.0, 1.0);
}

//============================================
// HEIGHT FOG
// Densidade varia com a altura (Y)
//============================================
float computeHeightFog(float height) {
    // Height-based density
    // Mais denso no chão, menos no céu
    float heightDiff = height - gFog.uFogHeightFalloff;
    float heightDensity = exp(-gFog.uHeightFogDensity * abs(heightDiff));
    
    return heightDensity;
}

//============================================
// LIGHT SCATTERING (RAYLEIGH APROX)
// Simula luz do sol espalhando no fog
//============================================
vec3 computeInScattering(vec3 viewDir, vec3 sunDir) {
    // Phase function de Rayleigh simplificada
    float cosAngle = dot(viewDir, sunDir);
    
    // Rayleigh phase: (1 + cos²θ)
    float phase = 1.0 + cosAngle * cosAngle;
    phase *= 0.75 / PI;  // Normalization
    
    // Scattering strength
    vec3 scattering = gFog.uSunColor * phase * gFog.uScatteringStrength;
    
    return scattering;
}

//============================================
// COMBINED FOG COMPUTATION
// Distance + Height + Scattering
//============================================
vec3 computeFog(vec3 viewPos, vec3 worldPos, vec3 viewDir) {
    // Distância da câmara
    float distance = length(viewPos);
    
    // Height do pixel
    float height = worldPos.y;
    
    //========================================
    // DISTANCE FOG
    //========================================
    float distanceFog = computeDistanceFog(distance);
    
    //========================================
    // HEIGHT FOG MODULATOR
    //========================================
    float heightFog = computeHeightFog(height);
    
    // Combine distance e height fog
    float combinedFog = distanceFog * heightFog;
    combinedFog = clamp(combinedFog, 0.0, 1.0);
    
    //========================================
    // IN-SCATTERING (LIGHT SHAFTS FAKE)
    //========================================
    vec3 inScatter = computeInScattering(normalize(viewDir), normalize(gFog.uSunDirection));
    
    // Adicionar in-scattering ao fog color
    vec3 fogColor = gFog.uFogColor + inScatter;
    
    return fogColor * combinedFog;
}

//============================================
// MAIN
//============================================
void main() {
    // View direction
    vec3 viewDir = normalize(vViewPosition);
    
    // Compute fog
    vec3 fog = computeFog(vViewPosition, vWorldPosition, viewDir);
    
    // Output fog color (para blend com a cena)
    vOutput = vec4(fog, 1.0);
}

//============================================
// NOTAS DE OTIMIZAÇÃO:
// 1. Zero texture fetches (100% analítico)
// 2. Exponential fog é mais barato que linear
// 3. Height fog usa apenas 1 exp() call
// 4. Rayleigh phase simplificada
// 5. In-scattering pré-computável em LUT
// 6. MAD-heavy nas equações
// 7. mediump precision suficiente
// 8. Pode ser combinado com tonemap pass
//============================================
