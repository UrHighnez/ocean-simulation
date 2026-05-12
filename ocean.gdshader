shader_type spatial;

uniform vec3 color_deep : source_color = vec3(0.05, 0.15, 0.3);
uniform vec3 color_shallow : source_color = vec3(0.1, 0.4, 0.6);
uniform vec3 color_foam : source_color = vec3(0.9, 0.9, 0.95);
uniform vec3 horizon_color : source_color = vec3(0.5, 0.6, 0.7);

uniform float foam_level = 0.08;
uniform float deep_level = -0.05;
uniform float time_scale = 0.1;

uniform vec4 wave_a = vec4(5.1, 0.3, 1.7, 52);
uniform vec4 wave_b = vec4(0.43, 0.31, 0.077, 3.1);
uniform vec4 wave_c = vec4(-0.12, 0.13, 0.054, 2.3);

uniform float fade_start = 30.0;
uniform float fade_end = 80.0;

uniform sampler2D wave_noise;
uniform float noise_scale = 0.02;

uniform sampler2D foam_noise; // Die Textur für die Risse im Schaum
uniform float foam_noise_scale = 0.2; // Wie klein/fein die Risse sind
uniform float foam_distortion = 0.08; // Wie stark der Rand zerfetzt wird

varying float wave_height_var;
varying float horizon_fade_var;
varying vec2 world_xz_var; 

vec3 gerstner_wave(vec4 wave, vec3 p, float time, float multiplier, float phase_offset) {
    float steepness = wave.z * multiplier;
    float wavelength = wave.w;
    
    float k = 2.0 * PI / wavelength;
    float c = sqrt(9.8 / k);
    vec2 d = normalize(wave.xy);
    
    float f = k * (dot(d, p.xz) - c * time * time_scale) + phase_offset;
    float a = steepness / k;

    return vec3(
        d.x * (a * cos(f)),
        a * sin(f),
        d.y * (a * cos(f))
    );
}

vec3 get_wave_displacement(vec3 p, float time, float multiplier, float phase_offset) {
    vec3 d = vec3(0.0);
    // Wir multiplizieren die Zeit für Welle B und C minimal (z.B. * 1.1), 
    // damit sie nicht für immer synchron mit Welle A laufen.
    d += gerstner_wave(wave_a, p, time, multiplier, phase_offset);
    d += gerstner_wave(wave_b, p, time * 1.1, multiplier, phase_offset * 1.2);
    d += gerstner_wave(wave_c, p, time * 0.9, multiplier, phase_offset * 1.5);
    return d;
}

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_xz_var = world_pos.xz;
    
    vec2 noise_uv = world_pos.xz * noise_scale + (TIME * 0.01);
    float noise_val = texture(wave_noise, noise_uv).r; 
    
    float height_multiplier = mix(0.3, 1.5, noise_val);
    
    // Wir wandeln den Noise (0.0 bis 1.0) in eine Verzerrung um (-0.5 bis 0.5) 
    // und multiplizieren sie z.B. mit 3.0, um die Rillen stark zu verbiegen.
    float phase_warp = (noise_val - 0.5) * 3.0; 
    
    // Wir übergeben den Warp an die Verschiebungs-Berechnung
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
        
    // 1. Noise-Textur auslesen. Wir addieren TIME, damit der Schaum dynamisch "blubbert".
    float f_noise = texture(foam_noise, world_xz_var * foam_noise_scale + (TIME * 0.05)).r;
    
    // 2. Den Noise in eine Verzerrung umwandeln (von -0.5 bis +0.5)
    float edge_distortion = (f_noise - 0.5) * foam_distortion;
    
    // 3. Den Schwellenwert (foam_level) mit der Verzerrung manipulieren
    float foam_limit = foam_level + edge_distortion;
    
    // 4. Die scharfe, aber nun gezackte Kante zeichnen
    float foam_mix = smoothstep(foam_limit - 0.02, foam_limit, wave_height_var);
    
    albedo_color = mix(albedo_color, color_foam, foam_mix);
    
    // Horizont
    albedo_color = mix(albedo_color, horizon_color, horizon_fade_var);
    
    ALBEDO = albedo_color;
    ROUGHNESS = 0.1; 
    SPECULAR = 0.5;
}