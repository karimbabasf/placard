# Blender scene for the launch video, frames 1-205 (60 fps): a wall of 24 Terminal windows, strips slam on,
# the hero goes NEEDS YOU, the camera whips into its strip. Run: blender -b -P scene.py -- <tex dir> <out dir>
import bpy, math, random, sys, os

argv = sys.argv[sys.argv.index("--") + 1:]
TEX, OUT = os.path.abspath(argv[0]), os.path.abspath(argv[1])
os.makedirs(OUT, exist_ok=True)
N, HERO, COLS = 24, 14, 6
PX, PY = 8.8, 5.9
END = 205
rnd = random.Random(7)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
sc.render.fps = 60
sc.frame_start, sc.frame_end = 1, END
sc.render.use_motion_blur = True
sc.render.motion_blur_shutter = 0.6
sc.eevee.taa_render_samples = 48
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
sc.render.image_settings.file_format = "PNG"
sc.render.filepath = os.path.join(OUT, "")
world = bpy.data.worlds.new("w"); sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.004, 0.004, 0.006, 1)

# interpolation of the segment that arrives at each key; applied after all keys exist (the prefs default is ignored in -b)
WANT = {}
def key(target, path, frame, value, interp="BEZIER"):
    setattr(target, path, value)
    target.keyframe_insert(path, frame=frame)
    full = path if isinstance(target, bpy.types.ID) else f"{target.path_from_id()}.{path}"
    WANT[(target.id_data.name, full, frame)] = interp

def fcurves(idb):
    ad = idb.animation_data
    if not ad or not ad.action:
        return []
    from bpy_extras import anim_utils
    cb = anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot)
    return list(cb.fcurves) if cb else []

def apply_interp():
    for idb in list(bpy.data.objects) + [m.node_tree for m in bpy.data.materials] + list(bpy.data.node_groups):
        for fc in fcurves(idb):
            kps = sorted(fc.keyframe_points, key=lambda k: k.co.x)
            for k in range(1, len(kps)):
                it = WANT.get((idb.name, fc.data_path, int(round(kps[k].co.x))), "BEZIER")
                kps[k - 1].interpolation = it
                if it == "EXPO":
                    kps[k - 1].easing = "EASE_IN"

def img(name):
    return bpy.data.images.load(os.path.join(TEX, name))

def plane(name, w, h):
    me = bpy.data.meshes.new(name)
    me.from_pydata([(-w / 2, -h / 2, 0), (w / 2, -h / 2, 0), (w / 2, h / 2, 0), (-w / 2, h / 2, 0)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new()
    for i, c in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)]):
        uv.data[i].uv = c
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    return ob

# shared clock for the working sweep
clock = bpy.data.node_groups.new("Clock", "ShaderNodeTree")
clock.interface.new_socket("t", in_out="OUTPUT", socket_type="NodeSocketFloat")
cv = clock.nodes.new("ShaderNodeValue")
go = clock.nodes.new("NodeGroupOutput")
clock.links.new(cv.outputs[0], go.inputs[0])
key(cv.outputs[0], "default_value", 1, 0.0, "LINEAR")
key(cv.outputs[0], "default_value", END, float(END), "LINEAR")

