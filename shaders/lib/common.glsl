// ReMorganShaded v1.0 - Common Library
// Funções e constantes compartilhadas entre todos os shaders
// Otimizado para GTX 750 Ti - Maxwell GM107

#ifndef COMMON_GLSL
#define COMMON_GLSL

// ============================================================================
// CONSTANTES GLOBAIS - Ajustáveis para performance
// ============================================================================

#define VERSION_MAJOR 1
#define VERSION_MINOR 0
#define SHADER_NAME "ReMorganShaded"

// Qualidade configurável via defines do OptiFine
#ifdef SSAO_QUALITY_HIGH
    #define SSAO_SAMPLES 6
    #define SSAO_HALF_RES
#else
    #ifdef SSAO_QUALITY_MEDIUM
        #define SSAO_SAMPLES 4
        #define SSAO_HALF_RES
    #else
        #define SSAO_SAMPLES 3
    #endif
#endif

#ifdef REFLECTION_QUALITY_MEDIUM
    #define SSR_STEPS 8
    #define SSR_HALF_RES
#else
    #ifdef REFLECTION_QUALITY_LOW
        #define SSR_STEPS 4
        #define SSR_HALF_RES
    #else
        #define SSR_STEPS 0
    #endif
#endif

// Shadow quality
#ifdef SHADOW_RES_2048
    #define SHADOW_MAP_RESOLUTION 2048.0
#else
    #define SHADOW_MAP_RESOLUTION 1024.0
#endif

#ifdef SHADOW_DIST_8
    #define SHADOW_DISTANCE 8.0
#else
    #ifdef SHADOW_DIST_6
        #define SHADOW_DISTANCE 6.0
    #else
        #ifdef SHADOW_DIST_5
            #define SHADOW_DISTANCE 5.0
        #else
            #define SHADOW_DISTANCE 4.0
        #endif
    #endif
#endif

// Bloom strength
#ifndef BLOOM_STRENGTH
    #define BLOOM_STRENGTH 1.0
#endif

// ============================================================================
// PRECISION - Usar mediump sempre que possível (GTX 750 Ti tem FP32 limitado)
// ============================================================================

#ifdef GL_ES
    precision mediump float;
    precision mediump int;
#else
    #define mediump
    #define highp
#endif

// ============================================================================
// CONSTANTS MATEMÁTICAS
// ============================================================================

const float PI = 3.14159265359;
const float PI2 = 6.28318530718;
const float INV_PI = 0.31830988618;
const float INV_PI2 = 0.15915494309;
const float SQRT2 = 1.41421356237;
const float EPSILON = 1e-6;

// ============================================================================
// UNIFORMS COMUNS
// ============================================================================

uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform float rainStrength;
uniform float wetness;
uniform vec3 skyColor;
uniform vec3 fogColor;
uniform vec3 cameraPosition;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjectionInverse;

// Sun/Moon direction
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform vec3 eyePosition;

// Fog
uniform float far;
uniform float near;
uniform float fogStart;
uniform float fogEnd;

// ============================================================================
// FUNÇÕES UTILITÁRIAS OTIMIZADAS
// ============================================================================

// Fast hash function - evita textura de noise
float hash(vec2 p) {
    // Hash baseado em obra de Inigo Quilez
    // Mais barato que texture fetch
    return fract(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x))));
}

float hash(vec3 p) {
    return fract(1e4 * sin(17.0 * p.x + p.y * 0.1 + p.z * 0.3) * (0.1 + abs(sin(p.y * 13.0 + p.x))));
}

