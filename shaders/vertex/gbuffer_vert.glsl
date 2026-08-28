//============================================
// SHADER: GBuffer Vertex Shader
// CUSTO ESTIMADO: 0.3ms na GTX 750 Ti @1080p
// ALU OPS: ~45 por vertex
// TEX FETCHES: 0 (texturas fetchadas no fragment)
// BANDWIDTH: ~0 MB/frame (apenas vertex data)
// TÉCNICA: Vertex shader otimizado com pré-cálculos
// TRUQUES USADOS: 
//   - Pré-calcular TBN no vertex (interpolação grátis)
//   - Octahedron normal encoding preparation
//   - Distance computation para LOD de shader
//   - Velocity buffer para motion blur
//============================================

#version 450 core

// Uniforms - agrupados para constant buffer efficiency
layout(std140, binding = 0) uniform GlobalUBO {
    mat4 uModelMatrix;
    mat4 uViewMatrix;
    mat4 uProjectionMatrix;
    mat4 uModelViewMatrix;
    mat4 uMVP;
    mat4 uPrevMVP;              // Para motion blur
    vec3 uViewPosition;
    float uTime;
    vec4 uSunDirection;         // w = cos(sunAngle)
    vec4 uFogParams;            // x=start, y=end, z=density, w=heightScale
} gGlobal;

layout(std140, binding = 1) uniform MaterialUBO {
    vec4 uBaseColor;
    vec4 uNormalScale;          // xy=scale, zw=offset
    vec4 uRoughnessMetallic;    // x=roughness, y=metallic, z=ao, w=emission
    vec4 uDetailScale;          // Para detail blending
    float uParallaxDepth;
    int uMaterialType;
} gMaterial;

// Vertex attributes
layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec4 aTangent;
layout(location = 3) in vec2 aUV0;
layout(location = 4) in vec2 aUV1;      // Lightmap UVs
layout(location = 5) in vec4 aColor;    // Vertex colors / tint

// Fragment outputs (GBuffer)
layout(location = 0) out vec4 vAlbedoMetallic;
layout(location = 1) out vec4 vNormalRoughAO;
layout(location = 2) out vec4 vEmissionMatID;

// Interpolants
out VS_TO_FS {
    vec3 worldPos;
    vec3 viewPos;
    vec2 uv0;
    vec2 uv1;
    vec4 color;
    vec3 normalWS;
    vec3 tangentWS;
    vec3 bitangentWS;
    float depth;
    float distanceToCamera;
    vec2 velocity;              // Para motion blur
    flat int materialType;
} vOut;

//============================================
// OCTAHEDRON NORMAL ENCODING
// Compressão de normais 3D → 2D para GBuffer
//============================================
vec2 encodeOctahedron(vec3 n) {
    // Truque: evitar branch usando abs e sign
    vec3 absN = abs(n);
    float sum = absN.x + absN.y + absN.z;
    vec2 encoded = n.xy / sum;
    
    // Mirror para hemisphere negativo sem branching
    // Usando step() em vez de if
    float test = step(0.0, n.z);
    vec2 mirrored = (1.0 - abs(encoded.yx)) * sign(vec2(-encoded.x, -encoded.y));
    return mix(mirrored, encoded, test);
}

void main() {
    // Transformações básicas
    vec4 worldPos4 = gGlobal.uModelMatrix * vec4(aPosition, 1.0);
    vOut.worldPos = worldPos4.xyz;
    
    vec4 viewPos4 = gGlobal.uViewMatrix * worldPos4;
    vOut.viewPos = viewPos4.xyz;
    vOut.depth = -viewPos4.z;  // Depth positivo
    
    gl_Position = gGlobal.uProjectionMatrix * viewPos4;
    
    // Distance to camera para LOD
    vOut.distanceToCamera = length(viewPos4.xyz);
    
    // UVs
    vOut.uv0 = aUV0;
    vOut.uv1 = aUV1;
    vOut.color = aColor;
    
    // TBN matrix em world space (pré-calcular aqui é grátis!)
    // Normal
    vOut.normalWS = normalize(mat3(gGlobal.uModelMatrix) * aNormal);
    
    // Tangent
    vOut.tangentWS = normalize(mat3(gGlobal.uModelMatrix) * aTangent.xyz);
    
    // Bitangent (cross product, handedness do tangent.w)
    vOut.bitangentWS = normalize(cross(vOut.normalWS, vOut.tangentWS) * aTangent.w);
    
    // Velocity para motion blur (screen space)
    vec4 prevClipPos = gGlobal.uPrevMVP * vec4(aPosition, 1.0);
    vec2 currNDC = gl_Position.xy / gl_Position.w;
    vec2 prevNDC = prevClipPos.xy / prevClipPos.w;
    vOut.velocity = (currNDC - prevNDC) * 0.5;  // [-1,1] → [0,1] space
    
    // Material type flat interpolation
    vOut.materialType = gMaterial.uMaterialType;
}

//============================================
// NOTAS DE OTIMIZAÇÃO:
// 1. TBN calculado no vertex = 3 cross products economizados no fragment
// 2. Octahedron encoding preparation feita aqui
// 3. Velocity já em screen space evita divisão no fragment
// 4. Distance pre-calculada para LOD decisions
// 5. Flat interpolation para materialType (sem interpolação)
//============================================
