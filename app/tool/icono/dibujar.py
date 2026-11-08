import asyncio, sys
from playwright.async_api import async_playwright

def pin(color_bus, dy=0, escala=1.0):
    # Pin blanco con la parte frontal de una combi dentro. Lienzo 1024.
    return f'''<g transform="translate(512 {512+dy}) scale({escala}) translate(-512 -559)">
  <path d="M512,860 C430,740 300,620 300,470 A212,212 0 1 1 724,470 C724,620 594,740 512,860 Z" fill="#FFFFFF"/>
  <rect x="404" y="352" width="216" height="206" rx="34" fill="{color_bus}"/>
  <rect x="428" y="372" width="168" height="18" rx="9" fill="#FFFFFF" fill-opacity="0.55"/>
  <rect x="428" y="402" width="168" height="84" rx="14" fill="#FFFFFF"/>
  <circle cx="452" cy="522" r="15" fill="#FFFFFF"/>
  <circle cx="572" cy="522" r="15" fill="#FFFFFF"/>
  <rect x="488" y="514" width="48" height="14" rx="7" fill="#FFFFFF" fill-opacity="0.55"/>
  <rect x="420" y="552" width="40" height="34" rx="10" fill="{color_bus}"/>
  <rect x="564" y="552" width="40" height="34" rx="10" fill="{color_bus}"/>
</g>'''

def svg(fondo, forma, color_bus, escala):
    if forma == 'cuadrado':      # ícono clásico (Android < 8): cuadrado redondeado
        bg = f'<rect width="1024" height="1024" rx="230" fill="{fondo}"/>'
    elif forma == 'lleno':       # web «maskable» y fondo completo
        bg = f'<rect width="1024" height="1024" fill="{fondo}"/>'
    else:                        # capa frontal del ícono adaptable: sin fondo
        bg = ''
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{bg}{pin(color_bus, escala=escala)}</svg>'

VARIANTES = {
    # nombre: (fondo, forma, color de la combi, escala)
    'pasajero_cuadrado': ('#0F5257', 'cuadrado', '#0F5257', 1.0),
    'pasajero_frente':   ('#0F5257', 'frente',   '#0F5257', 0.76),
    'pasajero_lleno':    ('#0F5257', 'lleno',    '#0F5257', 0.78),
    'conductor_cuadrado':('#B4410B', 'cuadrado', '#B4410B', 1.0),
    'conductor_frente':  ('#B4410B', 'frente',   '#B4410B', 0.76),
}

async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch()
        pg = await b.new_page(viewport={'width':1024,'height':1024})
        for nombre,(f,forma,c,e) in VARIANTES.items():
            await pg.set_content(f'<html><body style="margin:0;background:transparent">{svg(f,forma,c,e)}</body></html>')
            await pg.screenshot(path=f'{nombre}.png', omit_background=True, clip={'x':0,'y':0,'width':1024,'height':1024})
        await b.close()
asyncio.run(main())
