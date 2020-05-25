// This shader is used to bake the global albedo map.
// It exposes a subset of the main shader API, so uniform names were not modified.

shader_type spatial;

uniform sampler2D u_terrain_colormap : hint_albedo;
uniform sampler2D u_terrain_splat_index_map;
uniform sampler2D u_terrain_splat_weight_map;

uniform sampler2DArray u_ground_albedo_bump_array : hint_albedo;

// TODO Have UV scales for each texture in an array?
uniform float u_ground_uv_scale;
// Keep depth blending because it has a high effect on the final result
uniform bool u_depth_blending = true;


vec3 get_depth_blended_weights(vec3 splat, vec3 bumps) {
	float dh = 0.2;

	vec3 h = bumps + splat;

	// TODO Keep improving multilayer blending, there are still some edge cases...
	// Mitigation: nullify layers with near-zero splat
	h *= smoothstep(0, 0.05, splat);

	vec3 d = h + dh;
	d.r -= max(h.g, h.b);
	d.g -= max(h.r, h.b);
	d.b -= max(h.g, h.r);

	vec3 w = clamp(d, 0, 1);
	// Had to normalize, since this approach does not preserve components summing to 1
	return w / (w.x + w.y + w.z);
}

void vertex() {
	vec4 wpos = WORLD_MATRIX * vec4(VERTEX, 1);
	vec2 cell_coords = wpos.xz;

	// Normalized UV
	UV = (cell_coords / vec2(textureSize(u_terrain_splat_index_map, 0)));
}

void fragment() {
	vec4 tint = texture(u_terrain_colormap, UV);
	vec4 tex_splat_indexes = texture(u_terrain_splat_index_map, UV);
	vec4 tex_splat_weights = texture(u_terrain_splat_weight_map, UV);
	// TODO Can't use texelFetch!
	// https://github.com/godotengine/godot/issues/31732
	
	vec3 splat_indexes = tex_splat_indexes.rgb * 255.0;

	// Get bump at normal resolution so depth blending is accurate
	vec2 ground_uv = UV / u_ground_uv_scale;
	vec4 ab0 = texture(u_ground_albedo_bump_array, vec3(ground_uv, splat_indexes.x));
	vec4 ab1 = texture(u_ground_albedo_bump_array, vec3(ground_uv, splat_indexes.y));
	vec4 ab2 = texture(u_ground_albedo_bump_array, vec3(ground_uv, splat_indexes.z));

	vec3 splat_weights = vec3(
		tex_splat_weights.r, 
		tex_splat_weights.g,
		1.0 - tex_splat_weights.r - tex_splat_weights.g
	);
	
	// TODO An #ifdef macro would be nice! Or copy/paste everything in a different shader...
	if (u_depth_blending) {
		splat_weights = get_depth_blended_weights(splat_weights, vec3(ab0.a, ab1.a, ab2.a));
	}

	ALBEDO = tint.rgb * (
		  ab0.rgb * splat_weights.x 
		+ ab1.rgb * splat_weights.y
		+ ab2.rgb * splat_weights.z
	);
}