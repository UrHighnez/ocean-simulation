shader_type spatial;

// 1. Die drei Farben für unser Wasser
uniform vec3 color_deep : source_color = vec3(0.05, 0.15, 0.3);   // Dunkles Tiefblau (Wellentäler)
uniform vec3 color_shallow : source_color = vec3(0.1, 0.4, 0.6);  // Normales Ozeanblau (Mitte)
uniform vec3 color_foam : source_color = vec3(0.9, 0.9, 0.95);    // Weiß/Schaum (Wellenspitzen)

// 2. Schwellenwerte: Wo beginnen Tiefblau und Schaum? (Im Inspektor anpassbar)
uniform float foam_level = 0.5;  // Ab welcher Höhe (Y) der Schaum beginnt
uniform float deep_level = -0.2; // Ab welcher Tiefe (Y) das Wasser dunkel wird

uniform float time_scale = 0.5;

uniform vec4 wave_a = vec4(0.5, 0.0, 0.1, 5.0);
uniform vec4 wave_b = vec4(0.4, 0.3, 0.075, 3.0);
uniform vec4 wave_c = vec4(-0.1, 0.15, 0.05, 2.0);

// 3. VARYING: Diese Variable reicht die Höhe vom Vertex- zum Fragment-Shader durch
varying float wave_height_var;

vec3 gerstner_wave(vec4 wave, vec3 p, float time) {
    float steepness = wave.z;
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

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    vec3 displacement = vec3(0.0);
    displacement += gerstner_wave(wave_a, world_pos, TIME);
    displacement += gerstner_wave(wave_b, world_pos, TIME);
    displacement += gerstner_wave(wave_c, world_pos, TIME);

    // Wir speichern nur die Y-Verschiebung (die Auslenkung nach oben/unten) für die Farbe
    wave_height_var = displacement.y;

    // Der Fix gegen die "stacheligen" Polygone aus der vorherigen Antwort
    vec3 new_world_pos = world_pos + displacement;
    VERTEX = (inverse(MODEL_MATRIX) * vec4(new_world_pos, 1.0)).xyz;
}

void fragment() {
    // Der Low-Poly Trick
    vec3 normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
    NORMAL = normal;
    
    // --- FARBMISCHUNG ---
    // smoothstep(min, max, wert) liefert einen weichen Übergang zwischen 0.0 und 1.0
    
    // 1. Mische zwischen Tiefblau und Normalblau
    // Wenn das Wasser tief ist (deep_level), ist der Wert 0. Bei Höhe 0.0 ist der Wert 1.
    float depth_mix = smoothstep(deep_level, 0.0, wave_height_var);
    vec3 albedo_color = mix(color_deep, color_shallow, depth_mix);
    
    // 2. Mische den Schaum auf die Spitzen
    // Der Schaum beginnt etwas unterhalb des foam_levels (* 0.8) und ist bei foam_level deckend
    float foam_mix = smoothstep(foam_level * 0.8, foam_level, wave_height_var);
    albedo_color = mix(albedo_color, color_foam, foam_mix);
    
    // Weise die finale Farbe zu
    ALBEDO = albedo_color;
    ROUGHNESS = 0.0;
    SPECULAR = 0.5;
}