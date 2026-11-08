import sys, pathlib
from PIL import Image
app = pathlib.Path(sys.argv[1])
res_main = app/'android/app/src/main/res'
res_cond = app/'android/app/src/conductor/res'
DENS = {'mdpi':1,'hdpi':1.5,'xhdpi':2,'xxhdpi':3,'xxxhdpi':4}
def guardar(src, dst, lado):
    dst.parent.mkdir(parents=True, exist_ok=True)
    Image.open(src).convert('RGBA').resize((lado,lado), Image.LANCZOS).save(dst, optimize=True)
for res, nombre in ((res_main,'pasajero'),(res_cond,'conductor')):
    for d,f in DENS.items():
        guardar(f'{nombre}_cuadrado.png', res/f'mipmap-{d}/ic_launcher.png', round(48*f))
        guardar(f'{nombre}_frente.png', res/f'mipmap-{d}/ic_launcher_foreground.png', round(108*f))
web = app/'web'
guardar('pasajero_cuadrado.png', web/'favicon.png', 48)
guardar('pasajero_cuadrado.png', web/'icons/Icon-192.png', 192)
guardar('pasajero_cuadrado.png', web/'icons/Icon-512.png', 512)
guardar('pasajero_lleno.png', web/'icons/Icon-maskable-192.png', 192)
guardar('pasajero_lleno.png', web/'icons/Icon-maskable-512.png', 512)
print('ok')
