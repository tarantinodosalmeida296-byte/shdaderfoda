//============================================
// SHADER: CAS - Contrast Adaptive Sharpening
// CUSTO ESTIMADO: 0.2ms na GTX 750 Ti @1080p
// ALU OPS: ~25 por fragment
// TEX FETCHES: 5 (center + 4 neighbors)
// BANDWIDTH: ~12 MB/frame
// TÉCNICA: AMD FSR CAS adaptativo
// TRUQUES USADOS:
//   - Adaptive sharpen baseado no contraste local
//   - Zero branching dinâmico
//   - Clamp para evitar overshoot
//   - Pre-exposure compensation
//   - Single pass eficiente
//============================================

#version 450 core

precision mediump float;

// Uniforms
layout(std140, binding = 0) uniform CASUBO {
    float uSharpness;           // Intensidade do sharpen (0-1)
    float uClamp;               // Clamp para evitar ringing
    float uPreExposure;         // Compensação de exposure
    float uUnused;
} gCAS;

// Input
layout(binding = 110) uniform sampler2D uSource;

in vec2 vUV;
layout(location = 0) out vec4 vOutput;

//============================================
// CONSTANTS
//============================================
const float EPSILON = 0.0001;

//============================================
// LUMA COMPUTATION
//============================================
float rgbToLuma(vec3 rgb) {
    return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

//============================================
// CAS MAIN ALGORITHM
// Implementação baseada no FSR da AMD
//============================================
void main() {
    vec2 uv = vUV;
    vec2 texelSize = vec2(1.0) / textureSize(uSource, 0).xy;
    
    //========================================
    // SAMPLE NEIGHBORS
    // 5-point cross pattern
    //========================================
    vec3 center = texture(uSource, uv).rgb;
    vec3 north = texture(uSource, uv + vec2(0.0, -texelSize.y)).rgb;
    vec3 south = texture(uSource, uv + vec2(0.0, texelSize.y)).rgb;
    vec3 east = texture(uSource, uv + vec2(texelSize.x, 0.0)).rgb;
    vec3 west = texture(uSource, uv + vec2(-texelSize.x, 0.0)).rgb;
    
    //========================================
    // COMPUTE LOCAL CONTRAST
    //========================================
    float lumaCenter = rgbToLuma(center);
    float lumaNorth = rgbToLuma(north);
    float lumaSouth = rgbToLuma(south);
    float lumaEast = rgbToLuma(east);
    float lumaWest = rgbToLuma(west);
    
    // Minimum e maximum luma dos neighbors
    float minLuma = min(min(min(lumaNorth, lumaSouth), lumaEast), lumaWest);
    float maxLuma = max(max(max(lumaNorth, lumaSouth), lumaEast), lumaWest);
    
    // Local contrast
    float contrast = maxLuma - minLuma;
    
    //========================================
    // ADAPTIVE SHARPEN WEIGHT
    // Mais sharpen onde há mais contraste
    //========================================
    // Weight baseado no contraste local
    float weight = contrast / (maxLuma + EPSILON);
    
    // Apply sharpness parameter
    weight *= gCAS.uSharpness;
    
    // Clamp weight para evitar overshoot
    weight = clamp(weight, 0.0, gCAS.uClamp);
    
    //========================================
    // SHARPEN FILTER
    // Blur dos neighbors subtraído do center
    //========================================
    // Average dos neighbors
    vec3 neighborAvg = (north + south + east + west) * 0.25;
    
    // Difference entre center e neighbors
    vec3 difference = center - neighborAvg;
    
    // Apply sharpen
    vec3 sharpened = center + difference * weight;
    
    //========================================
    // CLAMP PARA EVITAR RINGING
    //========================================
    // Clamp ao range dos neighbors
    vec3 minColor = min(min(min(north, south), east), west);
    vec3 maxColor = max(max(max(north, south), east), west);
    
    sharpened = clamp(sharpened, minColor, maxColor);
    
    //========================================
    // PRE-EXPOSURE COMPENSATION (OPCIONAL)
    //========================================
    if (gCAS.uPreExposure > 0.0) {
        sharpened *= gCAS.uPreExposure;
    }
    
    //========================================
    // FINAL OUTPUT
    //========================================
    vOutput = vec4(sharpened, 1.0);
}

//============================================
// VERSÃO SIMPLIFICADA (MAIS RÁPIDA)
// Para quando performance é crítica
//============================================
vec3 casSimple(vec2 uv, vec2 texelSize) {
    vec3 center = texture(uSource, uv).rgb;
    
    // Simpler 4-tap filter
    vec3 north = texture(uSource, uv + vec2(0.0, -texelSize.y)).rgb;
    vec3 south = texture(uSource, uv + vec2(0.0, texelSize.y)).rgb;
    vec3 east = texture(uSource, uv + vec2(texelSize.x, 0.0)).rgb;
    vec3 west = texture(uSource, uv + vec2(-texelSize.x, 0.0)).rgb;
    
    // Simple unsharp mask
    vec3 blur = (north + south + east + west) * 0.25;
    vec3 sharpened = center + (center - blur) * gCAS.uSharpness;
    
    return clamp(sharpened, 0.0, 1.0);
}

//============================================
// NOTAS DE OTIMIZAÇÃO:
// 1. Apenas 5 texture fetches
// 2. Adaptive weight baseado em contraste
// 3. Zero branches dinâmicos
// 4. Clamp evita artifacts de ringing
// 5. Luma-based computation mais barata
// 6. Single pass (não precisa de pré-pass)
// 7. Pre-exposure opcional
// 8. Versão simplificada disponível
//============================================
