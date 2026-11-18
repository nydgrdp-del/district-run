"""Run with Blender --background --python tools/make_assets.py.
Original mesh kit, all dimensions in metres. No third-party game assets.
"""
import bpy
import math
import random
from pathlib import Path
from mathutils import Vector

OUT = Path(__file__).resolve().parents[1] / 'client/assets'
OUT.mkdir(exist_ok=True)
random.seed(107)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, color, metal=0, rough=.7):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Metallic'].default_value = metal
    shader.inputs['Roughness'].default_value = rough
    return mat

M = {k: material(k,c,m,r) for k,c,m,r in [
 ('sand',(.67,.48,.30),0,.9), ('cream',(.86,.80,.65),0,.85),
 ('teal',(.06,.32,.31),.05,.5), ('red',(.58,.16,.09),0,.7),
 ('wood',(.30,.18,.10),0,.9), ('dark',(.035,.055,.065),.15,.65),
 ('glass',(.09,.25,.31),.5,.18), ('metal',(.36,.41,.41),.7,.35),
 ('gold',(.95,.65,.20),.3,.5), ('white',(.87,.88,.84),0,.65),
 ('rubber',(.02,.025,.026),0,.9), ('leaf',(.14,.30,.12),0,.9),
 ('leaf2',(.29,.44,.13),0,.8), ('skin',(.56,.33,.20),0,.85),
 ('cloth',(.08,.17,.22),0,.95), ('denim',(.15,.21,.23),0,.95),
 ('blue',(.07,.31,.66),.2,.4)]}

def coord(p): return (p[0],-p[2],p[1])
def finish(o, name, mat):
    o.name = name
    o.data.materials.append(M[mat])
    return o

def box(name,p,s,mat,bevel=.03):
    bpy.ops.mesh.primitive_cube_add(size=1, location=coord(p))
    o=bpy.context.object
    o.scale=(s[0],s[2],s[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    finish(o,name,mat)
    if bevel:
        mod=o.modifiers.new('Rounded edges','BEVEL');mod.width=bevel;mod.segments=2
        bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return o

def sphere(name,p,s,mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=1,location=coord(p))
    o=bpy.context.object;o.scale=(s[0],s[2],s[1]);finish(o,name,mat)
    for f in o.data.polygons:f.use_smooth=True
    return o

def cyl(name,p,r,depth,mat,vertices=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=depth,location=coord(p))
    o=bpy.context.object;finish(o,name,mat)
    for f in o.data.polygons:f.use_smooth=True
    return o

def beam(name,a,b,r,mat):
    av,bv=Vector(coord(a)),Vector(coord(b))
    o=cyl(name,((a[0]+b[0])/2,(a[1]+b[1])/2,(a[2]+b[2])/2),r,(bv-av).length,mat)
    o.rotation_euler=(bv-av).to_track_quat('Z','Y').to_euler()
    return o

def poly(name,vertices,faces,mat):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata([coord(p) for p in vertices],[],faces);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);finish(o,name,mat)
    return o

def text(name,body,p,size,mat):
    bpy.ops.object.text_add(location=coord(p))
    o=bpy.context.object;o.name=name;o.data.body=body;o.data.size=size
    o.data.align_x='CENTER';o.data.extrude=.008
    # Face toward +Z in game space.
    o.rotation_euler=(math.pi/2,0,0)
    o.data.materials.append(M[mat]);bpy.ops.object.convert(target='MESH')
    return o

def export(name,join=True):
    if join:
        for mat in M.values():
            objects=[o for o in bpy.context.scene.objects if o.type=='MESH' and mat.name in [m.name for m in o.data.materials]]
            if objects:
                bpy.ops.object.select_all(action='DESELECT')
                for o in objects:o.select_set(True)
                bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join()
                objects[0].name=mat.name
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(OUT/f'{name}.glb'),export_format='GLB',use_selection=True,
                              export_yup=True,export_animations=False)
    bpy.ops.object.delete(use_global=False)

