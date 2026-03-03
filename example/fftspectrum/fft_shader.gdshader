shader_type canvas_item;
render_mode blend_mix;

uniform vec4 backgroundcolor : source_color = vec4(0.6, 0.2, 0.8, 1.0);
uniform vec4 voxthresholdcolor : source_color = vec4(0.602, 0.43, 0.508, 1.0);
uniform vec4 voxchunkmaxcolor : source_color = vec4(0.1, 0.8, 0.08, 0.2);
uniform vec4 voxwavecolor : source_color = vec4(0.8,0.8,0.9,1.0);
uniform float fftgain = 1.0;

uniform sampler2D chunktexture : filter_nearest;

void fragment() {
	COLOR = voxthresholdcolor;
	float d;
	vec4 v = texture(chunktexture, vec2(UV.x*0.125, UV.y));
	float a = fftgain*sqrt(v.r*v.r + v.g*v.g);
	if (a < 1.0) {
		COLOR.r = a;
		COLOR.g = 0.0;
	} else {
		COLOR.g = a - 1.0;
		COLOR.r = 1.0 - COLOR.g*0.25;
	}
}