def material(name, images, seq=None):
    """Emission of a stack of images; mix sockets pick which one shows. Returns (mat, mix inputs, strength input, alpha mult)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.surface_render_method = "DITHERED"
    nt = m.node_tree; n = nt.nodes; L = nt.links
    n.clear()
    outn = n.new("ShaderNodeOutputMaterial")
    texs = []
    for im in images:
        t = n.new("ShaderNodeTexImage"); t.image = im; t.interpolation = "Cubic"; texs.append(t)
    if seq:
        t = n.new("ShaderNodeTexImage"); t.image = seq[0]
        t.image_user.frame_duration = seq[1]; t.image_user.frame_start = seq[2]
        t.image_user.use_cyclic = True; t.image_user.use_auto_refresh = True
        texs.append(t)
    col = texs[0].outputs["Color"]
    mixes = []
    for t in texs[1:]:
        mx = n.new("ShaderNodeMix"); mx.data_type = "RGBA"
        L.new(col, mx.inputs[6]); L.new(t.outputs["Color"], mx.inputs[7])
        mx.inputs[0].default_value = 0
        col = mx.outputs[2]; mixes.append(mx.inputs[0])
    em = n.new("ShaderNodeEmission")
    L.new(col, em.inputs["Color"]); em.inputs["Strength"].default_value = 0
    amul = n.new("ShaderNodeMath"); amul.operation = "MULTIPLY"; amul.inputs[1].default_value = 1
    L.new(texs[0].outputs["Alpha"], amul.inputs[0])
    tr = n.new("ShaderNodeBsdfTransparent")
    mix = n.new("ShaderNodeMixShader")
    L.new(amul.outputs[0], mix.inputs[0]); L.new(tr.outputs[0], mix.inputs[1]); L.new(em.outputs[0], mix.inputs[2])
    L.new(mix.outputs[0], outn.inputs["Surface"])
    return m, mixes, em.inputs["Strength"], amul.inputs[1], (n, L, col, em)

def add_sweep(parts):
    n, L, col, em = parts
    g = n.new("ShaderNodeGroup"); g.node_tree = clock
    oi = n.new("ShaderNodeObjectInfo")
    tc = n.new("ShaderNodeTexCoord"); sep = n.new("ShaderNodeSeparateXYZ")
    L.new(tc.outputs["UV"], sep.inputs[0])
    m1 = n.new("ShaderNodeMath"); m1.operation = "MULTIPLY_ADD"
    L.new(g.outputs[0], m1.inputs[0]); m1.inputs[1].default_value = 0.011; L.new(oi.outputs["Random"], m1.inputs[2])
    fr = n.new("ShaderNodeMath"); fr.operation = "FRACT"; L.new(m1.outputs[0], fr.inputs[0])
    pos = n.new("ShaderNodeMath"); pos.operation = "MULTIPLY_ADD"
    L.new(fr.outputs[0], pos.inputs[0]); pos.inputs[1].default_value = 2.0; pos.inputs[2].default_value = -0.5
    d = n.new("ShaderNodeMath"); d.operation = "SUBTRACT"; L.new(sep.outputs[0], d.inputs[0]); L.new(pos.outputs[0], d.inputs[1])
    a = n.new("ShaderNodeMath"); a.operation = "ABSOLUTE"; L.new(d.outputs[0], a.inputs[0])
    s = n.new("ShaderNodeMapRange"); s.inputs[1].default_value = 0; s.inputs[2].default_value = 0.16
    s.inputs[3].default_value = 0.35; s.inputs[4].default_value = 0
    L.new(a.outputs[0], s.inputs[0])
    add = n.new("ShaderNodeMix"); add.data_type = "RGBA"; add.blend_type = "ADD"
    L.new(s.outputs[0], add.inputs[0]); L.new(col, add.inputs[6]); add.inputs[7].default_value = (1, 1, 1, 1)
    L.new(add.outputs[2], em.inputs["Color"])

# slam order: accelerating, hero lands mid-way as WORKING
order = [i for i in range(N) if i != HERO]
rnd.shuffle(order)
order.insert(9, HERO)
times = {w: round(58 + 84 * (k / (N - 1)) ** 0.62) for k, w in enumerate(order)}
NEEDS = 152

xmas = bpy.data.images.load(os.path.join(TEX, "xmas_0001.png")); xmas.source = "SEQUENCE"
wins = {}
for i in range(N):
    r, c = divmod(i, COLS)
    x, y = (c - (COLS - 1) / 2) * PX, ((4 - 1) / 2 - r) * PY
    z = rnd.uniform(-0.7, 0.7) if i != HERO else 0.4
    ob = plane(f"win{i}", 8, 5)
    ob.location = (x, y, z)
    ob.rotation_euler = (rnd.uniform(-0.03, 0.03), rnd.uniform(-0.04, 0.04), rnd.uniform(-0.012, 0.012))
    seq = (xmas, 48, NEEDS) if i == HERO else None
    m, mixes, stren, _, _ = material(f"mw{i}", [img(f"w{i}_a.png"), img(f"w{i}_b.png")], seq)
    ob.data.materials.append(m)
    # fade up from black, a sweep from the right
    delay = int((COLS - 1 - c) * 5 + r * 3)
    key(stren, "default_value", 1, 0.0)
    key(stren, "default_value", 8 + delay, 0.0)
    key(stren, "default_value", 34 + delay, 0.85)
    t = times[i]
    key(mixes[0], "default_value", 1, 0.0, "CONSTANT")
    key(mixes[0], "default_value", t, 1.0, "CONSTANT")
    key(stren, "default_value", t - 1, 0.85)
    key(stren, "default_value", t, 1.9)
    key(stren, "default_value", t + 12, 1.0)
    # impact kick
    key(ob, "location", t - 1, (x, y, z))
    key(ob, "location", t + 1, (x, y, z - 0.25))
    key(ob, "location", t + 9, (x, y, z))
    if i == HERO:
        key(mixes[1], "default_value", 1, 0.0, "CONSTANT")
        key(mixes[1], "default_value", NEEDS, 1.0, "CONSTANT")
        key(stren, "default_value", NEEDS - 1, 1.0)
        key(stren, "default_value", NEEDS, 2.4)
        key(stren, "default_value", NEEDS + 14, 1.15)
    else:
        key(stren, "default_value", NEEDS + 2, 1.0)
        key(stren, "default_value", NEEDS + 22, 0.28)
    # the strip
    st = plane(f"strip{i}", 7.08, 0.32)
    st.parent = ob
    st.rotation_euler = (0, 0, 0)
    imgs = [img(f"s{i}.png")] + ([img(f"s{i}_needs.png")] if i == HERO else [])
    sm, smix, sstren, salpha, parts = material(f"ms{i}", imgs)
    add_sweep(parts)
    st.data.materials.append(sm)
    home = (0.46, 2.3, 0.012)
    key(st, "location", t - 7, (home[0] + 0.3, home[1] + 0.5, 3.2))
    key(st, "location", t, home, "QUAD")
    key(st, "scale", t - 7, (1.5, 1.5, 1))
    key(st, "scale", t, (1, 1, 1), "QUAD")
    key(st, "scale", t + 2, (1.04, 1.15, 1))
    key(st, "scale", t + 6, (1, 1, 1))
    key(salpha, "default_value", 1, 0.0, "CONSTANT")
    key(salpha, "default_value", t - 7, 1.0, "CONSTANT")
    key(sstren, "default_value", 1, 1.0)
    key(sstren, "default_value", t, 2.6)
    key(sstren, "default_value", t + 10, 1.05)
    if i == HERO:
        key(smix[0], "default_value", 1, 0.0, "CONSTANT")
        key(smix[0], "default_value", NEEDS, 1.0, "CONSTANT")
    wins[i] = (x, y, z)

# camera: slow push across the wall, then a whip into the hero strip
cam_data = bpy.data.cameras.new("cam"); cam_data.lens = 32
cam_data.dof.use_dof = True; cam_data.dof.aperture_fstop = 1.6
cam = bpy.data.objects.new("cam", cam_data); sc.collection.objects.link(cam); sc.camera = cam
tgt = bpy.data.objects.new("tgt", None); sc.collection.objects.link(tgt)
con = cam.constraints.new("TRACK_TO"); con.target = tgt; con.track_axis = "TRACK_NEGATIVE_Z"; con.up_axis = "UP_Y"
cam_data.dof.focus_object = tgt
hx, hy, hz = wins[HERO]
sx, sy = hx + 0.46, hy + 2.3
key(cam, "location", 1, (17, -24, 33))
key(tgt, "location", 1, (5, 1, 0))
key(cam, "location", 140, (7, -16, 25))
key(tgt, "location", 140, (-1, -1, 0))
key(cam, "location", NEEDS + 10, (hx + 3, hy - 9, 16))
key(tgt, "location", NEEDS + 10, (hx, hy + 0.8, hz))
key(cam, "location", NEEDS + 26, (sx + 0.6, sy - 2.6, hz + 5), "SINE")
key(tgt, "location", NEEDS + 26, (sx, sy, hz), "SINE")
key(cam, "location", END, (sx - 1.0, sy, hz + 0.3), "EXPO")
key(tgt, "location", END, (sx - 1.0, sy + 0.001, hz), "EXPO")
apply_interp()

if "--render" in argv:
    bpy.ops.render.render(animation=True)
else:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "launch.blend"))
    for f in [int(a) for a in argv[2:] if a.isdigit()]:
        sc.frame_set(f); sc.render.filepath = os.path.join(OUT, f"still_{f:04d}.png")
        bpy.ops.render.render(write_still=True)
