shader_type canvas_item;

uniform vec4 backgroundcolor : source_color = vec4(0.1, 0.2, 0.8, 1.0);
uniform vec4 voxthresholdcolor : source_color = vec4(0.602, 0.43, 0.508, 1.0);
uniform vec4 voxchunkmaxcolor : source_color = vec4(0.8, 0.8, 0.08, 0.2);
uniform vec4 voxwavecolor : source_color = vec4(0.8,0.8,0.9,1.0);

uniform float voxthreshhold = 0.2;
uniform float chunkmax = 0.0;
uniform float chunkmaxpersist = 0.0;
uniform float speechnoiseprobability = 0.0;
uniform bool chunktexenabled = false;
uniform sampler2D chunktexture : repeat_enable;

void fragment() {
	if (UV.x > voxthreshhold)
		COLOR = backgroundcolor;
	else if ((chunkmax != 0.0) || chunktexenabled)
		COLOR = voxthresholdcolor;

	if ((UV.x < chunkmaxpersist) && (UV.y > 0.1) && (UV.y < 0.9))
		COLOR.rgb = mix(COLOR.rgb, voxchunkmaxcolor.rgb, voxchunkmaxcolor.a);

	if ((speechnoiseprobability > 0.0) && (UV.y > 0.9) && (abs(UV.x - 0.5) < speechnoiseprobability*0.5)) {
		COLOR.rgb = vec3(1.0,1.0,0);
	}

	float d;
	if (chunktexenabled) {
		vec4 v = texture(chunktexture, UV);
		d = UV.y*2.0 - v.r*4.0 - 1.0;
	} else {
		d = (UV.x < chunkmax ? UV.y - 0.5 : 1.0);
	}
	if (abs(d) < 0.1)
		COLOR = voxwavecolor;
}
