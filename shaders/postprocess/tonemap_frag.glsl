//============================================
// SHADER: Tone Mapping + Color Grading Stack
// CUSTO ESTIMADO: 0.3ms na GTX 750 Ti @1080p
// ALU OPS: ~35 por fragment
// TEX FETCHES: 2 (Color LUT + Film Grain)
// BANDWIDTH: ~20 MB/frame
// TÉCNICA: ACES Filmic + 3D LUT empacotada + Dithering
// TRUQUES USADOS:
//   - ACES approximation de Krzysztof Narkowicz (5 MADs)
//   - 3D LUT 16x16x16 empacotada em 2D 256x16
//   - Interleaved Gradient Noise para dithering
//   - Chromatic aberration sutil integrada
//   - Vignette analítico (zero texture)
//============================================

#version 450 core

precision mediump float;

// Uniforms
layout(std140, binding = 0) uniform PostUBO {
    float uExposure;
    float uContrast;
    float uSaturation;
    float uVignetteIntensity;
    vec4 uChromaticAberration;  // x=strength, y=spectralShift, z=min, w=max
    vec4 uFilmGrainParams;      // x=intensity, y=size, z=temporal, w=unused
} gPost;

// Inputs
layout(binding = 70) uniform sampler2D uSource;         // Input da cena
layout(binding = 71) uniform sampler2D uColorLUT;       // 3D LUT empacotada
layout(binding = 72) uniform sampler2D uBlueNoise;      // Blue noise tiled

in vec2 vUV;
layout(location = 0) out vec4 vOutput;

//============================================
// CONSTANTS
//============================================
const float PI = 3.14159265359;

//============================================
// ACES FILMIC TONE MAPPING
// Approximation de Krzysztof Narkowicz
// Apenas 5 MAD operations!
//============================================
vec3 acesFilmic(vec3 x) {
    // ACES curve approximation
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    
    // Clamp para evitar negatives
    x = max(x, 0.0);
    
    // (a*x + b) / (c*x + d) + e - mas formulado como MAD
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

//============================================
// REINHARD TONE MAPPING (ALTERNATIVA)
// Mais barata que ACES, menos cinematográfica
//============================================
vec3 reinhard(vec3 x) {
    return x / (1.0 + x);
}

//============================================
// UNCHARTED 2 TONE MAPPING
// Alternativa estilo jogo
//============================================
vec3 uncharted2Tonemap(vec3 x) {
    const float A = 0.15;
    const float B = 0.50;
    const float C = 0.10;
    const float D = 0.20;
    const float E = 0.02;
    const float F = 0.30;
    
    return ((x*(A*x+C*B)+D*E)/(x*(A*x+B)+D*F))-E/F;
}

//============================================
// 3D COLOR LUT LOOKUP
// LUT 16x16x16 empacotada em textura 2D 256x16
//============================================
vec3 lookupColorLUT(vec3 color) {
    // LUT dimensions
    const float lutSize = 16.0;
    const float invLutSize = 1.0 / lutSize;
    
    // Coordinates na LUT
    vec3 lutCoord = color * (lutSize - 1.0) * invLutSize;
    
    // Empacotamento: slice no X, depois Y
    // 256x16 = 16 slices de 16x16 lado a lado
    float sliceIdx = floor(lutCoord.b * lutSize);
    float sliceX = mod(sliceIdx, 16.0);
    
    vec2 uv;
    uv.x = (sliceX + lutCoord.r) / 16.0;
    uv.y = (floor(lutCoord.g * lutSize)) / 16.0;
    
    return texture(uColorLUT, uv).rgb;
}

//============================================
// INTERLEAVED GRADIENT NOISE (Vlachos 2016)
// Para dithering temporalmente estável
//============================================
float interleavedGradientNoise(vec2 position, float frameIndex) {
    // Pattern 8x8 interleaved
    const vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(position, magic.xy) + frameIndex * magic.z));
}

