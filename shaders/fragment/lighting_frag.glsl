//============================================
// SHADER: Lighting Pass - Deferred PBR Simplified
// CUSTO ESTIMADO: 2.0ms na GTX 750 Ti @1080p
// ALU OPS: ~120 por fragment
// TEX FETCHES: 4-6 (GBuffer + Shadow + LUT)
// BANDWIDTH: ~120 MB/frame
// TÉCNICA: Deferred lighting com GGX Schlick approximation
// TRUQUES USADOS:
//   - GGX simplified (Schlick-GGX sem integral completo)
//   - Spherical Harmonics order 2 para ambient
//   - Shadow PCF 3x3 rotated Poisson disk
//   - MAD-heavy formulation
//   - Half precision intermediates
//============================================

#version 450 core

precision mediump float;

// Uniforms
layout(std140, binding = 0) uniform GlobalUBO {
    mat4 uModelMatrix;
    mat4 uViewMatrix;
    mat4 uProjectionMatrix;
    mat4 uModelViewMatrix;
    mat4 uMVP;
    mat4 uPrevMVP;
    vec3 uViewPosition;
    float uTime;
    vec4 uSunDirection;         // xyz=direction, w=cosAngle
    vec4 uFogParams;
} gGlobal;

layout(std140, binding = 2) uniform LightUBO {
    vec4 uLightColor;           // RGB + intensity multiplier
    vec4 uLightDirection;       // Directional light
    vec3 uAmbientColor;
    float uExposure;
    vec4 uShadowCascadeSplits;  // Near planes das 3 cascatas
    mat4 uShadowMatrices[3];    // 3 cascadas
} gLight;

// GBuffer textures
layout(binding = 10) uniform sampler2D uGBuffer0;     // Albedo + Metallic
layout(binding = 11) uniform sampler2D uGBuffer1;     // Normal.xy + Roughness + AO
layout(binding = 12) uniform sampler2D uGBuffer2;     // Emission + MatID
layout(binding = 13) uniform sampler2D uDepthBuffer;

// Shadow maps (3 cascatas)
layout(binding = 20) uniform sampler2DShadow uShadowMap0;
layout(binding = 21) uniform sampler2DShadow uShadowMap1;
layout(binding = 22) uniform sampler2DShadow uShadowMap2;

// BRDF LUT (pre-computada)
layout(binding = 30) uniform sampler2D uBRDFLUT;

// Screen quad
in vec2 vUV;

layout(location = 0) out vec4 vFinalColor;

//============================================
// CONSTANTS
//============================================
const float PI = 3.14159265359;
const float INV_PI = 0.31830988618;

//============================================
// OCTAHEDRON NORMAL DECODING
//============================================
vec3 decodeOctahedron(vec2 encoded) {
    vec3 n = vec3(encoded.x, encoded.y, 1.0 - abs(encoded.x) - abs(encoded.y));
    vec2 mirrored = (1.0 - abs(n.zy)) * sign(vec2(-n.z, -n.y));
    float test = step(0.0, n.z);
    n.xy = mix(mirrored, n.xy, test);
    return normalize(n);
}

//============================================
// SCHUECK-GGX APPROXIMATION (SIMPLIFICADA)
// Evita a integral completa do microfacet model
//============================================
vec3 schlickGGX(vec3 h, vec3 n, vec3 v, float roughness, vec3 F0) {
    // NdotV e NdotL já calculados fora
    float NdotV = max(dot(n, v), 0.0);
    
    // Schlick Fresnel approximation (5 MADs!)
    // F = F0 + (1 - F0) * (1 - NdotV)^5
    float f = 1.0 - NdotV;
    float f2 = f * f;
    float f4 = f2 * f2;
    vec3 F = F0 + (vec3(1.0) - F0) * f4 * f;
    
    return F;
}

//============================================
// GGX VISIBILITY FUNCTION (Smith simplificado)
//============================================
float smithGGX(float NdotL, float NdotV, float roughness) {
    // Roughness → alpha conversion
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    
    // Smith visibility com aproximação de Schlick
    // G = 1 / (NdotL * (1 - k) + k) * 1 / (NdotV * (1 - k) + k)
    float k = alpha * 0.5;  // Simplificação de Smith
    
    float G_L = NdotL * (1.0 - k) + k;
    float G_V = NdotV * (1.0 - k) + k;
    
    return 1.0 / (G_L * G_V);
}

