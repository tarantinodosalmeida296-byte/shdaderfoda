// ReMorganShaded v1.0 - Post-Processing Library
// Funções de pós-processamento otimizadas
// Bloom, Tone Mapping, Color Grading, TAA, DoF, Motion Blur

#ifndef POST_GLSL
#define POST_GLSL

#include "lib/common.glsl"

// ============================================================================
// BLOOM - Downscale progressivo com blur separável
// 4 passes de downscale, blur gaussiano separável
// ============================================================================

// Kernel Gaussiano 1D (5 taps)
const float GaussianKernel[5] = float[](0.06136, 0.24477, 0.38774, 0.24477, 0.06136);

// Blur horizontal (separável - mais barato que 2D)
vec3 blurHorizontal(sampler2D tex, vec2 uv, float texelSize) {
    vec3 color = vec3(0.0);
    
    for (int i = -2; i <= 2; i++) {
        vec2 offset = vec2(float(i) * texelSize, 0.0);
        color += texture2D(tex, uv + offset).rgb * GaussianKernel[i + 2];
    }
    
    return color;
}

// Blur vertical (separável)
vec3 blurVertical(sampler2D tex, vec2 uv, float texelSize) {
    vec3 color = vec3(0.0);
    
    for (int i = -2; i <= 2; i++) {
        vec2 offset = vec2(0.0, float(i) * texelSize);
        color += texture2D(tex, uv + offset).rgb * GaussianKernel[i + 2];
    }
    
    return color;
}

// Blur mais simples (3 taps) para hardware fraco
vec3 blurHorizontalLow(sampler2D tex, vec2 uv, float texelSize) {
    vec3 center = texture2D(tex, uv).rgb;
    vec3 left = texture2D(tex, uv + vec2(-texelSize, 0.0)).rgb;
    vec3 right = texture2D(tex, uv + vec2(texelSize, 0.0)).rgb;
    
    return (left + center * 2.0 + right) * 0.25;
}

vec3 blurVerticalLow(sampler2D tex, vec2 uv, float texelSize) {
    vec3 center = texture2D(tex, uv).rgb;
    vec3 up = texture2D(tex, uv + vec2(0.0, -texelSize)).rgb;
    vec3 down = texture2D(tex, uv + vec2(0.0, texelSize)).rgb;
    
    return (up + center * 2.0 + down) * 0.25;
}

// Extrair áreas brilhantes para bloom
vec3 extractBright(vec3 color, float threshold) {
    float brightness = dot(color, vec3(0.299, 0.587, 0.114));
    float exceedance = max(0.0, brightness - threshold);
    
    // Suavizar transição
    float softThreshold = smoothstep(0.0, 1.0, exceedance);
    
    return color * softThreshold;
}

// ============================================================================
// TONE MAPPING
// ACES Filmic e Reinhard
// ============================================================================

// Já definido em common.glsl, mas aqui temos variantes

// Tone mapping com controle de exposure
vec3 toneMapACES(vec3 color, float exposure) {
    color *= exposure;
    return ACESFilmic(color);
}

// Uncharted 2 tone mapping (alternativa)
vec3 toneMapUncharted2(vec3 color) {
    const float A = 0.15;
    const float B = 0.50;
    const float C = 0.10;
    const float D = 0.20;
    const float E = 0.02;
    const float F = 0.30;
    
    return ((color * (A * color + C * B) + D * E) / 
            (color * (A * color + B) + D * F)) - E / F;
}

// ============================================================================
// COLOR GRADING VIA LUT 3D SIMPLIFICADA
// Usa interpolação trilinear em LUT pequena (32x32x32)
// ============================================================================

vec3 applyColorGrading(vec3 color, sampler3D lut3D) {
    // Mapear cor para UVW da LUT
    vec3 lutUVW = color * (1.0 / 32.0) + (0.5 / 32.0);
    
    return texture3D(lut3D, lutUVW).rgb;
}

// Color grading manual (sem LUT - mais barato)
vec3 manualColorGrade(vec3 color, vec3 gain, vec3 lift, vec3 gamma) {
    // Lift (sombras)
    color = color + lift * (1.0 - color);
    
    // Gain (altas luzes)
    color = color * gain;
    
    // Gamma (midtones)
    color = pow(color, 1.0 / gamma);
    
    return color;
}

// Curva de contraste S-curve barata
vec3 contrastCurve(vec3 color, float contrast) {
    return (color - 0.5) * contrast + 0.5;
}

// Saturação
vec3 adjustSaturation(vec3 color, float saturation) {
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 gray = vec3(luminance);
    
    return mix(gray, color, saturation);
}

