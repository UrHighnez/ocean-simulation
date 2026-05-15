shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms Weather;
uniform float wind_direction_degrees : hint_range(0.0, 360.0) = 0.0; 
uniform float storm_intensity : hint_range(0.0, 1.0) = 0.2; 

group_uniforms Colors;
uniform vec3 color_deep : source_color = vec3(0.07, 0.25, 0.34);
uniform vec3 color_mid : source_color = vec3(0.14, 0.44, 0.51); 
uniform vec3 color_crest : source_color = vec3(0.18, 0.72, 0.67);
uniform vec3 color_foam : source_color = vec3(0.9, 0.9, 0.95);
uniform vec3 horizon_color : source_color = vec3(0.5, 0.6, 0.7);

group_uniforms Wave_Blending;
uniform float deep_level = -4.0;
uniform float depth_blend_range = 8.0;
uniform float crest_blend_offset : hint_range(0.0, 1.0) = 0.3; 

group_uniforms Wave_Geometry;
uniform int wave_iterations : hint_range(1, 8) = 5;
uniform float global_wave_scale = 1.0;
uniform float global_steepness : hint_range(0.0, 1.5) = 0.8;
uniform float time_scale = 0.7;

group_uniforms Fading_Effects;
uniform float fade_start = 30.0;
uniform float fade_end = 80.0;   
uniform sampler2D wave_noise : hint_default_black;
uniform float noise_scale = 0.02;

group_uniforms Foam;
uniform sampler2D foam_noise : hint_default_white;
uniform float foam_level : hint_range(0.0, 1.0) = 0.5;
uniform float foam_noise_scale = 0.2;
uniform float foam_edge_softness : hint_range(0.001, 0.5) = 0.05; 
uniform float valley_foam_scale = 0.1; 
uniform float valley_foam_amount : hint_range(0.0, 1.0) = 0.5; 

group_uniforms Performance;
uniform float foam_max_render_distance = 60.0;
uniform float foam_proximity_fade_margin = 15.0;

group_uniforms Micro_Details;
uniform sampler2D wave_normal_map : hint_normal;
uniform float normal_scale = 0.1;
uniform vec2 normal_pan_speed = vec2(0.05, 0.03);
uniform float normal_uv_scale = 0.1;

group_uniforms Lighting;
uniform float sss_intensity : hint_range(0.0, 2.0) = 0.1;
uniform float fresnel_power : hint_range(1.0, 10.0) = 5.0;

// Reset uniform grouping
group_uniforms;

// --- VARYINGS ---
varying float wave_height_var;
varying float horizon_fade_var;
varying vec2 world_xz_var;
varying float vertex_dist_var;
varying float local_max_height_var;

// --- HELFERFUNKTIONEN ---
vec2 rotate_dir(vec2 dir, float deg) {
    float rad = radians(deg);
    float c = cos(rad);
    float s = sin(rad);
    return vec2(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
}

void calculate_gerstner_wave(vec2 world_xz, float time, float storm_multiplier, out vec3 out_pos, out vec3 out_normal) {
    vec3 tangent = vec3(1.0, 0.0, 0.0);
    vec3 binormal = vec3(0.0, 0.0, 1.0);
    vec3 pos = vec3(world_xz.x, 0.0, world_xz.y);
    
    float frequency = 0.2 / global_wave_scale;
    float amplitude = 1.5 * global_wave_scale * storm_multiplier;
    float speed = 2.0 * time_scale * mix(0.2, 1.8, storm_intensity);
    
    vec2 wind_dir = rotate_dir(vec2(1.0, 0.0), wind_direction_degrees);

    for (int i = 0; i < wave_iterations; i++) {
        vec2 dir = rotate_dir(wind_dir, float(i) * 27.5); 
        
        float k = frequency;
        float a = amplitude;
        float steepness = global_steepness / (float(wave_iterations) * a * k); 
        
        float f = dot(dir, world_xz) * k - time * speed;
        float sin_f = sin(f);
        float cos_f = cos(f);
        
        pos.x += dir.x * (steepness * a * cos_f);
        pos.z += dir.y * (steepness * a * cos_f);
        pos.y += a * sin_f;
        
        float wa = k * a;
        tangent.x -= dir.x * dir.x * (steepness * wa * sin_f);
        tangent.y += dir.x * (wa * cos_f);
        tangent.z -= dir.x * dir.y * (steepness * wa * sin_f);
        
        binormal.x -= dir.x * dir.y * (steepness * wa * sin_f);
        binormal.y += dir.y * (wa * cos_f);
        binormal.z -= dir.y * dir.y * (steepness * wa * sin_f);
        
        frequency *= 1.8;
        amplitude *= 0.45;
        speed *= 1.1;
    }
    
    out_pos = pos;
    out_normal = normalize(cross(binormal, tangent));
}

// --- VERTEX SHADER ---
void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float dist = distance(world_pos, CAMERA_POSITION_WORLD);
    vertex_dist_var = dist;

    vec2 noise_uv = world_pos.xz * noise_scale + (TIME * 0.01);
    float noise_val = texture(wave_noise, noise_uv).r; 
    
    float storm_scale = mix(0.05, 2.5, storm_intensity); 
    float height_multiplier = mix(0.5, 1.2, noise_val) * storm_scale;
    
    local_max_height_var = (1.5 * global_wave_scale * height_multiplier) * 1.81;
    
    vec3 final_pos;
    vec3 final_normal;
    calculate_gerstner_wave(world_pos.xz, TIME, height_multiplier, final_pos, final_normal);

    NORMAL = (inverse(MODEL_MATRIX) * vec4(final_normal, 0.0)).xyz;
    
    vec3 displacement = final_pos - vec3(world_pos.x, 0.0, world_pos.z);
    wave_height_var = displacement.y; 

    float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
    displacement *= fade;
    
    horizon_fade_var = smoothstep(fade_start, fade_end, dist);

    vec3 new_world_pos = world_pos + displacement;
    world_xz_var = new_world_pos.xz; 
    
    VERTEX = (inverse(MODEL_MATRIX) * vec4(new_world_pos, 1.0)).xyz;
}

