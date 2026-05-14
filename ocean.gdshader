shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// --- UNIFORMS: FARBEN & UMGEBUNG ---
uniform vec3 color_deep : source_color = vec3(0.07, 0.25, 0.34);
uniform vec3 color_mid : source_color = vec3(0.14, 0.44, 0.51);
uniform vec3 color_crest : source_color = vec3(0.19, 0.72, 0.67);

uniform vec3 color_foam : source_color = vec3(0.9, 0.9, 0.95);
uniform vec3 horizon_color : source_color = vec3(0.5, 0.6, 0.7);

uniform float deep_level = -0.5;
uniform float depth_blend_range = 1.0;
uniform float crest_blend_offset = 0.5;

// --- UNIFORMS: WELLEN-GEOMETRIE ---
uniform vec4 wave_a = vec4(5.1, 0.3, 0.3, 11.7);
uniform vec4 wave_b = vec4(0.43, 0.31, 0.15, 3.1);
uniform vec4 wave_c = vec4(-0.12, 0.13, 0.054, 2.3);
uniform float time_scale = 0.5;

// --- UNIFORMS: FADING & EFFEKTE ---
uniform float fade_start = 30.0;
uniform float fade_end = 80.0;   

uniform sampler2D wave_noise : hint_default_black;
uniform float noise_scale = 0.02;

// --- UNIFORMS: GISCHT ---
uniform sampler2D foam_noise : hint_default_white;
uniform float foam_noise_scale = 0.3;
uniform float foam_level = 0.15;
uniform float foam_edge_softness = 0.1;
uniform float foam_sparseness = 3.0;

// --- PERFORMANCE: GISCHT-AUSBLENDUNG IN DER FERNE ---
uniform float foam_max_render_distance = 60.0;
uniform float foam_proximity_fade_margin = 15.0;

// --- VARYINGS ---
varying float wave_height_var;
varying float horizon_fade_var;
varying vec2 world_xz_var;
varying float vertex_dist_var;
varying float foam_potential_var; // NEU: Gischt-Wahrscheinlichkeit aus dem Vertex-Shader

// --- HELFERFUNKTIONEN ---
vec3 gerstner_wave(vec4 wave, vec3 p, float time, float multiplier, float phase_offset) {
    float amplitude = wave.z * multiplier;
    float wavelength = wave.w;
    
    if (wavelength <= 0.01) { return vec3(0.0); }
    
    float k = 2.0 * PI / wavelength;
    float c = sqrt(9.8 / k);
    vec2 d = normalize(wave.xy);
    
    if (length(wave.xy) < 0.01) { d = vec2(1.0, 0.0); }
    
    float f = k * (dot(d, p.xz) - c * time * time_scale) + phase_offset;
    
    return vec3(
        d.x * (amplitude * cos(f)),
        amplitude * sin(f),
        d.y * (amplitude * cos(f))
    );
}

vec3 get_wave_displacement(vec3 p, float time, float multiplier, float phase_offset) {
    vec3 d = vec3(0.0);
    d += gerstner_wave(wave_a, p, time, multiplier, phase_offset);
    d += gerstner_wave(wave_b, p, time * 1.1, multiplier, phase_offset * 1.2);
    d += gerstner_wave(wave_c, p, time * 0.9, multiplier, phase_offset * 1.5);
    return d;
}

