// ReMorganShaded v1.0 - Noise Library
// Funções de noise otimizadas para performance
// Baseado em obras de Inigo Quilez, Morgan McGuire, e Ashima Arts

#ifndef NOISE_GLSL
#define NOISE_GLSL

#include "common.glsl"

// ============================================================================
// HASH FUNCTIONS - Base para todo noise procedural
// ============================================================================

// Hash 2D -> [0,1]
float hash21(vec2 p) {
    // Mais barato que texture fetch de noise
    return fract(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x))));
}

// Hash 3D -> [0,1]
float hash31(vec3 p) {
    return fract(1e4 * sin(17.0 * p.x + p.y * 0.1 + p.z * 0.3) * 
                 (0.1 + abs(sin(p.y * 13.0 + p.x + p.z * 0.5))));
}

// Hash 2D -> vec2 (para gradient noise)
vec2 hash22(vec2 p) {
    float n = sin(dot(p, vec2(41.0, 289.0)));
    return fract(vec2(2.0, 1.0) * n);
}

// Hash 3D -> vec3
vec3 hash33(vec3 p) {
    p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
             dot(p, vec3(269.5, 183.3, 246.1)),
             dot(p, vec3(113.5, 271.9, 124.6)));
    return fract(sin(p) * 43758.5453123);
}

// ============================================================================
// VALUE NOISE - Mais suave que hash puro
// ============================================================================

