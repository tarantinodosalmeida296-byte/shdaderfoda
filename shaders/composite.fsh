// ReMorganShaded v1.0 - Composite Fragment Shader (Pass 1)
// SSAO ultraleve + Fog atmosférico
// Otimizado: meia resolução, poucos samples

#version 120

#define COMPOSITE_FRAGMENT

#include "lib/common.glsl"
#include "lib/noise.glsl"
#include "lib/atmosphere.glsl"

varying vec2 texCoord;
varying vec2 halfResTexCoord;

uniform sampler2D gbufferColor;
uniform sampler2D gbufferDepth;
uniform sampler2D gbufferNormal;
uniform sampler2D colortex0; // Buffer anterior

// SSAO com 4 samples em padrão rotativo
float calculateSSAO(vec2 uv, float depth, vec3 normal) {
    #ifdef SSAO_QUALITY_OFF
        return 1.0;
    #endif
    
    float ao = 0.0;
    const float radius = 0.002;
    const float bias = 0.01;
    
    // Pattern rotativo baseado no frame para temporal accumulation
    float angle = float(frameCounter % 8) * 0.785398; // 45 degrees
    mat2 rotation = mat2(cos(angle), sin(angle), -sin(angle), cos(angle));
    
    // Samples em padrão de rotação
    vec2 samples[4] = vec2[](
        vec2(1.0, 0.0),
        vec2(-0.5, 0.866),
        vec2(-0.5, -0.866),
        vec2(0.0, 1.0)
    );
    
    for (int i = 0; i < 4; i++) {
        vec2 offset = rotation * samples[i] * radius;
        float sampleDepth = texture2D(gbufferDepth, uv + offset).r;
        
        // Depth difference
        float diff = (sampleDepth - depth) * 1000.0;
        
        // AO contribution
        float occ = smoothstep(0.0, 1.0, diff - bias);
        ao += occ;
    }
    
    ao /= 4.0;
    
    return 1.0 - ao;
}

void main() {
    // Cores e dados dos G-buffers
    vec3 color = texture2D(gbufferColor, texCoord).rgb;
    float depth = texture2D(gbufferDepth, texCoord).r;
    vec3 normal = texture2D(gbufferNormal, texCoord).rgb * 2.0 - 1.0;
    
    // SSAO (meia resolução para performance)
    float ssao = calculateSSAO(texCoord, depth, normal);
    
    // Aplicar SSAO à cor
    color *= ssao;
    
    // Fog atmosférico baseado na depth
    float viewZ = -linearizeDepth(depth, near, far);
    
    // Height fog
    vec3 worldPos = (gbufferModelViewInverse * vec4(0.0, 0.0, -viewZ, 1.0)).xyz;
    color = heightFog(color, normalize(worldPos), abs(viewZ), worldPos.y);
    
    // Exponential fog básico
    float fogDensity = 0.0003;
    float fogFactor = 1.0 - exp(-abs(viewZ) * fogDensity);
    fogFactor = clamp(fogFactor, 0.0, 1.0);
    
    color = mix(color, fogColor, fogFactor * 0.5);
    
    gl_FragData[0] = vec4(color, 1.0);
}
