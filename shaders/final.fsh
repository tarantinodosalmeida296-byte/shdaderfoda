// ReMorganShaded v1.0 - Final Fragment Shader
// Output final com efeitos de tela cheia
// Vinheta + Film Grain + Dithering Bayer

#version 120

#define FINAL_FRAGMENT

#include "lib/common.glsl"
#include "lib/post.glsl"

varying vec2 texCoord;

uniform sampler2D colortex0; // Output do composite2
uniform sampler2D gbufferDepth;

void main() {
    // Cor do passe anterior
    vec3 color = texture2D(colortex0, texCoord).rgb;
    
    // Vinheta sutil
    #ifdef VIGNETTE_ENABLED
    float vignetteStrength = 0.3;
    float vignetteRoundness = 1.5;
    color = applyVignette(color, texCoord, vignetteStrength, vignetteRoundness);
    #endif
    
    // Lens flare do sol (opcional)
    #ifdef LENS_FLARE_ENABLED
    vec2 sunPos = (sunPosition.xy / abs(sunPosition.z)) * 0.5 + 0.5;
    vec3 sunFlare = lensFlare(texCoord, sunPos, SUN_COLOR, 0.1);
    color += sunFlare;
    #endif
    
    // Sharpening leve (unsharp mask)
    #ifdef SHARPEN_ENABLED
    color = sharpen(colortex0, texCoord, 0.3);
    #endif
    
    // Film grain procedural sutil
    #ifdef FILM_GRAIN_ENABLED
    float grainIntensity = 0.04;
    color = applyColorFilmGrain(color, texCoord, grainIntensity);
    #endif
    
    // Dithering Bayer para reduzir color banding
    // Essencial para qualidade em 8-bit per channel
    color = applyTemporalDithering(color, gl_FragCoord.xy, frameCounter);
    
    // Clamp final para evitar valores fora do range
    color = clamp(color, 0.0, 1.0);
    
    // Gamma correction final (se necessário)
    // color = toGamma(color);
    
    gl_FragData[0] = vec4(color, 1.0);
}
