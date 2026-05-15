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
uniform float foam_noise_scale = 0.1;
uniform float foam_edge_softness : hint_range(0.001, 0.5) = 0.05; 
uniform float valley_foam_scale = 0.05; 
uniform float valley_foam_amount : hint_range(0.0, 1.0) = 0.5; 

group_uniforms Performance;
uniform float foam_max_render_distance = 60.0;
uniform float foam_proximity_fade_margin = 15.0;

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
    float mix_low = smoothstep(deep_level, deep_level + (depth_blend_range * 0.5), wave_height_var);
    float crest_start = deep_level + (depth_blend_range * crest_blend_offset);
    float mix_high = smoothstep(crest_start, deep_level + depth_blend_range, wave_height_var); 

    vec3 albedo_color = mix(color_deep, color_mid, mix_low);
    albedo_color = mix(albedo_color, color_crest, mix_high);
        
    float foam_mix = 0.0;

    if (vertex_dist_var < foam_max_render_distance) {
        float proximity_fade = 1.0 - smoothstep(foam_max_render_distance - foam_proximity_fade_margin, foam_max_render_distance, vertex_dist_var);

        vec2 wind_dir_vec = rotate_dir(vec2(1.0, 0.0), wind_direction_degrees);
        float storm_foam_speed = mix(1.0, 2.5, storm_intensity);
        vec2 base_uv_offset = wind_dir_vec * TIME * 0.04 * storm_foam_speed;

        // Texture Fetch 1: Crest Foam
        vec2 crest_noise_uv = world_xz_var * foam_noise_scale + base_uv_offset;
        float raw_crest_noise = texture(foam_noise, crest_noise_uv).r;
        float combined_crest_noise = raw_crest_noise * raw_crest_noise; 

        // Uncorrelated UV base mapping
        vec2 valley_uncorrelated_xz = vec2(world_xz_var.y + 173.1, world_xz_var.x - 231.7);
        vec2 valley_noise_uv = valley_uncorrelated_xz * valley_foam_scale + (base_uv_offset * 0.8);
        
        // Procedural Fluid Warp: Replaces the crest-noise warp to eliminate intersection artifacts.
        // Uses orthogonal sine/cosine waves scaled by world space to create a swirling distortion.
        vec2 fluid_warp = vec2(
            sin(world_xz_var.y * 0.15 + TIME * 1.2),
            cos(world_xz_var.x * 0.15 + TIME * 1.2)
        ) * 0.04;
        valley_noise_uv += fluid_warp;
        
        float raw_valley_noise = texture(foam_noise, valley_noise_uv).r;
        float combined_valley_noise = raw_valley_noise * raw_valley_noise;
        
        float normalized_height = clamp(wave_height_var / max(0.1, local_max_height_var), 0.0, 1.0);
        
        // Crest Foam Logic
        float crest_threshold = max(0.0, 1.0 - foam_level - (storm_intensity * 0.4));
        float crest_mask = smoothstep(0.4, 0.8, normalized_height);
        float crest_foam = crest_mask * smoothstep(crest_threshold, crest_threshold + foam_edge_softness, combined_crest_noise);
        
        // Valley Foam Logic
        float valley_mask = 1.0 - smoothstep(0.2, 0.6, normalized_height);
        float valley_threshold = mix(0.95, 0.5, valley_foam_amount) - (storm_intensity * 0.1); 
        float valley_foam = valley_mask * smoothstep(valley_threshold, valley_threshold + foam_edge_softness, combined_valley_noise);
        
        // Additive Blend
        float base_foam = clamp(crest_foam + valley_foam, 0.0, 1.0);
        
        float opacity_fade = mix(0.35, 1.0, normalized_height);
        base_foam *= opacity_fade;
        
        // Sharp Break Edge Logic
        float peak_mask = smoothstep(0.85, 0.95, normalized_height);
        float sharp_edge = peak_mask * smoothstep(0.3, 0.3 + foam_edge_softness, combined_crest_noise);
        
        foam_mix = clamp(base_foam + sharp_edge, 0.0, 1.0);
        foam_mix *= proximity_fade;
    }
    
    albedo_color = mix(albedo_color, color_foam, foam_mix);
    albedo_color = mix(albedo_color, horizon_color, horizon_fade_var);
    
    ALBEDO = albedo_color;
    ROUGHNESS = 0.02; 
    SPECULAR = 0.4;
}