def building(style):
    h=8.2 if style=='apartment' else 4.0
    wall='teal' if style=='police' else ('sand' if style=='house' else 'cream')
    box('foundation',(0,-.06,0),(12.5,.12,10.5),'sand')
    for x in [-6,6]:box('side wall',(x,h/2,0),(.3,h,10),wall)
    box('rear wall',(0,h/2,-5),(12,h,.3),wall)
    for x in [-3.7,3.7]:box('front facade',(x,h/2,5),(4.6,h,.3),wall)
    box('lintel',(0,3.5,5),(2.8,1,.3),wall)
    # Upper floor and roof cornices, with surface edges and drainage.
    box('roof',(0,h+.12,0),(12.65,.25,10.65),'cream')
    for x in [-6.25,6.25]:box('roof parapet',(x,h+.4,0),(.2,.5,10.5),wall)
    for z in [-5.2,5.2]:box('roof trim',(0,h+.4,z),(12.5,.5,.2),wall)
    for x in [-5.8,5.8]:
        cyl('drainpipe',(x,h/2,5.25),.06,h,'metal',10)
    levels=[1.8,5.8] if h>5 else [1.8]
    for y in levels:
        for x in [-4.2,4.2]:
            box('window frame',(x,y,5.19),(2.8,1.8,.18),'wood')
            box('window glass',(x,y,5.3),(2.55,1.55,.08),'glass')
            box('window mullion',(x,y,5.37),(.08,1.6,.08),'cream')
            box('window cross',(x,y,5.37),(2.6,.08,.08),'cream')
            box('window sill',(x,y-.95,5.35),(3,.15,.5),'cream')
            if style=='apartment':
                box('balcony',(x,y-.95,6.0),(3.4,.2,1.5),'cream')
                for k in range(9):beam('railing',(x-1.55+k*.39,y-.85,6.6),(x-1.55+k*.39,y,6.6),.025,'metal')
                beam('rail',(x-1.7,y,6.6),(x+1.7,y,6.6),.045,'metal')
    for x in [-1.5,1.5]:box('door frame',(x,1.5,5.2),(.16,3,.24),'wood')
    box('door frame',(0,3,5.2),(3.15,.18,.24),'wood')
    if style=='house':
        # Pitched tile roof is a real shaped mesh, not a placeholder cube.
        poly('gable roof',[(-6.5,h+.5,-5.5),(6.5,h+.5,-5.5),(0,h+3,-5.5),(-6.5,h+.5,5.5),(6.5,h+.5,5.5),(0,h+3,5.5)],
             [(0,1,2),(5,4,3),(0,3,5,2),(1,2,5,4),(0,1,4,3)],'red')
        for z in range(-5,6):
            beam('tile course',(-6.5,h+.5,z),(0,h+3,z),.035,'sand')
            beam('tile course',(0,h+3,z),(6.5,h+.5,z),.035,'sand')
    if style in ('shop','police'):
        sign='NIGHT MARKET' if style=='shop' else 'DISTRICT POLICE'
        box('sign board',(0,3.55,5.4),(10,.65,.2),'teal' if style=='shop' else 'dark')
        text('sign',sign,(0,3.3,5.56),.43,'gold' if style=='shop' else 'white')
        for i in range(10):
            o=box('canvas awning',(-5.4+i*1.2,2.92,5.9),(1.18,.07,1.3),'teal' if i%2 else 'cream')
            o.rotation_euler[0]=.15
    # Fully visible interior shelves, individual packs, till and counter.
    box('floor',(0,.025,0),(11.7,.05,9.7),'wood' if style=='house' else 'sand')
    if style=='shop':
        for x in [-4.7,4.7]:
            for y in [.5,1.1,1.7,2.3]:
                box('shelf',(x,y,-1),(1.3,.09,4.5),'metal')
                for j in range(8):
                    box('product',(x,y+.21,-2.9+j*.55),(.65,.35,.35),['red','teal','gold'][j%3],.03)
        box('checkout',(0,.55,-2),(3,1.1,.8),'teal')
        box('counter',(0,1.13,-2),(3.2,.12,1),'wood')
        box('register',(.5,1.35,-2),(.6,.34,.5),'dark')
        for x in [-3,3]:
            cyl('ceiling fan stem',(x,3.4,0),.05,.8,'metal')
            for a in [0,math.pi/2]:
                o=box('fan blade',(x,3.05,0),(2.0,.05,.22),'wood');o.rotation_euler[2]=a
    else:
        box('desk',(0,.7,-2),(3,1.4,1.3),'wood')
        box('desktop',(0,1.43,-2),(3.2,.12,1.5),'cream')
        box('screen',(.5,1.8,-2),(.7,.6,.12),'dark')
    export(style)

for style in ['shop','house','apartment','police']:building(style)

# Sedan: shaped body sections, windows, mirrors, lamps, bumpers and wheels.
sections=[(-2.2,.55,.82),(-1.85,.9,.95),(-.85,1.05,.96),(-.5,1.65,.77),(.8,1.65,.77),(1.35,1.05,.94),(2.1,.85,.88)]
verts=[]
for z,h,w in sections:verts.extend([(-w,.45,z),(w,.45,z),(-w,h,z),(w,h,z)])
faces=[(0,1,3,2)]
for i in range(len(sections)-1):
    a,b=i*4,(i+1)*4
    faces.extend([(a,b,b+2,a+2),(a+1,a+3,b+3,b+1),(a+2,b+2,b+3,a+3),(a,a+1,b+1,b)])
