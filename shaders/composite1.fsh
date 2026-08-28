// ReMorganShaded v1.0 - Composite1 Fragment Shader (Pass 2)
// Screen Space Reflections + Bloom Downscale
// Otimizado: SSR limitado, bloom eficiente

#version 120

#define COMPOSITE1_FRAGMENT

#include "lib/common.glsl"
#include "lib/water.glsl"
#include "lib/post.glsl"

varying vec2 texCoord;
varying vec2 halfResTexCoord;
varying vec2 quarterResTexCoord;

uniform sampler2D colortex0; // Output do composite
uniform sampler2D gbufferDepth;
uniform sampler2D gbufferNormal;
uniform sampler2D gbufferColor;

void main() {
    // Cor do passe anterior
    vec3 color = texture2D(colortex0, texCoord).rgb;
    
    // Depth e normal
    float depth = texture2D(gbufferDepth, texCoord).r;
    vec3 normal = texture2D(gbufferNormal, texCoord).rgb * 2.0 - 1.0;
    
    // View direction
    vec3 viewDir = normalize(vec3(
        (texCoord.x - 0.5) * aspectRatio,
        (texCoord.y - 0.5),
        -1.0
    ));
    
    // Screen Space Reflections (SSR) simplificado
    #if SSR_STEPS > 0
    if (dot(viewDir, normal) < -0.1) {
        // Só refletir se olhando para superfície
        vec3 reflectDir = reflect(viewDir, normal);
        
        // Ray march na tela
        vec2 screenStep = normalize(reflectDir.xy / abs(reflectDir.z)) * 0.02;
        vec2 currentUV = texCoord;
        
        vec3 reflection = vec3(0.0);
        float hitWeight = 0.0;
        
        for (int i = 0; i < SSR_STEPS; i++) {
            currentUV += screenStep;
            
            // Check bounds
            if (currentUV.x < 0.0 || currentUV.x > 1.0 ||
                currentUV.y < 0.0 || currentUV.y > 1.0) {
                break;
            }
            
            float sampleDepth = texture2D(gbufferDepth, currentUV).r;
            
            // Hit detection simplificado
            if (sampleDepth < depth) {
                reflection = texture2D(gbufferColor, currentUV).rgb;
                hitWeight = 1.0;
                break;
            }
        }
        
        // Fresnel para mistura
        float fresnel = pow(1.0 - max(dot(-viewDir, normal), 0.0), 5.0);
        color = mix(color, reflection, fresnel * hitWeight * 0.5);
    }
    #endif
    
    // Bloom downscale - extrair áreas brilhantes
    float brightness = dot(color, vec3(0.299, 0.587, 0.114));
    float threshold = 1.2;
    
    vec3 brightPixels = extractBright(color, threshold);
    
    // Downscale para bloom pyramid (quarter resolution)
    vec3 bloomDownscaled = brightPixels * 0.25;
    
    gl_FragData[0] = vec4(color, 1.0);
    gl_FragData[1] = vec4(bloomDownscaled, 1.0); // Bloom buffer
}
