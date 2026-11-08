# Ícono de RutaSur

El ícono es un pin blanco con el frente de una combi. El fondo es verde azulado (`#0F5257`) en la app del pasajero y en el panel, y naranja (`#B4410B`) en la del conductor, para distinguirlas en el teléfono.

Para regenerarlo, desde esta carpeta (necesita Playwright con Chromium y Pillow):

```
python dibujar.py          # dibuja el SVG y lo exporta a PNG de 1024 px
python generar.py ../..    # escribe todos los tamaños de Android (mipmap-*) y de la web
```

En Android 8 o superior se usa el ícono adaptable (`mipmap-anydpi-v26/ic_launcher.xml`), que combina el color de fondo (`values/ic_launcher_background.xml`) con la capa frontal (`ic_launcher_foreground.png`). En versiones anteriores se usa `ic_launcher.png`. Los archivos de `src/conductor/res` reemplazan a los de `src/main/res` en el sabor del conductor.