float valueNoise(vec2 x) {
    vec2 i = floor(x);
    vec2 f = fract(x);
    
    // Quintic curve para C2 continuity (mais suave)
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    
    return mix(mix(hash21(i + vec2(0.0, 0.0)), 
                   hash21(i + vec2(1.0, 0.0)), u.x),
               mix(hash21(i + vec2(0.0, 1.0)), 
                   hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float valueNoise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    
    vec2 u = f.xy * f.xy * (3.0 - 2.0 * f.xy);
    
    return mix(mix(mix(hash31(i + vec3(0.0, 0.0, 0.0)), 
                       hash31(i + vec3(1.0, 0.0, 0.0)), u.x),
                   mix(hash31(i + vec3(0.0, 1.0, 0.0)), 
                       hash31(i + vec3(1.0, 1.0, 0.0)), u.x), u.y),
               mix(mix(hash31(i + vec3(0.0, 0.0, 1.0)), 
                       hash31(i + vec3(1.0, 0.0, 1.0)), u.x),
                   mix(hash31(i + vec3(0.0, 1.0, 1.0)), 
                       hash31(i + vec3(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

// ============================================================================
// GRADIENT NOISE (Perlin-like) - Mais natural para terrenos/nuvens
// ============================================================================

float gradientNoise(vec2 x) {
    vec2 i = floor(x);
    vec2 f = fract(x);
    
    // Quintic interpolation
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    
    // Gradient dots
    float n00 = dot(hash22(i + vec2(0.0, 0.0)) - 0.5, f - vec2(0.0, 0.0));
    float n10 = dot(hash22(i + vec2(1.0, 0.0)) - 0.5, f - vec2(1.0, 0.0));
    float n01 = dot(hash22(i + vec2(0.0, 1.0)) - 0.5, f - vec2(0.0, 1.0));
    float n11 = dot(hash22(i + vec2(1.0, 1.0)) - 0.5, f - vec2(1.0, 1.0));
    
    return mix(mix(n00, n10, u.x), mix(n01, n11, u.x), u.y);
}

// ============================================================================
// SIMPLEX NOISE - Melhor qualidade/performance que Perlin
// Implementação simplificada para 2D
// ============================================================================

vec3 simplexGrad3(vec3 g) {
    return hash33(g) - 0.5;
}

float simplexNoise2D(vec2 v) {
    const mat2 C = mat2(1.0, 0.0, -0.5, 0.866025403784); // sqrt(3)/2
    const mat2 D = mat2(1.0, 0.0, 0.211324865405, 0.366025403784); // (3-sqrt(3))/6, (sqrt(3)-1)/6
    
    // Skew to simplex space
    vec2 i = floor(v + dot(v, C.yy));
    vec2 x0 = v - dot(i, D);
    
    // Determine which simplex we're in
    vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    
    vec2 x1 = x0 - i1 + D.xx;
    vec2 x2 = x0 - 1.0 + D.yy;
    
    vec3 i3 = vec3(i, i + i1, i + 1.0);
    
    // Gradient contributions
    float n0, n1, n2;
    
    vec3 g3 = simplexGrad3(i3);
    
    vec3 x3 = vec3(dot(x0, x0), dot(x1, x1), dot(x2, x2));
    vec3 t3 = max(0.5 - x3, 0.0);
    vec3 t3sq = t3 * t3;
    
    n0 = dot(t3sq * t3sq, vec3(dot(g3.xy, x0), 0.0, 0.0));
    n1 = dot(t3sq * t3sq, vec3(dot(g3.xy, x1), 0.0, 0.0));
    n2 = dot(t3sq * t3sq, vec3(dot(g3.xy, x2), 0.0, 0.0));
    
    return 70.0 * (n0.x + n1.y + n2.z);
}

// ============================================================================
// FBM (Fractal Brownian Motion) - Multi-octave noise
// Otimizado: máximo 3-4 octaves para performance
// ============================================================================

// FBM 2D com rotação para evitar artefatos de grid
float fbm2D(vec2 x, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    // Matriz de rotação para quebrar padrões
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.50));
    
    for (int i = 0; i < 4; i++) {
        if (i >= octaves) break;
        
        value += amplitude * gradientNoise(x * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
        x = rot * x;
    }
    
    return value;
}

// FBM 3D (limitado a 2-3 octaves para performance)
float fbm3D(vec3 x, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < 3; i++) {
        if (i >= octaves) break;
        
        value += amplitude * valueNoise(x * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

// ============================================================================
// RIDGED MULTIFRACTAL - Para montanhas/terrenos mais realistas
// ============================================================================

float ridgedMF(vec2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    float weight = 1.0;
    
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.50));
    
    for (int i = 0; i < 4; i++) {
        if (i >= octaves) break;
        
        float n = gradientNoise(p * frequency);
        n = 1.0 - abs(n); // Ridge
        n = n * n * weight;
        
        value += n * amplitude;
        weight = n * 2.0;
        weight = clamp(weight, 0.0, 1.0);
        
        frequency *= 2.0;
        amplitude *= 0.5;
        p = rot * p;
    }
    
    return value;
}

// ============================================================================
// WORLEY NOISE (Cellular/Voronoi) - Para pedras, nuvens, etc.
// ============================================================================

vec2 worleyNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    
    vec2 result = vec2(1.0);
    vec2 point = vec2(0.0);
    
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 randOffset = hash22(i + neighbor);
            vec2 cellPoint = neighbor + randOffset;
            
            float dist = distanceSq(f, cellPoint);
            
            if (dist < result.x) {
                result.y = result.x;
                result.x = dist;
                point = cellPoint;
            } else if (dist < result.y) {
                result.y = dist;
            }
        }
    }
    
    return result;
}

// ============================================================================
// DOMAIN WARPING - Para efeitos de fumaça/fluidos
// ============================================================================

float domainWarp(vec2 uv, float warpStrength) {
    vec2 q = vec2(
        fbm2D(uv + vec2(0.0, 0.0), 3),
        fbm2D(uv + vec2(5.2, 1.3), 3)
    );
    
    vec2 r = vec2(
        fbm2D(uv + 1.0 * q + vec2(1.7, 9.2), 3),
        fbm2D(uv + 1.0 * q + vec2(8.3, 2.8), 3)
    );
    
    return fbm2D(uv + warpStrength * r, 3);
}

// ============================================================================
// CLOUD NOISE - Especialmente otimizado para nuvens fake
// ============================================================================

float cloudNoise(vec2 uv, float time) {
    // Camada base
    float clouds = fbm2D(uv * 2.0 + vec2(time * 0.02, 0.0), 3);
    
    // Camada de detalhe
    float detail = fbm2D(uv * 4.0 - vec2(time * 0.05, 0.0), 2);
    
    // Combinação
    clouds = clouds * 0.7 + detail * 0.3;
    
    return clouds;
}

// ============================================================================
// WATER NOISE - Ondas e superfície da água
// ============================================================================

float waterNoise(vec2 uv, float time) {
    // Múltiplas escalas de ondas
    float waves = 0.0;
    
    waves += sin(uv.x * 2.0 + time * 0.5) * 0.5;
    waves += sin(uv.y * 3.0 + time * 0.3) * 0.25;
    waves += sin((uv.x + uv.y) * 5.0 + time * 0.7) * 0.125;
    
    // Adicionar algum noise para variação
    waves += fbm2D(uv * 3.0, 2) * 0.125;
    
    return waves * 0.5 + 0.5;
}

#endif // NOISE_GLSL