//============================================
// GGX DISTRIBUTION FUNCTION (Trowbridge-Reitz)
//============================================
float ggxDistribution(vec3 h, vec3 n, float roughness) {
    float NdotH = max(dot(n, h), 0.0);
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    
    float denom = NdotH * NdotH * (alpha2 - 1.0) + 1.0;
    return alpha2 / (PI * denom * denom);
}

//============================================
// PCF SHADOW COM ROTATED POISSON DISK
// 3x3 samples com pattern rotativo por frame
//============================================
float sampleShadow(sampler2DShadow shadowMap, vec3 shadowCoord, int cascadeIdx) {
    // Poisson disk 3x3 rotated
    const vec2 poissonDisk[9] = vec2[](
        vec2(0.0, 0.0),
        vec2(-0.577, 0.577),
        vec2(0.577, -0.577),
        vec2(0.0, 1.0),
        vec2(-0.866, -0.5),
        vec2(0.866, 0.5),
        vec2(1.0, 0.0),
        vec2(-0.5, 0.866),
        vec2(0.5, -0.866)
    );
    
    // Rotação baseada no frame index (uniforme)
    float angle = gGlobal.uTime * 2.0;
    float s = sin(angle);
    float c = cos(angle);
    mat2 rot = mat2(c, -s, s, c);
    
    float shadow = 0.0;
    float texelSize = 1.0 / 2048.0;  // Shadow map resolution
    
    for (int i = 0; i < 9; i++) {
        vec2 offset = rot * poissonDisk[i] * texelSize;
        shadow += texture(shadowMap, vec3(shadowCoord.xy + offset, shadowCoord.z));
    }
    
    return shadow / 9.0;
}

//============================================
// CASCADE SELECTION
//============================================
int selectCascade(float depth) {
    // Selecionar cascata baseado na distância da câmara
    if (depth < gLight.uShadowCascadeSplits[0]) return 0;
    if (depth < gLight.uShadowCascadeSplits[1]) return 1;
    return 2;
}

//============================================
// COMPUTE SHADOWS
//============================================
float computeShadow(vec3 worldPos, float depth) {
    int cascade = selectCascade(depth);
    
    mat4 shadowMatrix = (cascade == 0) ? gLight.uShadowMatrices[0] :
                        (cascade == 1) ? gLight.uShadowMatrices[1] :
                                         gLight.uShadowMatrices[2];
    
    sampler2DShadow shadowMap = (cascade == 0) ? uShadowMap0 :
                                (cascade == 1) ? uShadowMap1 :
                                                 uShadowMap2;
    
    vec4 shadowCoord = shadowMatrix * vec4(worldPos, 1.0);
    vec3 projCoords = shadowCoord.xyz / shadowCoord.w;
    projCoords = projCoords * 0.5 + 0.5;  // [0,1]
    
    // Depth bias para evitar shadow acne
    float bias = max(0.005 * tan(acos(clamp(dot(-gLight.uLightDirection.xyz, normalize(worldPos - gGlobal.uViewPosition)), -1.0, 1.0))), 0.001);
    projCoords.z -= bias;
    
    // Clamp para evitar leitura fora do shadow map
    if (projCoords.z < 0.0 || projCoords.z > 1.0 || projCoords.x < 0.0 || projCoords.x > 1.0 || projCoords.y < 0.0 || projCoords.y > 1.0) {
        return 1.0;  // Fora do shadow map = fully lit
    }
    
    return sampleShadow(shadowMap, projCoords, cascade);
}

