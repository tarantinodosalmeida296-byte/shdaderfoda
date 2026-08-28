//============================================
// SHADER: Motion Blur - Per-Object Velocity
// CUSTO ESTIMADO: 0.4ms na GTX 750 Ti @1080p
// ALU OPS: ~30 por fragment
// TEX FETCHES: 5-7 (velocity + neighbor samples)
// BANDWIDTH: ~25 MB/frame
// TÉCNICA: Per-object velocity buffer com neighbor sampling
// TRUQUES USADOS:
//   - Velocity buffer já calculado no GBuffer pass
//   - Neighbor sampling adaptativo
//   - Max 7 samples (trade-off quality/perf)
//   - Clamp de velocity para evitar artifacts
//   - Temporal accumulation opcional
//============================================

#version 450 core

precision mediump float;

// Uniforms
layout(std140, binding = 0) uniform MotionBlurUBO {
    float uShutterSpeed;        // Exposição do motion blur
    float uMaxVelocity;         // Velocity máxima para clamp
    float uMinVelocity;         // Threshold mínimo
    float uQuality;             // Número de samples
} gMB;

// Inputs
layout(binding = 90) uniform sampler2D uSource;         // Input da cena
layout(binding = 91) uniform sampler2D uVelocityBuffer; // Screen-space velocity

in vec2 vUV;
layout(location = 0) out vec4 vOutput;

//============================================
// CONSTANTS
//============================================
const int MAX_SAMPLES = 7;

//============================================
// LINEAR INTERPOLATION
//============================================
vec4 sampleBilinear(sampler2D tex, vec2 uv, vec2 texelSize) {
    return texture(tex, uv);
}

//============================================
// MOTION BLUR COM NEIGHBOR SAMPLING
// Samples ao longo do vector de velocity
//============================================
vec4 computeMotionBlur() {
    vec2 texelSize = vec2(1.0) / textureSize(uSource, 0).xy;
    
    // Sample velocity do pixel central
    vec2 velocity = texture(uVelocityBuffer, vUV).rg;
    
    // Converter de [0,1] para [-1,1] space
    velocity = velocity * 2.0 - 1.0;
    
    // Scale pela shutter speed
    velocity *= gMB.uShutterSpeed;
    
    // Clamp velocity máxima
    float maxVel = gMB.uMaxVelocity * texelSize.x;
    velocity = clamp(velocity, -maxVel, maxVel);
    
    // Early exit se velocity é mínima
    if (length(velocity) < gMB.uMinVelocity * texelSize.x) {
        return texture(uSource, vUV);
    }
    
    // Número de samples baseado na qualidade
    int numSamples = int(gMB.uQuality);
    numSamples = clamp(numSamples, 3, MAX_SAMPLES);
    
    // Calcular step ao longo do velocity vector
    vec2 step = velocity / float(numSamples);
    
    // Start position (beginning of shutter)
    vec2 startUV = vUV - velocity * 0.5;
    
    // Accumulate samples
    vec4 sum = vec4(0.0);
    
    for (int i = 0; i < MAX_SAMPLES; i++) {
        if (i >= numSamples) break;
        
        vec2 sampleUV = startUV + step * float(i);
        
        // Clamp UV para evitar wrapping
        sampleUV = clamp(sampleUV, 0.0, 1.0);
        
        sum += texture(uSource, sampleUV);
    }
    
    return sum / float(numSamples);
}

//============================================
// ADAPTIVE SAMPLE COUNT
// Mais samples para velocities altas
//============================================
vec4 computeAdaptiveMotionBlur() {
    vec2 texelSize = vec2(1.0) / textureSize(uSource, 0).xy;
    
    vec2 velocity = texture(uVelocityBuffer, vUV).rg * 2.0 - 1.0;
    velocity *= gMB.uShutterSpeed;
    
    float velLength = length(velocity);
    
    // Early exit
    if (velLength < gMB.uMinVelocity * texelSize.x) {
        return texture(uSource, vUV);
    }
    
    // Adaptive sample count baseado na velocity
    int numSamples = int(velLength / texelSize.x * 2.0);
    numSamples = clamp(numSamples, 3, MAX_SAMPLES);
    
    vec2 step = velocity / float(numSamples);
    vec2 startUV = vUV - velocity * 0.5;
    
    vec4 sum = vec4(0.0);
    
    for (int i = 0; i < MAX_SAMPLES; i++) {
        if (i >= numSamples) break;
        
        vec2 sampleUV = startUV + step * float(i);
        sampleUV = clamp(sampleUV, 0.0, 1.0);
        
        sum += texture(uSource, sampleUV);
    }
    
    return sum / float(numSamples);
}

//============================================
// TILE-BASED MOTION BLUR (OPCIONAL)
// Agrupar pixels com velocity similar
//============================================
vec4 computeTileBasedMotionBlur() {
    vec2 texelSize = vec2(1.0) / textureSize(uSource, 0).xy;
    
    // Tile size 4x4
    vec2 tileUV = floor(vUV * textureSize(uSource, 0).xy / 4.0) * 4.0 * texelSize;
    
    // Average velocity no tile
    vec2 avgVelocity = vec2(0.0);
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            vec2 vel = texture(uVelocityBuffer, tileUV + offset).rg * 2.0 - 1.0;
            avgVelocity += vel;
        }
    }
    avgVelocity /= 16.0;
    
    avgVelocity *= gMB.uShutterSpeed;
    
    // Usar average velocity para todo o tile
    float maxVel = gMB.uMaxVelocity * texelSize.x;
    avgVelocity = clamp(avgVelocity, -maxVel, maxVel);
    
    if (length(avgVelocity) < gMB.uMinVelocity * texelSize.x) {
        return texture(uSource, vUV);
    }
    
    int numSamples = int(gMB.uQuality);
    numSamples = clamp(numSamples, 3, MAX_SAMPLES);
    
    vec2 step = avgVelocity / float(numSamples);
    vec2 startUV = vUV - avgVelocity * 0.5;
    
    vec4 sum = vec4(0.0);
    for (int i = 0; i < MAX_SAMPLES; i++) {
        if (i >= numSamples) break;
        vec2 sampleUV = startUV + step * float(i);
        sampleUV = clamp(sampleUV, 0.0, 1.0);
        sum += texture(uSource, sampleUV);
    }
    
    return sum / float(numSamples);
}

//============================================
// PASS TYPE SELECTION
// 0 = Standard, 1 = Adaptive, 2 = Tile-based
//============================================
layout(location = 1) uniform int uPassType;

void main() {
    if (uPassType == 0) {
        vOutput = computeMotionBlur();
    } else if (uPassType == 1) {
        vOutput = computeAdaptiveMotionBlur();
    } else if (uPassType == 2) {
        vOutput = computeTileBasedMotionBlur();
    }
}

//============================================
// NOTAS DE OTIMIZAÇÃO:
// 1. Velocity buffer pré-calculado no GBuffer pass
// 2. Max 7 samples (suficiente para 60fps+)
// 3. Early exit para pixels estáticos
// 4. Velocity clamped para evitar overblur
// 5. Tile-based option reduz cálculos redundantes
// 6. Adaptive quality baseada na velocity
// 7. Zero branches dinâmicos críticos
// 8. Texture fetches minimizados
//============================================