// ============================================================================
// TEMPORAL ANTI-ALIASING (TAA) LEVE
// 2 frames de história com blend adaptativo
// ============================================================================

// Neighborhood Clipping para TAA
vec3 neighborhoodClipping(vec3 current, vec3 history, sampler2D colorTex, vec2 uv) {
    // Pegar vizinhos
    vec2 texelSize = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    
    vec3 n1 = texture2D(colorTex, uv + vec2(texelSize.x, 0.0)).rgb;
    vec3 n2 = texture2D(colorTex, uv - vec2(texelSize.x, 0.0)).rgb;
    vec3 n3 = texture2D(colorTex, uv + vec2(0.0, texelSize.y)).rgb;
    vec3 n4 = texture2D(colorTex, uv - vec2(0.0, texelSize.y)).rgb;
    
    // Encontrar min/max do neighborhood
    vec3 minNeighbor = min(min(min(n1, n2), n3), n4);
    vec3 maxNeighbor = max(max(max(n1, n2), n3), n4);
    
    // Clamp history ao range do neighborhood
    return clamp(history, minNeighbor, maxNeighbor);
}

// Blend TAA com detecção de movimento
vec3 taablend(vec3 current, vec3 history, float motionFactor) {
    // Menos blend onde há muito movimento
    float blendWeight = 0.5 * (1.0 - motionFactor);
    
    return mix(current, history, blendWeight);
}

// ============================================================================
| MOTION BLUR PER-PIXEL ULTRALEVE
// Apenas camera motion, 4 samples
// ============================================================================

vec3 motionBlur(sampler2D colorTex, vec2 uv, vec2 motionVector, float shutterSpeed) {
    #ifdef MOTION_BLUR_ON
    vec3 color = vec3(0.0);
    
    // 4 samples ao longo do motion vector
    for (int i = 0; i < 4; i++) {
        float t = float(i) / 3.0;
        vec2 sampleUV = uv - motionVector * (t - 0.5) * shutterSpeed;
        
        color += texture2D(colorTex, sampleUV).rgb;
    }
    
    return color * 0.25;
    #else
    return texture2D(colorTex, uv).rgb;
    #endif
}

// ============================================================================
// DEPTH OF FIELD (CoC + Blur Separável)
// Quarto de resolução, blur baseado em circle of confusion
// ============================================================================

float calculateCoC(float depth, float focusDistance, float focalLength, float fStop) {
    // Circle of Confusion
    float coc = abs(depth - focusDistance) / depth;
    coc *= focalLength * focalLength / (fStop * (focusDistance - focalLength));
    
    return coc * 100.0; // Scale para pixels
}

// Blur com CoC variável (aproximação barata)
vec3 dofBlur(sampler2D tex, vec2 uv, float coc) {
    // Limitar CoC para performance
    coc = clamp(coc, 0.0, 4.0);
    
    int kernelSize = int(coc) + 1;
    kernelSize = min(kernelSize, 5);
    
    vec3 color = vec3(0.0);
    float totalWeight = 0.0;
    
    float texelSize = 1.0 / 256.0; // Quarter res
    
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            if (abs(x) > kernelSize || abs(y) > kernelSize) continue;
            
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            float weight = exp(-dot(offset, offset) * 10.0);
            
            color += texture2D(tex, uv + offset).rgb * weight;
            totalWeight += weight;
        }
    }
    
    return color / totalWeight;
}

// ============================================================================
// VINHETA
// Escurecimento nas bordas
// ============================================================================

vec3 applyVignette(vec3 color, vec2 uv, float strength, float roundness) {
    // Distância do centro
    vec2 center = vec2(0.5);
    float dist = distance(uv, center);
    
    // Vinheta suave
    float vignette = 1.0 - pow(dist * 2.0, roundness) * strength;
    vignette = clamp(vignette, 0.0, 1.0);
    
    return color * vignette;
}

// ============================================================================
// FILM GRAIN PROCEDURAL
// Hash function, sem textura extra
// ============================================================================

vec3 applyFilmGrain(vec3 color, vec2 uv, float intensity) {
    // Grain baseado em hash temporal
    float grain = hash(uv * vec2(viewWidth, viewHeight) + float(frameCounter));
    grain = (grain - 0.5) * intensity;
    
    return color + vec3(grain);
}

