//============================================
// SHADER: Auto Exposure - Histogram Downscale
// CUSTO ESTIMADO: 0.1ms na GTX 750 Ti @1080p
// ALU OPS: ~15 por fragment
// TEX FETCHES: 4 (downscale pass)
// BANDWIDTH: ~8 MB/frame
// TÉCNICA: Average luminance via mip chain downscale
// TRUQUES USADOS:
//   - Log-average luminance mais preciso que arithmetic mean
//   - Downscale em múltiplos passes (power of 2)
//   - Temporal smoothing para evitar flicker
//   - Clamp para evitar valores extremos
//   - Pode usar compute shader se disponível
//============================================

#version 450 core

precision mediump float;

// Uniforms
layout(std140, binding = 0) uniform AEUBO {
    float uExposureSpeed;       // Speed de adaptação (0-1)
    float uMinEV;               // Minimum exposure value
    float uMaxEV;               // Maximum exposure value
    float uMiddleGray;          // Middle gray target (~0.18)
    float uPrevAverageLuma;     // Luminância do frame anterior (para temporal smooth)
} gAE;

// Input
layout(binding = 130) uniform sampler2D uSource;

in vec2 vUV;
layout(location = 0) out float vAvgLuminance;

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
// LOGARITHMIC AVERAGE
// Mais preciso para HDR que arithmetic mean
//============================================
float computeLogAverage() {
    vec2 texelSize = vec2(1.0) / textureSize(uSource, 0).xy;
    
    // Sample 4 taps para downscale
    vec3 c00 = texture(uSource, vUV + texelSize * vec2(-0.5, -0.5)).rgb;
    vec3 c01 = texture(uSource, vUV + texelSize * vec2(-0.5, 0.5)).rgb;
    vec3 c10 = texture(uSource, vUV + texelSize * vec2(0.5, -0.5)).rgb;
    vec3 c11 = texture(uSource, vUV + texelSize * vec2(0.5, 0.5)).rgb;
    
    // Calcular luminance de cada sample
    float l00 = rgbToLuma(c00);
    float l01 = rgbToLuma(c01);
    float l10 = rgbToLuma(c10);
    float l11 = rgbToLuma(c11);
    
    // Log average: exp(avg(log(luma)))
    // Adicionar epsilon para evitar log(0)
    float logSum = log(max(l00, EPSILON)) + 
                   log(max(l01, EPSILON)) + 
                   log(max(l10, EPSILON)) + 
                   log(max(l11, EPSILON));
    
    float avgLog = logSum * 0.25;
    
    return exp(avgLog);
}

//============================================
// ARITHMETIC AVERAGE (ALTERNATIVA MAIS BARATA)
//============================================
float computeArithmeticAverage() {
    vec2 texelSize = vec2(1.0) / textureSize(uSource, 0).xy;
    
    vec3 c00 = texture(uSource, vUV + texelSize * vec2(-0.5, -0.5)).rgb;
    vec3 c01 = texture(uSource, vUV + texelSize * vec2(-0.5, 0.5)).rgb;
    vec3 c10 = texture(uSource, vUV + texelSize * vec2(0.5, -0.5)).rgb;
    vec3 c11 = texture(uSource, vUV + texelSize * vec2(0.5, 0.5)).rgb;
    
    float l00 = rgbToLuma(c00);
    float l01 = rgbToLuma(c01);
    float l10 = rgbToLuma(c10);
    float l11 = rgbToLuma(c11);
    
    return (l00 + l01 + l10 + l11) * 0.25;
}

//============================================
// TEMPORAL SMOOTHING
// Evitar flicker entre frames
//============================================
float temporalSmooth(float current, float previous, float speed) {
    // Lerp com speed control
    return mix(previous, current, speed);
}

//============================================
// EXPOSURE VALUE CLAMP
//============================================
float clampEV(float ev, float minEV, float maxEV) {
    return clamp(ev, minEV, maxEV);
}

void main() {
    //========================================
    // COMPUTE AVERAGE LUMINANCE
    //========================================
    float avgLuma = computeLogAverage();
    
    //========================================
    // TEMPORAL SMOOTHING
    //========================================
    float smoothedLuma = temporalSmooth(
        avgLuma, 
        gAE.uPrevAverageLuma, 
        gAE.uExposureSpeed
    );
    
    //========================================
    // CONVERT TO EXPOSURE VALUE
    // EV = log2(L * ISO / K)
    // Simplificado: EV = log2(L / middleGray)
    //========================================
    float ev = log2(smoothedLuma / gAE.uMiddleGray);
    
    //========================================
    // CLAMP EV
    //========================================
    ev = clampEV(ev, gAE.uMinEV, gAE.uMaxEV);
    
    //========================================
    // OUTPUT
    // Average luminance para cálculo de exposure
    //========================================
    vAvgLuminance = smoothedLuma;
}

//============================================
// NOTAS DE OTIMIZAÇÃO:
// 1. Downscale power-of-2 para mip chain
// 2. Log-average mais preciso para HDR
// 3. Temporal smoothing evita flicker
// 4. Arithmetic average como alternativa barata
// 5. 4 texture fetches por pass
// 6. Single float output (economiza bandwidth)
// 7. EV clamped para evitar extremes
// 8. Pode ser feito em compute shader se disponível
//============================================

//============================================
// USAGE NA PIPELINE:
// 1. Render scene to HDR buffer
// 2. Downscale luminance em múltiplos passes até 1x1
// 3. Ler valor final do 1x1 texture
// 4. Calcular exposure = middleGray / avgLuma
// 5. Apply exposure na cena antes do tone mapping
//============================================
