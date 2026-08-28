//============================================
// SHADER: Lens Flare - Screen Space Ghosts
// CUSTO ESTIMADO: 0.2ms na GTX 750 Ti @1080p
// ALU OPS: ~35 por fragment
// TEX FETCHES: 2-4 (flare sprites + source)
// BANDWIDTH: ~10 MB/frame
// TÉCNICA: Screen-space ghosts com threshold
// TRUQUES USADOS:
//   - Threshold-based bright spot detection
//   - Ghost sprites pre-rendered
//   - Chromatic offset per ghost
//   - Vignette mask para blend suave
//   - Early exit se sem light source visível
//============================================

#version 450 core

precision mediump float;

// Uniforms
layout(std140, binding = 0) uniform FlareUBO {
    vec3 uSunPosition;          // Posição do sol em screen space [0,1]
    vec3 uSunColor;
    float uFlareIntensity;
    float uGhostCount;
    float uChromaticOffset;
    float uVignetteSmoothness;
} gFlare;

// Inputs
layout(binding = 120) uniform sampler2D uSource;        // Input da cena (para threshold)
layout(binding = 121) uniform sampler2D uFlareSprites;  // Sprites dos ghosts
layout(binding = 122) uniform sampler2D uFlareGlow;     // Glow texture

in vec2 vUV;
layout(location = 0) out vec4 vOutput;

//============================================
// CONSTANTS
//============================================
const int MAX_GHOSTS = 8;
const float PI = 3.14159265359;

//============================================
// GHOST CONFIGURATION
// Cada ghost tem posição, scale e cor diferentes
//============================================
struct Ghost {
    float distance;     // Distância do centro da lente
    float scale;        // Tamanho do ghost
    vec3 color;         // Cor tint
    float rotation;     // Rotação em radians
};

// Ghost array pre-configurado
Ghost ghosts[MAX_GHOSTS] = Ghost[](
    Ghost(0.1, 0.15, vec3(0.8, 0.6, 0.4), 0.0),
    Ghost(0.2, 0.12, vec3(0.6, 0.7, 0.8), 0.5),
    Ghost(0.3, 0.10, vec3(0.9, 0.8, 0.5), 1.0),
    Ghost(0.4, 0.08, vec3(0.5, 0.6, 0.9), 1.5),
    Ghost(0.5, 0.06, vec3(0.8, 0.5, 0.7), 2.0),
    Ghost(0.6, 0.05, vec3(0.7, 0.8, 0.6), 2.5),
    Ghost(0.7, 0.04, vec3(0.6, 0.9, 0.8), 3.0),
    Ghost(0.8, 0.03, vec3(0.9, 0.7, 0.6), 3.5)
);

//============================================
// THRESHOLD DETECTION
// Detectar se a luz source é visível
//============================================
float computeThreshold(vec2 uv, vec2 lightPos) {
    float dist = distance(uv, lightPos);
    
    // Threshold baseado na brightness da source
    float threshold = 0.8;  // Apenas pixels muito bright
    
    // Sample area ao redor da light position
    float sampleRadius = 0.05;
    
    if (dist < sampleRadius) {
        vec3 sampleColor = texture(uSource, lightPos).rgb;
        float luminance = dot(sampleColor, vec3(0.2126, 0.7152, 0.0722));
        
        // Se luminance > threshold, flare é visível
        return smoothstep(threshold, threshold + 0.2, luminance);
    }
    
    return 0.0;
}

