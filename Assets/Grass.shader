Shader "Roystan/Grass"
{
    Properties
    {
        [Header(Shading)]
        _TopColor("Top Color", Color) = (1,1,1,1)
        _BottomColor("Bottom Color", Color) = (1,1,1,1)
        _TranslucentGain("Translucent Gain", Range(0,1)) = 0.5
        _Smoothness("Smoothness", Range(0,1)) = 0.5
        _Metallic("Metallic", Range(0,1)) = 0.0
        [Space]
        _TessellationUniform ("Tessellation Uniform", Range(1, 64)) = 1
        [Header(Blades)]
        _BladeWidth("Blade Width", Float) = 0.05
        _BladeWidthRandom("Blade Width Random", Float) = 0.02
        _BladeHeight("Blade Height", Float) = 0.5
        _BladeHeightRandom("Blade Height Random", Float) = 0.3
        _BladeForward("Blade Forward Amount", Float) = 0.38
        _BladeCurve("Blade Curvature Amount", Range(1, 4)) = 2
        _BendRotationRandom("Bend Rotation Random", Range(0, 1)) = 0.2
        [Header(Wind)]
        _WindDistortionMap("Wind Distortion Map", 2D) = "white" {}
        _WindStrength("Wind Strength", Float) = 1
        _WindFrequency("Wind Frequency", Vector) = (0.05, 0.05, 0, 0)
        [Header(Lighting)]
        _LightAttenuationMultiplier("Light Attenuation Multiplier", Range(0.1, 25)) = 1.0
        _LightFalloffExponent("Light Falloff Exponent", Range(0.1, 4)) = 1.0
        _LightRangeMultiplier("Light Range Multiplier", Range(0.1, 10)) = 1.0
    }

    CGINCLUDE
    #include "UnityCG.cginc"
    #include "Autolight.cginc"
    #include "Lighting.cginc"
    #include "UnityPBSLighting.cginc"
    #include "Shaders/CustomTessellation.cginc"

    struct GrassVertexOutput
    {
        float4 pos : SV_POSITION;
        float3 normal : NORMAL;
        float2 uv : TEXCOORD0;
        float3 worldPos : TEXCOORD1;
        #if !UNITY_PASS_SHADOWCASTER
            float4 shadowCoord : TEXCOORD2;
            float3 viewDir : TEXCOORD3;
        #endif
    };

    // Properties
    float _BladeHeight;
    float _BladeHeightRandom;
    float _BladeWidthRandom;
    float _BladeWidth;
    float _BladeForward;
    float _BladeCurve;
    float _BendRotationRandom;
    sampler2D _WindDistortionMap;
    float4 _WindDistortionMap_ST;
    float _WindStrength;
    float2 _WindFrequency;
    float4 _TopColor;
    float4 _BottomColor;
    float _TranslucentGain;
    float _Smoothness;
    float _Metallic;
    float _LightAttenuationMultiplier;
    float _LightFalloffExponent;
    float _LightRangeMultiplier;

    float rand(float3 co)
    {
        return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
    }

    float3x3 AngleAxis3x3(float angle, float3 axis)
    {
        float c, s;
        sincos(angle, s, c);

        float t = 1 - c;
        float x = axis.x;
        float y = axis.y;
        float z = axis.z;

        return float3x3(
            t * x * x + c, t * x * y - s * z, t * x * z + s * y,
            t * x * y + s * z, t * y * y + c, t * y * z - s * x,
            t * x * z - s * y, t * y * z + s * x, t * z * z + c
        );
    }

    GrassVertexOutput CreateGrassVertex(float3 vertPos, float3 normal, float2 uv, float3 worldPos)
    {
        GrassVertexOutput o;
        
        #if UNITY_PASS_SHADOWCASTER
            o.pos = UnityObjectToClipPos(float4(vertPos, 1));
            o.normal = normal; // Keep normal for potential use
            o.uv = uv;
            o.worldPos = worldPos;
            
            // Handle shadow bias
            #if UNITY_REVERSED_Z
                o.pos.z = min(o.pos.z, o.pos.w * UNITY_NEAR_CLIP_VALUE);
            #else
                o.pos.z = max(o.pos.z, o.pos.w * UNITY_NEAR_CLIP_VALUE);
            #endif
        #else
            o.pos = UnityWorldToClipPos(worldPos);
            o.normal = UnityObjectToWorldNormal(normal);
            o.worldPos = worldPos;
            o.viewDir = WorldSpaceViewDir(float4(vertPos, 1));
            o.uv = uv;
            o.shadowCoord = ComputeScreenPos(o.pos);
        #endif
        
        return o;
    }

    GrassVertexOutput GenerateGrassVertex(float3 vertPos, float width, float height, float forward, float2 uv, float3x3 transformMatrix)
    {
        float3 tangentPoint = float3(width, forward, height);
        float3 tangentNormal = float3(0, -1, forward);
        tangentNormal = normalize(tangentNormal); // Normalize the normal vector
        
        float3 localPosition = vertPos + mul(transformMatrix, tangentPoint);
        float3 localNormal = mul(transformMatrix, tangentNormal);
        float3 worldPos = mul(unity_ObjectToWorld, float4(localPosition, 1)).xyz;
        
        return CreateGrassVertex(localPosition, localNormal, uv, worldPos);
    }

    #define BLADE_SEGMENTS 3
    
    [maxvertexcount(BLADE_SEGMENTS * 2 + 1)]
    void geo(triangle vertexOutput IN[3], inout TriangleStream<GrassVertexOutput> triStream)
    {
        float3 pos = IN[0].vertex.xyz;
        
        float3x3 facingRotationMatrix = AngleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1));
        float3x3 bendRotationMatrix = AngleAxis3x3(rand(pos.zzx) * _BendRotationRandom * UNITY_PI * 0.5, float3(-1, 0, 0));

        float2 uv = pos.xz * _WindDistortionMap_ST.xy + _WindDistortionMap_ST.zw + _WindFrequency * _Time.y;
        float2 windSample = (tex2Dlod(_WindDistortionMap, float4(uv, 0, 0)).xy * 2 - 1) * _WindStrength;
        float3 wind = float3(windSample.x, windSample.y, 0);
        wind = normalize(wind);
        float3x3 windRotation = AngleAxis3x3(UNITY_PI * windSample, wind);

        float3 vNormal = IN[0].normal;
        float4 vTangent = IN[0].tangent;
        float3 vBinormal = cross(vNormal, vTangent.xyz) * vTangent.w;

        float3x3 tangentToLocal = float3x3(
            vTangent.x, vBinormal.x, vNormal.x,
            vTangent.y, vBinormal.y, vNormal.y,
            vTangent.z, vBinormal.z, vNormal.z
        );

        float3x3 transformationMatrix = mul(mul(mul(tangentToLocal, windRotation), facingRotationMatrix), bendRotationMatrix);
        float3x3 transformationMatrixFacing = mul(tangentToLocal, facingRotationMatrix);

        float height = (rand(pos.zyx) * 2 - 1) * _BladeHeightRandom + _BladeHeight;
        float width = (rand(pos.xzy) * 2 - 1) * _BladeWidthRandom + _BladeWidth;
        float forward = rand(pos.yyz) * _BladeForward;

        for (int i = 0; i < BLADE_SEGMENTS; i++)
        {
            float t = i / (float)BLADE_SEGMENTS;
            float segmentHeight = height * t;
            float segmentWidth = width * (1 - t);
            float segmentForward = pow(t, _BladeCurve) * forward;

            float3x3 transformMatrix = i == 0 ? transformationMatrixFacing : transformationMatrix;

            triStream.Append(GenerateGrassVertex(pos, segmentWidth, segmentHeight, segmentForward, float2(0, t), transformMatrix));
            triStream.Append(GenerateGrassVertex(pos, -segmentWidth, segmentHeight, segmentForward, float2(1, t), transformMatrix));
        }

        triStream.Append(GenerateGrassVertex(pos, 0, height, forward, float2(0.5, 1), transformationMatrix));
    }

    float4 frag(GrassVertexOutput i) : SV_Target
    {
        #if UNITY_PASS_SHADOWCASTER
            return 0;
        #else
            float3 worldNormal = normalize(i.normal);
            float3 viewDir = normalize(i.viewDir);
            
            float3 lightDir;
            float attenuation;
            
            if (_WorldSpaceLightPos0.w == 0.0)
            {
                lightDir = normalize(_WorldSpaceLightPos0.xyz);
                attenuation = 1.0;
            }
            else
            {
                float3 lightVector = _WorldSpaceLightPos0.xyz - i.worldPos;
                lightDir = normalize(lightVector);
                float lightDistance = length(lightVector);
                float lightRange = length(unity_LightPosition[0].xyz) * _LightRangeMultiplier;
                float normalizedDistance = lightDistance / lightRange;
                attenuation = 1.0 / (1.0 + normalizedDistance * normalizedDistance);
                attenuation = pow(attenuation, _LightFalloffExponent) * _LightAttenuationMultiplier;
            }

            UNITY_LIGHT_ATTENUATION(shadowAttenuation, i, i.worldPos);
            attenuation *= shadowAttenuation;
            
            float NdotL = saturate(dot(worldNormal, lightDir));
            float3 directLight = NdotL * _LightColor0.rgb * attenuation;
            
            float translucency = pow(saturate(-dot(worldNormal, lightDir)), 1.5) * _TranslucentGain;
            float3 translucencyLight = translucency * _LightColor0.rgb * attenuation;
            
            float3 ambient = ShadeSH9(float4(worldNormal, 1));
            
            float3 albedo = lerp(_BottomColor.rgb, _TopColor.rgb, i.uv.y);
            float3 finalColor = albedo * (directLight + ambient + translucencyLight);
            
            return float4(finalColor, 1);
        #endif
    }

    float4 fragAdd(GrassVertexOutput i) : SV_Target
    {
        float3 worldNormal = normalize(i.normal);
        float3 lightDir = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
        
        float attenuation;
        float3 lightVector = _WorldSpaceLightPos0.xyz - i.worldPos;
        float lightDistance = length(lightVector);
        float lightRange = length(unity_LightPosition[0].xyz) * _LightRangeMultiplier;
        float normalizedDistance = lightDistance / lightRange;
        attenuation = 1.0 / (1.0 + normalizedDistance * normalizedDistance);
        attenuation = pow(attenuation, _LightFalloffExponent) * _LightAttenuationMultiplier;
        
        UNITY_LIGHT_ATTENUATION(shadowAttenuation, i, i.worldPos);
        attenuation *= shadowAttenuation;
        
        float NdotL = saturate(dot(worldNormal, lightDir));
        float translucency = pow(saturate(-dot(worldNormal, lightDir)), 1.5) * _TranslucentGain;
        
        float3 albedo = lerp(_BottomColor.rgb, _TopColor.rgb, i.uv.y);
        float3 lighting = NdotL * _LightColor0.rgb * attenuation;
        float3 translucencyLight = translucency * _LightColor0.rgb * attenuation;
        
        return float4(albedo * (lighting + translucencyLight), 1);
    }

    ENDCG

    SubShader
    {
        Cull Off

        Pass
        {
            Tags
            {
                "RenderType" = "Opaque"
                "LightMode" = "ForwardBase"
            }

            CGPROGRAM
            #pragma vertex vert
            #pragma hull hull
            #pragma domain domain
            #pragma geometry geo
            #pragma fragment frag
            #pragma multi_compile_fwdbase
            #pragma target 4.6
            ENDCG
        }

        Pass
        {
            Tags {"LightMode" = "ShadowCaster"}

            CGPROGRAM
            #pragma vertex vert
            #pragma hull hull
            #pragma domain domain
            #pragma geometry geo
            #pragma fragment frag
            #pragma multi_compile_shadowcaster
            #pragma target 4.6
            ENDCG
        }
        
        Pass
        {
            Tags {"LightMode" = "ForwardAdd"}
            Blend One One
            ZWrite Off
            
            CGPROGRAM
            #pragma vertex vert
            #pragma hull hull
            #pragma domain domain
            #pragma geometry geo
            #pragma fragment fragAdd
            #pragma multi_compile_fwdadd_fullshadows
            #pragma target 4.6
            ENDCG
        }
    }
}