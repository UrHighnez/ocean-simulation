shader_type spatial;

uniform vec3 color_deep : source_color = vec3(0.05, 0.15, 0.3);
uniform vec3 color_shallow : source_color = vec3(0.1, 0.4, 0.6);
uniform vec3 color_foam : source_color = vec3(0.9, 0.9, 0.95);

uniform vec3 horizon_color : source_color = vec3(0.5, 0.6, 0.7);

uniform float foam_level = 0.08;
uniform float deep_level = -0.05;
uniform float time_scale = 0.1;

uniform vec4 wave_a = vec4(0.5, 0.0, 0.1, 5.0);
uniform vec4 wave_b = vec4(0.4, 0.3, 0.075, 3.0);
uniform vec4 wave_c = vec4(-0.1, 0.15, 0.05, 2.0);

uniform float fade_start = 30.0;
uniform float fade_end = 80.0;

uniform sampler2D wave_noise;
uniform float noise_scale = 0.02;

varying float wave_height_var;
varying float horizon_fade_var;

vec3 gerstner_wave(vec4 wave, vec3 p, float time, float multiplier) {
    float steepness = wave.z * multiplier;
    float wavelength = wave.w;
    
    float k = 2.0 * PI / wavelength;
    float c = sqrt(9.8 / k);
    
    vec2 d = normalize(wave.xy);
    float f = k * (dot(d, p.xz) - c * time * time_scale);
    float a = steepness / k;

    return vec3(
        d.x * (a * cos(f)),
        a * sin(f),
        d.y * (a * cos(f))
    );
}

// --- NEU: Hilfsfunktion, um den Code aufgeräumt zu halten ---
vec3 get_wave_displacement(vec3 p, float time, float multiplier) {
    vec3 d = vec3(0.0);
    d += gerstner_wave(wave_a, p, time, multiplier);
    d += gerstner_wave(wave_b, p, time, multiplier);
    d += gerstner_wave(wave_c, p, time, multiplier);
    return d;
}

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    vec2 noise_uv = world_pos.xz * noise_scale + (TIME * 0.01);
    float noise_val = texture(wave_noise, noise_uv).r; 
    float height_multiplier = mix(0.3, 1.5, noise_val);
    
    // 1. Die Wellen-Verschiebung am aktuellen Punkt
    vec3 displacement = get_wave_displacement(world_pos, TIME, height_multiplier);

    // --- NEU: BERECHNUNG DER WEICHEN OBERFLÄCHE ---
    // 2. Wir tasten das Wasser 10cm weiter auf der X- und Z-Achse ab
    float e = 0.1; 
    vec3 px = world_pos + vec3(e, 0.0, 0.0);
    vec3 pz = world_pos + vec3(0.0, 0.0, e);

    vec3 displacement_x = get_wave_displacement(px, TIME, height_multiplier);
    vec3 displacement_z = get_wave_displacement(pz, TIME, height_multiplier);

    // Die echten 3D-Positionen der drei Punkte
    vec3 p0 = world_pos + displacement;
    vec3 p1 = px + displacement_x;
    vec3 p2 = pz + displacement_z;

    // Das Kreuzprodukt der benachbarten Punkte ergibt die perfekte, weiche Krümmung (Normale)
    vec3 smooth_normal = normalize(cross(p2 - p0, p1 - p0));
    
    // Die weiche Krümmung an Godots Beleuchtungssystem übergeben
    NORMAL = (inverse(MODEL_MATRIX) * vec4(smooth_normal, 0.0)).xyz;

    // 3. LOD Fade anwenden
    float dist = distance(world_pos, CAMERA_POSITION_WORLD);
    float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
    displacement *= fade;
	
	horizon_fade_var = smoothstep(fade_start, fade_end, dist);

    wave_height_var = displacement.y;

    vec3 new_world_pos = world_pos + displacement;
    VERTEX = (inverse(MODEL_MATRIX) * vec4(new_world_pos, 1.0)).xyz;
}

void fragment() {
    
    float depth_mix = smoothstep(deep_level, 0.0, wave_height_var);
    vec3 albedo_color = mix(color_deep, color_shallow, depth_mix);
    
    float foam_mix = smoothstep(foam_level * 0.8, foam_level, wave_height_var);
    albedo_color = mix(albedo_color, color_foam, foam_mix);
    
	albedo_color = mix(albedo_color, horizon_color, horizon_fade_var);
	
    ALBEDO = albedo_color;
    // ROUGHNESS leicht erhöht (0.1), damit das weiche Wasser nicht wie eine Plastikfolie aussieht
    ROUGHNESS = 0.1; 
    SPECULAR = 0.5;
}