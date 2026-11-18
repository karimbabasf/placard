# Blender scene for the launch video, frames 1-510 at 60 fps: five Terminal windows on a desk, near frontal.
# Strips ease on one by one, two agents finish and dim, infra needs you and goes Christmas, the camera leans in.
# Run: blender -b -P scene.py -- <tex dir> <out dir> [--render | frame numbers for stills]
import bpy, os, sys

argv = sys.argv[sys.argv.index("--") + 1:]
TEX, OUT = os.path.abspath(argv[0]), os.path.abspath(argv[1])
os.makedirs(OUT, exist_ok=True)
END, HERO = 510, 3
LABEL = [150, 182, 214, 246, 278]       # api, web, docs, infra, db
TURN = {1: 345, 4: 372}                 # web and db finish
NEEDS = 412

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
sc.render.fps = 60
sc.frame_start, sc.frame_end = 1, END
sc.render.use_motion_blur = True
sc.render.motion_blur_shutter = 0.5
sc.eevee.taa_render_samples = 48
sc.view_settings.view_transform = "Standard"
sc.render.image_settings.file_format = "PNG"
sc.render.filepath = os.path.join(OUT, "")
world = bpy.data.worlds.new("w"); sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.006, 0.006, 0.008, 1)

# interpolation of the segment arriving at each key, applied after all keys exist (-b ignores the prefs default)
WANT = {}
def key(target, path, frame, value, interp="BEZIER"):
    setattr(target, path, value)
    target.keyframe_insert(path, frame=frame)
    full = path if isinstance(target, bpy.types.ID) else f"{target.path_from_id()}.{path}"
    WANT[(target.id_data.name, full, frame)] = interp

def apply_interp():
    from bpy_extras import anim_utils
    for idb in list(bpy.data.objects) + [m.node_tree for m in bpy.data.materials] + list(bpy.data.node_groups):
        ad = idb.animation_data
        if not ad or not ad.action:
            continue
        cb = anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot)
        for fc in (cb.fcurves if cb else []):
            kps = sorted(fc.keyframe_points, key=lambda k: k.co.x)
            for k in range(1, len(kps)):
                kps[k - 1].interpolation = WANT.get((idb.name, fc.data_path, int(round(kps[k].co.x))), "BEZIER")

def img(name):
    return bpy.data.images.load(os.path.join(TEX, name))

def plane(name, w, h, parent=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([(-w / 2, -h / 2, 0), (w / 2, -h / 2, 0), (w / 2, h / 2, 0), (-w / 2, h / 2, 0)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new()
    for i, c in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)]):
        uv.data[i].uv = c
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    ob.parent = parent
    return ob

clock = bpy.data.node_groups.new("Clock", "ShaderNodeTree")
clock.interface.new_socket("t", in_out="OUTPUT", socket_type="NodeSocketFloat")
cv = clock.nodes.new("ShaderNodeValue"); go = clock.nodes.new("NodeGroupOutput")
clock.links.new(cv.outputs[0], go.inputs[0])
key(cv.outputs[0], "default_value", 1, 0.0, "LINEAR")
key(cv.outputs[0], "default_value", END, float(END), "LINEAR")

def material(name, images, seq=None, sweep=False):
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
        t = n.new("ShaderNodeTexImage"); t.image = seq[0]; t.interpolation = "Cubic"
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
    if sweep:
        g = n.new("ShaderNodeGroup"); g.node_tree = clock
        oi = n.new("ShaderNodeObjectInfo"); tc = n.new("ShaderNodeTexCoord"); sep = n.new("ShaderNodeSeparateXYZ")
        L.new(tc.outputs["UV"], sep.inputs[0])
        m1 = n.new("ShaderNodeMath"); m1.operation = "MULTIPLY_ADD"
        L.new(g.outputs[0], m1.inputs[0]); m1.inputs[1].default_value = 0.008; L.new(oi.outputs["Random"], m1.inputs[2])
        fr = n.new("ShaderNodeMath"); fr.operation = "FRACT"; L.new(m1.outputs[0], fr.inputs[0])
        pos = n.new("ShaderNodeMath"); pos.operation = "MULTIPLY_ADD"
        L.new(fr.outputs[0], pos.inputs[0]); pos.inputs[1].default_value = 2.2; pos.inputs[2].default_value = -0.6
        d = n.new("ShaderNodeMath"); d.operation = "SUBTRACT"; L.new(sep.outputs[0], d.inputs[0]); L.new(pos.outputs[0], d.inputs[1])
        a = n.new("ShaderNodeMath"); a.operation = "ABSOLUTE"; L.new(d.outputs[0], a.inputs[0])
        s = n.new("ShaderNodeMapRange"); s.inputs[1].default_value = 0; s.inputs[2].default_value = 0.14
        s.inputs[3].default_value = 0.22; s.inputs[4].default_value = 0
        L.new(a.outputs[0], s.inputs[0])
        # the sweep only shows while working: scale it by an animated amount
        amt = n.new("ShaderNodeMath"); amt.operation = "MULTIPLY"; amt.inputs[1].default_value = 1
        L.new(s.outputs[0], amt.inputs[0])
        add = n.new("ShaderNodeMix"); add.data_type = "RGBA"; add.blend_type = "ADD"
        L.new(amt.outputs[0], add.inputs[0]); L.new(col, add.inputs[6]); add.inputs[7].default_value = (1, 1, 1, 1)
        col = add.outputs[2]
        sweep = amt.inputs[1]
    L.new(col, em.inputs["Color"]); em.inputs["Strength"].default_value = 1
    amul = n.new("ShaderNodeMath"); amul.operation = "MULTIPLY"; amul.inputs[1].default_value = 1
    L.new(texs[0].outputs["Alpha"], amul.inputs[0])
    tr = n.new("ShaderNodeBsdfTransparent"); mix = n.new("ShaderNodeMixShader")
    L.new(amul.outputs[0], mix.inputs[0]); L.new(tr.outputs[0], mix.inputs[1]); L.new(em.outputs[0], mix.inputs[2])
    L.new(mix.outputs[0], outn.inputs["Surface"])
    return m, mixes, em.inputs["Strength"], amul.inputs[1], sweep