faces.append(tuple(range(len(verts)-4,len(verts))))
poly('sculpted body',verts,faces,'teal')
poly('windscreen',[(-.75,1.62,-.5),(.75,1.62,-.5),(.9,1.08,-.85),(-.9,1.08,-.85)],[(0,1,2,3)],'glass')
poly('rear screen',[(-.75,1.62,.8),(.75,1.62,.8),(.9,1.08,1.35),(-.9,1.08,1.35)],[(3,2,1,0)],'glass')
for side in [-1,1]:
    for a,b in [(-.48,.1),(.18,.78)]:
        poly('side window',[(side*.79,1.59,a),(side*.79,1.59,b),(side*.95,1.08,b+.15),(side*.95,1.08,a-.12)],[(0,1,2,3)],'glass')
    box('mirror',(side*1.08,1.16,-.55),(.25,.16,.32),'teal')
    for z in [-1.4,1.35]:
        o=cyl('tire',(side*.95,.48,z),.43,.25,'rubber',24);o.rotation_euler[1]=math.pi/2
        o=cyl('alloy wheel',(side*1.09,.48,z),.27,.03,'metal',16);o.rotation_euler[1]=math.pi/2
        for a in range(5):
            y=.48+math.sin(a*math.tau/5)*.17;zz=z+math.cos(a*math.tau/5)*.17
            beam('spoke',(side*1.12,.48,z),(side*1.12,y,zz),.035,'dark')
    box('headlamp',(side*.62,.8,-2.11),(.45,.18,.08),'white')
    box('taillamp',(side*.62,.75,2.09),(.4,.17,.08),'red')
    for z in [-.3,.6]:box('door handle',(side*.96,.97,z),(.06,.06,.2),'metal')
box('front bumper',(0,.5,-2.2),(1.8,.16,.12),'metal')
box('grille',(0,.72,-2.19),(.65,.18,.08),'dark')
box('plate',(0,.58,2.15),(.48,.2,.02),'white')
export('sedan')

# Segmented character with named pivot groups used by the client's gait controller.
def part(name,p,fn):
    before=set(bpy.context.scene.objects)
    fn()
    objs=list(set(bpy.context.scene.objects)-before)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join();o=objs[0];o.name=name
    bpy.context.scene.cursor.location=coord(p)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

part('Torso',(0,1.12,0),lambda:[sphere('jacket',(0,1.33,0),(.29,.35,.17),'cloth'),
 box('zipper',(0,1.34,-.17),(.025,.48,.03),'metal'),
 box('belt',(0,1.01,0),(.48,.08,.32),'dark'),
 box('backpack',(0,1.34,.24),(.45,.5,.23),'wood',.08),
 box('pocket',(.16,1.27,-.17),(.17,.19,.06),'denim')])
part('Head',(0,1.6,0),lambda:[sphere('face',(0,1.76,0),(.17,.23,.16),'skin'),
 sphere('nose',(0,1.76,-.16),(.045,.055,.055),'skin'),
 sphere('hair',(0,1.92,.01),(.18,.10,.17),'dark'),
 box('glasses',(0,1.81,-.15),(.29,.065,.06),'dark'),
 sphere('earL',(-.17,1.77,0),(.035,.06,.04),'skin'),sphere('earR',(.17,1.77,0),(.035,.06,.04),'skin')])
for side,label in [(-1,'L'),(1,'R')]:
    part('Arm'+label,(side*.3,1.52,0),lambda side=side:[
        sphere('sleeve',(side*.34,1.29,0),(.11,.25,.11),'cloth'),
        sphere('forearm',(side*.35,.99,-.03),(.085,.17,.085),'skin'),
        sphere('hand',(side*.35,.84,-.04),(.085,.10,.08),'skin')])
    part('Leg'+label,(side*.14,1.0,0),lambda side=side:[
        sphere('trouser',(side*.14,.68,0),(.125,.32,.14),'denim'),
        sphere('shin',(side*.14,.3,0),(.095,.22,.11),'denim'),
        box('boot',(side*.14,.1,-.07),(.22,.2,.38),'dark',.06)])
box('Pistol',(.36,.88,-.20),(.07,.12,.30),'metal',.015)
export('runner',False)

# Curved trunk and swept, pointed palm fronds.
for j in range(12):
    y=j*.43
    beam('trunk',(.12*math.sin(y*.3),y,0),(.12*math.sin((y+.5)*.3),y+.5,0),.22-j*.008,'wood')
    cyl('trunk ring',(.12*math.sin(y*.3),y,0),.23-j*.008,.07,'sand',12)
for i in range(10):
    a=i*math.tau/10
    vertices=[]
    for j in range(7):
        r=j*.55; width=math.sin(j/6*math.pi)*.42
        y=5.2+math.sin(j/6*math.pi)*.8-j*.11
        for side in [-1,1]:vertices.append((.12+math.cos(a)*r+side*math.sin(a)*width,y,math.sin(a)*r-side*math.cos(a)*width))
    poly('frond',vertices,[(2*j,2*j+1,2*j+3,2*j+2) for j in range(6)],'leaf' if i%2 else 'leaf2')
export('palm')

box('crate',(0,.38,0),(.8,.76,.65),'wood')
for x in [-.3,.3]:box('strap',(x,.39,0),(.06,.8,.69),'metal')
text('mark','DR',(0,.28,.335),.21,'gold')
export('crate')

box('cabinet',(0,.65,0),(1.1,1.3,.65),'teal',.08)
box('screen bezel',(0,1.01,.34),(.82,.42,.08),'dark')
box('screen',(0,1.03,.39),(.68,.28,.02),'blue')
box('tray',(0,.56,.43),(.8,.08,.45),'metal')
for i in range(3):box('button',(-.25+i*.25,.66,.36),(.12,.08,.03),'gold')
export('terminal')
print('Asset kit exported to',OUT)
