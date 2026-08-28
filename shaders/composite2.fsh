// ReMorganShaded v1.0 - Composite2 Fragment Shader (Pass 3)
// Bloom upscale + Tone Mapping ACES + Color Grading + TAA
// Otimizado: blur separável, LUT simples

#version 120

#define COMPOSITE2_FRAGMENT

#include "lib/common.glsl"
#include "lib/post.glsl"

varying vec2 texCoord;
varying vec2 halfResTexCoord;

uniform sampler2D colortex0; // Output do composite1
uniform sampler2D colortex1; // Bloom buffer
uniform sampler2D gbufferDepth;

void main() {
    // Cor principal
    vec3 color = texture2D(colortex0, texCoord).rgb;
    
    // Bloom - upscale com blur
    vec3 bloom = texture2D(colortex1, halfResTexCoord).rgb;
    
    // Blur gaussiano separável no bloom (horizontal + vertical)
    float texelSize = 1.0 / (viewWidth * 0.5);
    
    #ifdef BLOOM_QUALITY_HIGH
        bloom = blurHorizontal(colortex1, halfResTexCoord, texelSize);
        bloom = blurVertical(colortex1, halfResTexCoord, texelSize);
    #else
        bloom = blurHorizontalLow(colortex1, halfResTexCoord, texelSize);
        bloom = blurVerticalLow(colortex1, halfResTexCoord, texelSize);
    #endif
    
    // Adicionar bloom à cor principal
    color += bloom * BLOOM_STRENGTH;
    
    // Tone Mapping ACES Filmic
    color = ACESFilmic(color);
    
    // Color grading manual (pode ser substituído por LUT 3D)
    // Ajustes sutis para look cinematográfico
    vec3 lift = vec3(0.02);     // Sombras
    vec3 gain = vec3(1.05);     // Altas luzes
    vec3 gamma = vec3(1.0);     // Midtones
    
    color = manualColorGrade(color, gain, lift, gamma);
    
    // Saturação leve
    color = adjustSaturation(color, 1.1);
    
    // TAA (Temporal Anti-Aliasing) com 2 frames de história
    #ifdef TAA_ENABLED
    vec2 motionVector = vec2(0.0); // Calcular baseado em camera motion
    float motionFactor = length(motionVector);
    
    // Neighborhood clipping para evitar ghosting
    vec3 historyColor = texture2DLod(colortex0, texCoord - motionVector, 0.0).rgb;
    color = neighborhoodClipping(color, historyColor, colortex0, texCoord);
    
    // Blend temporal
    color = taablend(color, historyColor, motionFactor);
    #endif
    
    gl_FragData[0] = vec4(color, 1.0);
}