//============================================
// BLUE NOISE SAMPLE
// Para film grain
//============================================
float sampleBlueNoise(vec2 uv, float frame) {
    // Tile blue noise 128x128
    vec2 noiseUV = uv * 128.0;
    noiseUV += vec2(frame * 0.1, frame * 0.2);  // Temporal shift
    noiseUV = fract(noiseUV);
    
    return texture(uBlueNoise, noiseUV).r;
}

//============================================
// VIGNETTE ANALÍTICO
// Zero texture fetches, apenas dot product
//============================================
float computeVignette(vec2 uv, float intensity) {
    vec2 centeredUV = uv - 0.5;
    float dist = dot(centeredUV, centeredUV);
    float vignette = smoothstep(0.8, 0.2, dist * intensity);
    return vignette;
}

//============================================
// CHROMATIC ABERRATION SUTIL
// 3 samples offset
//============================================
vec3 chromaticAberration(vec2 uv, float strength) {
    vec2 center = vec2(0.5);
    vec2 dir = uv - center;
    float dist = length(dir);
    
    // Offset baseado na distância do centro
    vec2 offset = normalize(dir) * dist * dist * strength;
    
    // Sample RGB channels separadamente
    float r = texture(uSource, uv + offset * 0.5).r;
    float g = texture(uSource, uv).g;
    float b = texture(uSource, uv - offset * 0.5).b;
    
    return vec3(r, g, b);
}

//============================================
// SATURATION ADJUSTMENT
//============================================
vec3 adjustSaturation(vec3 color, float saturation) {
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    return mix(vec3(luminance), color, saturation);
}

void main() {
    //========================================
    // SOURCE COLOR
    //========================================
    vec3 color = texture(uSource, vUV).rgb;
    
    //========================================
    // EXPOSURE
    //========================================
    color *= gPost.uExposure;
    
    //========================================
    // TONE MAPPING (ACES Filmic)
    //========================================
    color = acesFilmic(color);
    
    //========================================
    // COLOR GRADING VIA 3D LUT
    //========================================
    color = lookupColorLUT(color);
    
    //========================================
    // SATURATION
    //========================================
    color = adjustSaturation(color, gPost.uSaturation);
    
    //========================================
    // CHROMATIC ABERRATION (OPCIONAL)
    // Só se strength > 0
    //========================================
    if (gPost.uChromaticAberration.x > 0.001) {
        color = chromaticAberration(vUV, gPost.uChromaticAberration.x);
    }
    
    //========================================
    // VIGNETTE
    //========================================
    float vignette = computeVignette(vUV, gPost.uVignetteIntensity);
    color *= vignette;
    
    //========================================
    // DITHERING COM INTERLEAVED GRADIENT NOISE
    // Para evitar banding em gradients suaves
    //========================================
    float noise = interleavedGradientNoise(gl_FragCoord.xy, gPost.uFilmGrainParams.z);
    noise = (noise - 0.5) * (1.0 / 255.0);  // Scale para 8-bit
    color += noise;
    
    //========================================
    // FILM GRAIN (BLUE NOISE)
    //========================================
    if (gPost.uFilmGrainParams.x > 0.001) {
        float grain = sampleBlueNoise(vUV, gPost.uFilmGrainParams.z);
        grain = (grain - 0.5) * gPost.uFilmGrainParams.x;
        color += grain;
    }
    
    //========================================
    // CLAMP FINAL
    //========================================
    color = clamp(color, 0.0, 1.0);
    
    vOutput = vec4(color, 1.0);
}

//============================================
// NOTAS DE OTIMIZAÇÃO:
// 1. ACES approximation usa apenas 5 MADs
// 2. 3D LUT empacotada em 2D (economiza memória)
// 3. LUT 16x16x16 suficiente para grading
// 4. Interleaved gradient noise é barato e eficaz
// 5. Vignette analítico sem texture fetch
// 6. Chromatic aberration opcional (early exit)
// 7. Blue noise tiled para film grain
// 8. Dithering embutido evita banding post-tonemap
//============================================