// Noise 2D otimizado - menos operações que value noise tradicional
float noise(vec2 x) {
    vec2 i = floor(x);
    vec2 f = fract(x);
    
    // Cubic interpolation mais suave que linear
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    return mix(mix(hash(i + vec2(0.0, 0.0)), 
                   hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), 
                   hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// FBm (Fractal Brownian Motion) com 3 octaves apenas (performance!)
float fbm(vec2 x) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    // Rotação para evitar artefatos de grid
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    
    for (int i = 0; i < 3; ++i) {
        v += a * noise(x);
        x = rot * x * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// Fast distance squared - evita sqrt caro
float distanceSq(vec2 a, vec2 b) {
    vec2 d = b - a;
    return dot(d, d);
}

float distanceSq(vec3 a, vec3 b) {
    vec3 d = b - a;
    return dot(d, d);
}

// Clamp otimizado usando min/max (evita branching)
float saturate(float x) {
    return clamp(x, 0.0, 1.0);
}

vec2 saturate(vec2 x) {
    return clamp(x, 0.0, 1.0);
}

vec3 saturate(vec3 x) {
    return clamp(x, 0.0, 1.0);
}

// Fast normalize com prevenção de div por zero
vec3 safeNormalize(vec3 v) {
    float len = length(v);
    return len > EPSILON ? v / len : vec3(0.0);
}

// Schlick Fresnel approximation - MUITO mais barato que cálculo completo
float fresnelSchlick(float cosTheta, float F0) {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

vec3 fresnelSchlickVec(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Gamma correction rápida
vec3 toLinear(vec3 sRGB) {
    return pow(sRGB, vec3(2.2));
}

vec3 toGamma(vec3 linear) {
    return pow(linear, vec3(1.0/2.2));
}

// ACES Filmic Tone Mapping - padrão da indústria, custo razoável
vec3 ACESFilmic(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Reinhard tone mapping - alternativa mais barata
vec3 Reinhard(vec3 x) {
    return x / (1.0 + x);
}

// ============================================================================
// VOGEL DISK PARA PCF SHADOWS
// Distribuição ótima para sampleamento de sombras
// ============================================================================

const int VOGEL_SAMPLES = 6;
const float VogelSamples[VOGEL_SAMPLES] = float[](
    0.0, 1.0, 2.0, 3.0, 4.0, 5.0
);

vec2 getVogelDiskSample(int index, float radius, vec2 dir) {
    // Golden angle para distribuição uniforme
    const float goldenAngle = 2.39996322973;
    
    float theta = float(index) * goldenAngle;
    float r = sqrt(float(index) + 0.5) / sqrt(float(VOGEL_SAMPLES));
    
    return radius * r * vec2(cos(theta), sin(theta));
}

// ============================================================================
// BAYER DITHERING 8x8 - Combater color banding sem custo significativo
// ============================================================================

const float BayerMatrix8x8[64] = float[](
     0.0,  32.0,   8.0,  40.0,   2.0,  34.0,  10.0,  42.0,
    48.0,  16.0,  56.0,  24.0,  50.0,  18.0,  58.0,  26.0,
    12.0,  44.0,   4.0,  36.0,  14.0,  46.0,   6.0,  38.0,
    60.0,  28.0,  52.0,  20.0,  62.0,  30.0,  54.0,  22.0,
     3.0,  35.0,  11.0,  43.0,   1.0,  33.0,   9.0,  41.0,
    51.0,  19.0,  59.0,  27.0,  49.0,  17.0,  57.0,  25.0,
    15.0,  47.0,   7.0,  39.0,  13.0,  45.0,   5.0,  37.0,
    63.0,  31.0,  55.0,  23.0,  61.0,  29.0,  53.0,  21.0
);

float getBayerFactor(vec2 fragCoord) {
    ivec2 pos = ivec2(fragCoord) & 7;
    return BayerMatrix8x8[pos.y * 8 + pos.x] / 64.0;
}

// Aplica dithering ao fragmento final
vec3 applyDithering(vec3 color, vec2 fragCoord) {
    float dither = getBayerFactor(fragCoord);
    return color + (dither - 0.5) * (1.0 / 255.0);
}

// ============================================================================
// OCTAHEDRAL NORMAL ENCODING - Pack normals em 2 canais
// Economiza bandwidth de textura significativamente
// ============================================================================

vec2 encodeNormalOct(vec3 n) {
    // Octahedral encoding
    vec3 absN = abs(n);
    float m = dot(absN, vec3(1.0));
    vec2 enc = n.xy / (m - n.z);
    
    if (n.z < 0.0) {
        enc.x = (1.0 - abs(enc.y)) * sign(enc.x);
        enc.y = (1.0 - abs(enc.x)) * sign(enc.y);
    }
    
    return enc * 0.5 + 0.5;
}

vec3 decodeNormalOct(vec2 enc) {
    enc = enc * 2.0 - 1.0;
    
    vec3 n = vec3(enc.x, enc.y, 1.0 - abs(enc.x) - abs(enc.y));
    
    if (n.z < 0.0) {
        n.x = (1.0 - abs(n.y)) * sign(n.x);
        n.y = (1.0 - abs(n.x)) * sign(n.y);
    }
    
    return normalize(n);
}

// ============================================================================
// LINEARIZE DEPTH - Converter depth buffer para world space depth
// ============================================================================

float linearizeDepth(float depth, float near, float far) {
    return (2.0 * near * far) / (far + near - (2.0 * depth - 1.0) * (far - near));
}

float getViewZ(float depth, float near, float far) {
    // Converte depth [0,1] para Z view space
    return -(near * far) / ((far - near) * depth - far);
}

// ============================================================================
// UV COORDINATES HELPERS
// ============================================================================

vec2 getScreenUV() {
    return gl_FragCoord.xy / vec2(viewWidth, viewHeight);
}

vec2 getHalfResUV() {
    return gl_FragCoord.xy / vec2(viewWidth * 0.5, viewHeight * 0.5);
}

vec2 getQuarterResUV() {
    return gl_FragCoord.xy / vec2(viewWidth * 0.25, viewHeight * 0.25);
}

// ============================================================================
// CHECKERBOARD PATTERN - Para temporal reprojection
// ============================================================================

bool isCheckerboardFrame() {
    return (frameCounter & 1) == 0;
}

bool isCurrentPixelActive() {
    ivec2 coord = ivec2(gl_FragCoord.xy);
    return ((coord.x + coord.y) & 1) == (frameCounter & 1);
}

#endif // COMMON_GLSL