// --- FRAGMENT SHADER ---
void fragment() {
    // --- GLOBAL STORM MODULATION ---
    // Extracted to top-level to dynamically flatten geometry and disable foam simultaneously.
    float storm_fade = smoothstep(0.0, 0.2, storm_intensity);

    // 1. DUAL-LAYER NORMAL MAPPING (MICRO-GEOMETRY)
    vec2 wind_dir_vec = rotate_dir(vec2(1.0, 0.0), wind_direction_degrees);
    float ripple_speed = mix(0.5, 2.5, storm_intensity);
    
    vec2 normal_uv1 = world_xz_var * normal_uv_scale + wind_dir_vec * TIME * normal_pan_speed.x * ripple_speed;
    vec2 normal_uv2 = world_xz_var * (normal_uv_scale * 1.3) - vec2(wind_dir_vec.y, wind_dir_vec.x) * TIME * normal_pan_speed.y * ripple_speed;
    
    vec3 n1 = texture(wave_normal_map, normal_uv1).rgb;
    vec3 n2 = texture(wave_normal_map, normal_uv2).rgb;
    
    vec3 t1 = n1 * 2.0 - 1.0;
    vec3 t2 = n2 * 2.0 - 1.0;
    vec3 combined_normal = normalize(vec3(t1.xy + t2.xy, t1.z));
    
    NORMAL_MAP = combined_normal * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = normal_scale * storm_fade;

    // 2. HEIGHT & BASE COLOR CALCULATION
    float normalized_height = clamp(wave_height_var / max(0.1, local_max_height_var), 0.0, 1.0);
    
    float mix_low = smoothstep(deep_level, deep_level + (depth_blend_range * 0.5), wave_height_var);
    float crest_start = deep_level + (depth_blend_range * crest_blend_offset);
    float mix_high = smoothstep(crest_start, deep_level + depth_blend_range, wave_height_var); 

    vec3 albedo_color = mix(color_deep, color_mid, mix_low);
    albedo_color = mix(albedo_color, color_crest, mix_high);

    // 3. FRESNEL REFLECTANCE
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
    albedo_color = mix(albedo_color, horizon_color, fresnel * 0.8);

    // 4. SUBSURFACE SCATTERING (SSS) APPROXIMATION
    float sss_mask = smoothstep(0.4, 1.0, normalized_height);
    vec3 sss_emission = color_crest * sss_mask * sss_intensity;

    // 5. FOAM CALCULATION
    float foam_mix = 0.0;

    if (vertex_dist_var < foam_max_render_distance) {
        float proximity_fade = 1.0 - smoothstep(foam_max_render_distance - foam_proximity_fade_margin, foam_max_render_distance, vertex_dist_var);
        float storm_foam_speed = mix(1.0, 2.5, storm_intensity);
        
        vec2 crest_uv_offset = wind_dir_vec * TIME * 0.04 * storm_foam_speed;
        vec2 valley_uv_offset = wind_dir_vec * TIME * 0.005 * storm_foam_speed; 

        vec2 crest_noise_uv = world_xz_var * foam_noise_scale + crest_uv_offset;
        float raw_crest_noise = texture(foam_noise, crest_noise_uv).r;
        float combined_crest_noise = raw_crest_noise * raw_crest_noise; 

        vec2 valley_uncorrelated_xz = vec2(world_xz_var.y + 173.1, world_xz_var.x - 231.7);
        vec2 valley_noise_uv = valley_uncorrelated_xz * valley_foam_scale + valley_uv_offset;
        
        vec2 fluid_warp = vec2(
            sin(world_xz_var.y * 0.15 + TIME * 0.8),
            cos(world_xz_var.x * 0.15 + TIME * 0.8)
        ) * 0.04;
        valley_noise_uv += fluid_warp;
        
        float raw_valley_noise = texture(foam_noise, valley_noise_uv).r;
        float combined_valley_noise = raw_valley_noise * raw_valley_noise;
        
        float unified_noise = max(combined_crest_noise, combined_valley_noise);
        
        float dynamic_crest_level = foam_level * storm_fade;
        float crest_threshold = max(0.0, 1.0 - dynamic_crest_level - (storm_intensity * 0.4));
        
        float dynamic_valley_amount = valley_foam_amount * storm_fade;
        float valley_threshold = mix(1.0, 0.5, dynamic_valley_amount); 
        
        float dynamic_threshold = mix(valley_threshold, crest_threshold, smoothstep(0.2, 0.8, normalized_height));
        
        float base_foam = smoothstep(dynamic_threshold, dynamic_threshold + foam_edge_softness, unified_noise);
        
        float opacity_fade = mix(0.65, 1.0, normalized_height);
        base_foam *= opacity_fade;
        
        float peak_mask = smoothstep(0.85, 0.95, normalized_height);
        
        float sharp_threshold = mix(1.0, 0.3, storm_fade);
        float sharp_edge = peak_mask * smoothstep(sharp_threshold, sharp_threshold + foam_edge_softness, unified_noise);
        
        foam_mix = clamp(base_foam + sharp_edge, 0.0, 1.0);
        foam_mix *= proximity_fade;
    }
    
    albedo_color = mix(albedo_color, color_foam, foam_mix);
    
    ALBEDO = albedo_color;
    EMISSION = sss_emission * (1.0 - foam_mix);
    ROUGHNESS = mix(0.02, 0.15, foam_mix);
    SPECULAR = 0.5;
}