# desk layout: back row three, front row two in front, every title bar visible
POS = [(-8.3, 2.3, 0.0), (0.0, 2.6, 0.15), (8.3, 2.2, 0.05), (-4.2, -2.5, 0.9), (4.4, -2.3, 0.7)]
# the desk stands up as a wall facing -Y, so the camera keeps a clean world-Z up axis
desk = bpy.data.objects.new("desk", None); sc.collection.objects.link(desk)
desk.rotation_euler = (1.5707963, 0, 0)
def D(v):
    return (v[0], -v[2], v[1])
shadow = img("shadow.png")
xmas = img("xmas_0001.png"); xmas.source = "SEQUENCE"
for i, (x, y, z) in enumerate(POS):
    win = plane(f"win{i}", 8, 5, desk)
    win.location = (x, y, z)
    seq = (xmas, 48, NEEDS) if i == HERO else None
    m, mixes, stren, _, _ = material(f"mw{i}", [img(f"w{i}_a.png"), img(f"w{i}_b.png")], seq)
    win.data.materials.append(m)
    sh = plane(f"sh{i}", 10.4, 6.5, win); sh.location = (0, -0.35, -0.04)
    sm, _, sstr, _, _ = material(f"msh{i}", [shadow])
    sh.data.materials.append(sm)
    sstr.default_value = 0
    t = LABEL[i]
    # windows fade up together, gently staggered
    key(stren, "default_value", 1, 0.0)
    key(stren, "default_value", 4 + i * 4, 0.0)
    key(stren, "default_value", 40 + i * 4, 1.0)
    # body takes the group tint as the strip lands
    key(mixes[0], "default_value", t, 0.0)
    key(mixes[0], "default_value", t + 20, 1.0)
    # strip: fades in while it settles down onto the title bar
    st = plane(f"strip{i}", 6.88, 0.44, win)
    imgs = [img(f"s{i}_work.png"), img(f"s{i}_turn.png")] + ([img(f"s{i}_needs.png")] if i == HERO else [])
    stm, smix, _, salpha, sweep = material(f"ms{i}", imgs, sweep=True)
    st.data.materials.append(stm)
    home = (0.48, 2.21, 0.01)
    key(st, "location", t, (home[0], home[1] + 0.22, 0.25))
    key(st, "location", t + 22, home)
    key(salpha, "default_value", t, 0.0)
    key(salpha, "default_value", t + 16, 1.0)
    if i in TURN:
        key(smix[0], "default_value", TURN[i], 0.0)
        key(smix[0], "default_value", TURN[i] + 14, 1.0)
        key(sweep, "default_value", TURN[i], 1.0)
        key(sweep, "default_value", TURN[i] + 14, 0.0)
    if i == HERO:
        key(mixes[1], "default_value", 1, 0.0, "CONSTANT")
        key(mixes[1], "default_value", NEEDS, 1.0, "CONSTANT")
        key(smix[1], "default_value", NEEDS - 1, 0.0)
        key(smix[1], "default_value", NEEDS + 6, 1.0)
        key(sweep, "default_value", NEEDS, 1.0)
        key(sweep, "default_value", NEEDS + 6, 0.0)
    else:
        key(stren, "default_value", NEEDS + 4, 1.0)
        key(stren, "default_value", NEEDS + 34, 0.45)

# camera: a slow drift, then a calm lean toward infra when it needs you
cd = bpy.data.cameras.new("cam"); cd.lens = 50
cd.dof.use_dof = True; cd.dof.aperture_fstop = 4.0
cam = bpy.data.objects.new("cam", cd); sc.collection.objects.link(cam); sc.camera = cam
tgt = bpy.data.objects.new("tgt", None); sc.collection.objects.link(tgt)
con = cam.constraints.new("TRACK_TO"); con.target = tgt; con.track_axis = "TRACK_NEGATIVE_Z"; con.up_axis = "UP_Y"
cd.dof.focus_object = tgt
key(cam, "location", 1, D((1.6, -3.0, 45.0)))
key(tgt, "location", 1, D((0.4, 2.2, 0.0)))
key(cam, "location", NEEDS, D((-0.8, -2.4, 42.0)), "LINEAR")
key(tgt, "location", NEEDS, D((0.0, 2.0, 0.3)), "LINEAR")
hx, hy, hz = POS[HERO]
key(cam, "location", 492, D((hx + 0.9, hy - 2.8, 29.0)))
key(tgt, "location", 492, D((hx + 0.6, hy + 2.4, hz)))
key(cam, "location", END, D((hx + 0.85, hy - 2.7, 28.4)))
key(tgt, "location", END, D((hx + 0.6, hy + 2.4, hz)))
apply_interp()

if "--render" in argv:
    bpy.ops.render.render(animation=True)
else:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "launch.blend"))
    for f in [int(a) for a in argv[2:] if a.isdigit()]:
        sc.frame_set(f); sc.render.filepath = os.path.join(OUT, f"still_{f:04d}.png")
        bpy.ops.render.render(write_still=True)