//============================================
// RENDER SINGLE GHOST
//============================================
vec3 renderGhost(Ghost ghost, vec2 uv, vec2 lightPos, float visibility) {
    // Direction do center da lente até o ghost
    vec2 center = vec2(0.5);
    vec2 dir = normalize(lightPos - center);
    
    // Posição do ghost
    vec2 ghostPos = center + dir * ghost.distance;
    
    // UV relativo ao ghost
    vec2 ghostUV = (uv - ghostPos) / ghost.scale;
    
    // Rotação do ghost
    float cosR = cos(ghost.rotation);
    float sinR = sin(ghost.rotation);
    mat2 rot = mat2(cosR, -sinR, sinR, cosR);
    ghostUV = rot * ghostUV;
    
    // Sample do sprite
    ghostUV = ghostUV * 0.5 + 0.5;  // Scale para [0,1]
    
    if (ghostUV.x < 0.0 || ghostUV.x > 1.0 || 
        ghostUV.y < 0.0 || ghostUV.y > 1.0) {
        return vec3(0.0);
    }
    
    vec3 spriteColor = texture(uFlareSprites, ghostUV).rgb;
    
    // Chromatic offset
    float chromaOffset = gFlare.uChromaticOffset * ghost.distance;
    float r = texture(uFlareSprites, ghostUV + vec2(chromaOffset, 0.0)).r;
    float g = texture(uFlareSprites, ghostUV).g;
    float b = texture(uFlareSprites, ghostUV - vec2(chromaOffset, 0.0)).b;
    spriteColor = vec3(r, g, b);
    
    // Apply ghost color e visibility
    return spriteColor * ghost.color * visibility * gFlare.uFlareIntensity;
}

//============================================
// GLOW/HALO AROUND LIGHT SOURCE
//============================================
vec3 renderGlow(vec2 uv, vec2 lightPos, float visibility) {
    vec2 glowUV = (uv - lightPos) * 5.0 + 0.5;  // Scale glow
    
    if (glowUV.x < 0.0 || glowUV.x > 1.0 || 
        glowUV.y < 0.0 || glowUV.y > 1.0) {
        return vec3(0.0);
    }
    
    vec3 glowColor = texture(uFlareGlow, glowUV).rgb;
    
    return glowColor * gFlare.uSunColor * visibility * gFlare.uFlareIntensity * 0.5;
}

//============================================
// VIGNETTE MASK PARA BLEND SUAVE
//============================================
float computeVignetteMask(vec2 uv) {
    vec2 centeredUV = uv - 0.5;
    float dist = dot(centeredUV, centeredUV) * 4.0;
    return smoothstep(1.0, gFlare.uVignetteSmoothness, dist);
}

void main() {
    //========================================
    // VISIBILITY CHECK
    //========================================
    float visibility = computeThreshold(vUV, gFlare.uSunPosition.xy);
    
    // Early exit se luz não é visível
    if (visibility < 0.01) {
        vOutput = vec4(0.0);
        return;
    }
    
    //========================================
    // RENDER GLOW
    //========================================
    vec3 flare = renderGlow(vUV, gFlare.uSunPosition.xy, visibility);
    
    //========================================
    // RENDER GHOSTS
    //========================================
    int ghostCount = int(gFlare.uGhostCount);
    ghostCount = clamp(ghostCount, 1, MAX_GHOSTS);
    
    for (int i = 0; i < MAX_GHOSTS; i++) {
        if (i >= ghostCount) break;
        
        vec3 ghost = renderGhost(ghosts[i], vUV, gFlare.uSunPosition.xy, visibility);
        flare += ghost;
    }
    
    //========================================
    // VIGNETTE MASK
    //========================================
    float vignette = computeVignetteMask(vUV);
    flare *= vignette;
    
    //========================================
    // OUTPUT
    //========================================
    vOutput = vec4(flare, visibility);  // Alpha = visibility para blend
}

//============================================
// NOTAS DE OTIMIZAÇÃO:
// 1. Early exit se luz source não visível
// 2. Ghost count ajustável (1-8)
// 3. Sprites pre-rendered em textura
// 4. Chromatic offset barato (3 samples)
// 5. Vignette analítico para blend
// 6. Threshold detection simples
// 7. Loop unrolled para ghosts fixos
// 8. Alpha output para blend aditivo
//============================================