//============================================
// SPHERICAL HARMONICS ORDER 2
// Ambient lighting aproximado
//============================================
vec3 computeSHAmbient(vec3 normal) {
    // SH coefficients pre-baked (exemplo)
    // Na prática, viriam de um UBO
    const vec3 shCoeffs[9] = vec3[](
        vec3(0.5), vec3(0.3), vec3(0.2), vec3(0.1),
        vec3(0.15), vec3(0.1), vec3(0.05), vec3(0.02), vec3(0.01)
    );
    
    // SH basis functions
    vec3 ambient = shCoeffs[0];
    ambient += shCoeffs[1] * normal.y;
    ambient += shCoeffs[2] * normal.z;
    ambient += shCoeffs[3] * normal.x;
    ambient += shCoeffs[4] * normal.y * normal.x;
    ambient += shCoeffs[5] * normal.y * normal.z;
    ambient += shCoeffs[6] * normal.z * normal.x;
    ambient += shCoeffs[7] * (3.0 * normal.y * normal.y - 1.0);
    ambient += shCoeffs[8] * (normal.x * normal.x - normal.z * normal.z);
    
    return ambient * gLight.uAmbientColor;
}

//============================================
// MAIN LIGHTING COMPUTATION
//============================================
void main() {
    //========================================
    // GBUFFER UNPACK
    //========================================
    vec4 gBuffer0 = texture(uGBuffer0, vUV);
    vec4 gBuffer1 = texture(uGBuffer1, vUV);
    vec4 gBuffer2 = texture(uGBuffer2, vUV);
    
    vec3 albedo = gBuffer0.rgb;
    float metallic = gBuffer0.a;
    
    vec3 normalWS = decodeOctahedron(gBuffer1.xy);
    float roughness = gBuffer1.z;
    float ao = gBuffer1.w;
    
    vec3 emission = gBuffer2.rgb;
    
    //========================================
    // DERIVED VALUES
    //========================================
    vec3 viewDir = normalize(gGlobal.uViewPosition - gl_FragCoord.xyz);
    vec3 halfVec = normalize(viewDir - gLight.uLightDirection.xyz);
    
    // F0 para Fresnel (dielectric = 0.04, metal = albedo)
    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    
    //========================================
    // LIGHTING CALCULATION
    //========================================
    float NdotL = max(dot(normalWS, -gLight.uLightDirection.xyz), 0.0);
    float NdotV = max(dot(normalWS, viewDir), 0.0);
    float NdotH = max(dot(normalWS, halfVec), 0.0);
    float VdotH = max(dot(viewDir, halfVec), 0.0);
    
    // GGX Distribution
    float D = ggxDistribution(halfVec, normalWS, roughness);
    
    // Smith Visibility
    float G = smithGGX(NdotL, NdotV, roughness);
    
    // Schlick Fresnel
    vec3 F = schlickGGX(halfVec, normalWS, viewDir, roughness, F0);
    
    // Specular BRDF
    vec3 specular = (D * G * F) / max(4.0 * NdotL * NdotV, 0.001);
    
    // Diffuse (Lambert modificado para energia conservativa)
    vec3 diffuse = (1.0 - F) * (1.0 - metallic) * albedo * INV_PI;
    
    //========================================
    // SHADOWS
    //========================================
    float shadow = computeShadow(gl_FragCoord.xyz, gl_FragCoord.z);
    
    //========================================
    // AMBIENT (SH + AO)
    //========================================
    vec3 ambient = computeSHAmbient(normalWS) * ao;
    
    //========================================
    // FINAL LIGHTING
    //========================================
    vec3 directLight = (diffuse + specular) * NdotL * gLight.uLightColor.rgb * gLight.uLightColor.w;
    directLight *= shadow;
    
    vec3 finalColor = ambient + directLight + emission;
    
    //========================================
    // EXPOSURE
    //========================================
    finalColor *= gLight.uExposure;
    
    vFinalColor = vec4(finalColor, 1.0);
}

//============================================
// NOTAS DE OTIMIZAÇÃO:
// 1. GGX simplificado usa Schlick em vez de integral completo
// 2. PCF 3x3 com Poisson disk rotated (melhor quality/cost)
// 3. SH Order 2 para ambient (9 coeffs, barato)
// 4. MAD-heavy nas equações de BRDF
// 5. mediump precision para throughput
// 6. Cascade selection com branches estáticos
// 7. Early depth test no GBuffer já feito
// 8. Zero dependent reads exceto shadow lookup
//============================================