// --- VERTEX SHADER ---
void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_xz_var = world_pos.xz;
    
    float dist = distance(world_pos, CAMERA_POSITION_WORLD);
    vertex_dist_var = dist;

    vec2 noise_uv = world_pos.xz * noise_scale + (TIME * 0.01);
    float noise_val = texture(wave_noise, noise_uv).r; 
    
    float height_multiplier = mix(0.3, 1.5, noise_val);
    float phase_warp = (noise_val - 0.5) * 3.0; 
    
    vec3 displacement = get_wave_displacement(world_pos, TIME, height_multiplier, phase_warp);

    float e = 0.1; 
    vec3 px = world_pos + vec3(e, 0.0, 0.0);
    vec3 pz = world_pos + vec3(0.0, 0.0, e);

    vec3 displacement_x = get_wave_displacement(px, TIME, height_multiplier, phase_warp);
    vec3 displacement_z = get_wave_displacement(pz, TIME, height_multiplier, phase_warp);

    vec3 p0 = world_pos + displacement;
    vec3 p1 = px + displacement_x;
    vec3 p2 = pz + displacement_z;

    vec3 smooth_normal = normalize(cross(p2 - p0, p1 - p0));
    NORMAL = (inverse(MODEL_MATRIX) * vec4(smooth_normal, 0.0)).xyz;

    // Schaumpotenzial im Vertex-Shader berechnen
    // Erzeugt Werte von x bis y, abhängig davon wie nah die Welle an ihrer Maximalhöhe ist.
    float crest_pot = smoothstep(0.1, 0.6, displacement.y); 
    // Nutzt die Weltraum-Normale. Je flacher die Welle, desto näher ist smooth_normal.xz an vec2(0.0).
    float slope_pot = smoothstep(0.1, 0.6, length(smooth_normal.xz)); 
    
    foam_potential_var = clamp(crest_pot + slope_pot, 0.0, 1.0);

    float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
    displacement *= fade;
    horizon_fade_var = smoothstep(fade_start, fade_end, dist);
    
    wave_height_var = displacement.y;

    vec3 new_world_pos = world_pos + displacement;
    VERTEX = (inverse(MODEL_MATRIX) * vec4(new_world_pos, 1.0)).xyz;
}

// --- FRAGMENT SHADER ---
void fragment() {
    // 1. Übergang: Von den tiefen Tälern zur Mitte der Welle
    // Wir nutzen die erste Hälfte der Blend-Range
    float mix_low = smoothstep(deep_level, deep_level + (depth_blend_range * 0.6), wave_height_var);
    
    // 2. Übergang: Von der Mitte zu den leuchtenden Kämmen (Subsurface-Effekt)
    // Wir starten den Übergang etwas später, damit nur die Spitzen leuchten
    float mix_high = smoothstep(deep_level + (depth_blend_range * crest_blend_offset), deep_level + depth_blend_range, wave_height_var);

    // Farben mischen
    vec3 albedo_color = mix(color_deep, color_mid, mix_low);
    albedo_color = mix(albedo_color, color_crest, mix_high);
        
    float foam_mix = 0.0;

    if (vertex_dist_var < foam_max_render_distance) {
        
        float proximity_fade = 1.0 - smoothstep(foam_max_render_distance - foam_proximity_fade_margin, foam_max_render_distance, vertex_dist_var);

        vec2 noise_uv1 = world_xz_var * foam_noise_scale + (TIME * 0.04);
        vec2 noise_uv2 = world_xz_var * (foam_noise_scale * 1.2) - (TIME * 0.03);
        float f_noise1 = texture(foam_noise, noise_uv1).r;
        float f_noise2 = texture(foam_noise, noise_uv2).r;
        
        float combined_noise = f_noise1 * f_noise2;
        combined_noise = smoothstep(0.2, 0.5, combined_noise);
        
        // Dynamische Dichte (Sparseness)
        float dynamic_sparseness = mix(foam_sparseness, 1.0, foam_potential_var);
        combined_noise = pow(combined_noise, dynamic_sparseness); 
        
        // Wahrscheinlichkeit
        float final_foam_value = combined_noise * foam_potential_var;
        
        // Dynamischer Schwellenwert
        float dynamic_level = mix(foam_level + 0.1, foam_level - 0.05, foam_potential_var);
        
        foam_mix = smoothstep(dynamic_level, dynamic_level + foam_edge_softness, final_foam_value);
        foam_mix *= proximity_fade;
    }
    
    albedo_color = mix(albedo_color, color_foam, foam_mix);
    albedo_color = mix(albedo_color, horizon_color, horizon_fade_var);
    
    ALBEDO = albedo_color;
    ROUGHNESS = 0.05; 
    SPECULAR = 0.5;
}