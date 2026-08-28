// ReMorganShaded v1.0 - G-Buffer Sky Basic Fragment Shader
// Renderiza céu procedural com modelo simplificado
// Nuvens fake, estrelas, transição dia/noite

#version 120

#define GBUFFERS_SKYBASIC_FRAGMENT

#include "lib/common.glsl"
#include "lib/atmosphere.glsl"
#include "lib/noise.glsl"

varying vec3 viewDir;
varying float sunFactor;

uniform sampler2D gbufferDepth;

void main() {
    // Calcular cor do céu baseada na direção de vista
    vec3 skyColor = getSkyColor(viewDir, sunFactor, frameTimeCounter);
    
    // Nuvens fake (volumétricas baratas)
    #ifdef ENABLE_CLOUDS
    float cloudCoverage = fakeVolumetricClouds(viewDir, frameTimeCounter);
    
    if (cloudCoverage > 0.1) {
        vec3 cloudColor = renderFakeClouds(viewDir, normalize(sunPosition), frameTimeCounter);
        skyColor = mix(skyColor, cloudColor, cloudCoverage * 0.8);
    }
    #endif
    
    // Halo do sol/lua
    vec3 sunHaloColor = sunHalo(viewDir, sunPosition, SUN_COLOR);
    skyColor += sunHaloColor;
    
    // Fog atmosférico no horizonte
    float heightFactor = max(viewDir.y, 0.0);
    vec3 horizonFog = SKY_HORIZON_COLOR * (1.0 - heightFactor) * 0.3;
    skyColor += horizonFog;
    
    gl_FragData[0] = vec4(skyColor, 1.0);
}