// Grain colorido (mais realista)
vec3 applyColorFilmGrain(vec3 color, vec2 uv, float intensity) {
    float grainR = hash(uv * vec2(viewWidth, viewHeight) + float(frameCounter));
    float grainG = hash(uv * vec2(viewWidth * 1.1, viewHeight * 0.9) + float(frameCounter));
    float grainB = hash(uv * vec2(viewWidth * 0.9, viewHeight * 1.1) + float(frameCounter));
    
    vec3 grain = vec3(grainR, grainG, grainB) - 0.5;
    grain *= intensity;
    
    return color + grain;
}

// ============================================================================
// LENS FLARE DO SOL
// 2-3 ghosts baseados em textura
// ============================================================================

vec3 lensFlare(vec2 uv, vec2 sunPos, vec3 sunColor, float intensity) {
    vec3 flare = vec3(0.0);
    
    // Direção do sol ao centro
    vec2 dir = normalize(sunPos - vec2(0.5));
    float distToSun = distance(uv, sunPos);
    
    // Ghosts ao longo da linha entre sol e centro
    float ghostPositions[3] = float[](0.2, 0.5, 0.8);
    float ghostSizes[3] = float[](0.02, 0.04, 0.03);
    vec3 ghostColors[3] = vec3[](
        vec3(1.0, 0.8, 0.6),
        vec3(0.8, 0.6, 1.0),
        vec3(0.6, 0.8, 1.0)
    );
    
    for (int i = 0; i < 3; i++) {
        vec2 ghostPos = mix(vec2(0.5), sunPos, ghostPositions[i]);
        float ghostDist = distance(uv, ghostPos);
        
        float ghost = 1.0 - smoothstep(0.0, ghostSizes[i], ghostDist);
        ghost *= (1.0 - distToSun * 2.0); // Fade quando longe do sol
        
        flare += ghostColors[i] * ghost;
    }
    
    // Anel externo
    float ring = 1.0 - smoothstep(0.1, 0.15, distToSun);
    ring *= smoothstep(0.0, 0.05, distToSun);
    flare += vec3(0.5, 0.3, 0.8) * ring * 0.3;
    
    return flare * intensity;
}

// ============================================================================
// CHROMATIC ABERRATION
// Separação de canais RGB nas bordas
// ============================================================================

vec3 chromaticAberration(sampler2D tex, vec2 uv, vec2 distortion, float strength) {
    float r = texture2DLod(tex, uv + distortion * strength, 0.0).r;
    float g = texture2DLod(tex, uv, 0.0).g;
    float b = texture2DLod(tex, uv - distortion * strength, 0.0).b;
    
    return vec3(r, g, b);
}

// ============================================================================
// SHARPENING
// Unsharp mask
// ============================================================================

vec3 sharpen(sampler2D tex, vec2 uv, float strength) {
    vec2 texelSize = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    
    // Blur leve
    vec3 blurred = vec3(0.0);
    blurred += texture2D(tex, uv).rgb * 0.5;
    blurred += texture2D(tex, uv + vec2(texelSize.x, 0.0)).rgb * 0.125;
    blurred += texture2D(tex, uv - vec2(texelSize.x, 0.0)).rgb * 0.125;
    blurred += texture2D(tex, uv + vec2(0.0, texelSize.y)).rgb * 0.125;
    blurred += texture2D(tex, uv - vec2(0.0, texelSize.y)).rgb * 0.125;
    
    // Unsharp mask
    vec3 original = texture2D(tex, uv).rgb;
    vec3 sharpened = original + (original - blurred) * strength;
    
    return sharpened;
}

// ============================================================================
// ADAPTIVE EXPOSURE
// Baseado na luminosidade média da cena
// ============================================================================

float calculateExposure(float avgLuminance, float key, float white, float black) {
    // Simple exposure calculation
    return key / (avgLuminance + 0.001);
}

// Eye adaptation simulation (lerp lento)
float adaptExposure(float currentExposure, float targetExposure, float adaptationSpeed) {
    return mix(currentExposure, targetExposure, adaptationSpeed);
}

// ============================================================================
// DITHERING PARA REDUÇÃO DE COLOR BANDNG
// Bayer 8x8 já definido em common.glsl
// ============================================================================

vec3 applyTemporalDithering(vec3 color, vec2 fragCoord, int frame) {
    // Rotacionar matriz de Bayer a cada frame
    float phase = float(frame % 4) * PI2 / 4.0;
    mat2 rotation = mat2(cos(phase), sin(phase), -sin(phase), cos(phase));
    
    vec2 rotatedCoord = rotation * fragCoord;
    float dither = getBayerFactor(rotatedCoord);
    
    return color + (dither - 0.5) * (1.0 / 255.0) * 4.0;
}

#endif // POST_GLSL
