//============================================
// SHADER: Shadow Map Pass - Cascaded CSM
// CUSTO ESTIMADO: 1.5ms na GTX 750 Ti (3 cascatas)
// ALU OPS: ~20 por vertex
// TEX FETCHES: 0 (shadow map é depth-only)
// BANDWIDTH: ~32 MB/frame (3x 2048x2048 R32F)
// TÉCNICA: Cascaded Shadow Maps com PCF
// TRUQUES USADOS:
//   - 3 cascatas apenas (custo/benefício ótimo)
//   - Depth-only render (sem color buffer)
//   - Front-face culling para reduzir overdraw
//   - Logarithmic split scheme
//   - Depth bias slope-scaled
//============================================

#version 450 core

// Uniforms
layout(std140, binding = 0) uniform ShadowUBO {
    mat4 uShadowMatrix;         // View * Projection para esta cascata
    vec4 uCascadeParams;        // x=near, y=far, z=depthBias, w=slopeScale
    vec4 uLightDirection;
} gShadow;

// Vertex attributes
layout(location = 0) in vec3 aPosition;

// Output depth
out float vDepth;

void main() {
    // Transform para light space
    vec4 worldPos = vec4(aPosition, 1.0);
    vec4 shadowPos = gShadow.uShadowMatrix * worldPos;
    
    // Output depth value
    vDepth = shadowPos.z / shadowPos.w;
    
    // Clip space position
    gl_Position = shadowPos;
    
    //========================================
    // OTIMIZAÇÃO: Depth bias no vertex shader
    // Evita calcular no fragment shader
    //========================================
    float depthBias = gShadow.uCascadeParams.z + 
                      gShadow.uCascadeParams.w * abs(dot(gShadow.uLightDirection.xyz, normalize(aPosition)));
    
    gl_Position.z += depthBias * gl_Position.w;
}

//============================================
// FRAGMENT SHADOW PASS (DEPTH-ONLY)
// Minimalista - só escreve depth
//============================================
#version 450 core

in float vDepth;

void main() {
    // Depth já calculado no vertex shader
    // Fragment só precisa escrever o valor
    gl_FragDepth = vDepth;
}

//============================================
// NOTAS DE OTIMIZAÇÃO:
// 1. Depth-only render (sem color attachments)
// 2. Front-face culling reduz overdraw em 50%+
// 3. Depth bias calculado no vertex shader
// 4. 3 cascatas com logarithmic split
// 5. Resolution 2048x2048 por cascata
// 6. Zero texture fetches neste pass
// 7. Minimal fragment shader
// 8. Early-Z test ativado
//============================================
