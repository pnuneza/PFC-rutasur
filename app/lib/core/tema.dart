/// Tema visual: paleta definida en P06 (sección 2.14, contrastes WCAG 2.1 AA).
library;

import 'package:flutter/material.dart';

import '../domain/modelos.dart';

abstract final class ColoresRutaSur {
  static const Color primario = Color(0xFF0F5257); // verde azulado, contraste 8.88:1
  static const Color mollebaya = Color(0xFF1D5FD1); // azul, 5.82:1
  static const Color cerrillo = Color(0xFFB4410B); // naranja oscuro, 5.67:1
  static const Color tramoComun = Color(0xFF4A5560); // gris pizarra, 6.45:1

  static const Color vigenteTexto = Color(0xFF1E6E31);
  static const Color vigenteFondo = Color(0xFFD5EFDA);
  static const Color demoradoTexto = Color(0xFF7A4A00);
  static const Color demoradoFondo = Color(0xFFFFE2AE);
  static const Color noConfiableTexto = Color(0xFFB3261E);
  static const Color noConfiableFondo = Color(0xFFF9DEDC);

  static const Color texto = Color(0xFF191C1C);
  static const Color textoSecundario = Color(0xFF3F4948);
  static const Color fondo = Color(0xFFFAFBFB);

  static Color deRamal(Ramal ramal) => switch (ramal) {
        Ramal.mollebaya => mollebaya,
        Ramal.cerrillo => cerrillo,
      };

  static ({Color texto, Color fondo}) deFrescura(Frescura frescura) => switch (frescura) {
        Frescura.vigente => (texto: vigenteTexto, fondo: vigenteFondo),
        Frescura.demorado => (texto: demoradoTexto, fondo: demoradoFondo),
        Frescura.noConfiable => (texto: noConfiableTexto, fondo: noConfiableFondo),
      };
}

ThemeData temaRutaSur() {
  final esquema = ColorScheme.fromSeed(
    seedColor: ColoresRutaSur.primario,
    primary: ColoresRutaSur.primario,
    surface: ColoresRutaSur.fondo,
    onSurface: ColoresRutaSur.texto,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: ColoresRutaSur.fondo,
  );
  return base.copyWith(textTheme: conTextoMinimo(base.textTheme));
}

/// Tamaño mínimo de todo texto informativo (P06, sección 2.14; D-10).
const double tamanoTextoMinimo = 16;

/// Sube a 16 sp los estilos que Material 3 trae más pequeños (12–14 sp):
/// cuerpo, etiquetas de botones y títulos pequeños. Pensado para leer en la
/// calle, con el teléfono en la mano y a pleno sol.
TextTheme conTextoMinimo(TextTheme base) {
  // En ThemeData los estilos aún no traen tamaño (null): Flutter lo agrega después,
  // desde Typography.englishLike, con 11–14 sp para estos estilos. Por eso un tamaño
  // vacío también se fija en 16; solo se respeta un tamaño explícito mayor.
  TextStyle minimo(TextStyle? estilo) {
    final tamano = estilo?.fontSize;
    if (estilo != null && tamano != null && tamano >= tamanoTextoMinimo) return estilo;
    return (estilo ?? const TextStyle()).copyWith(fontSize: tamanoTextoMinimo);
  }

  return base.copyWith(
    bodyLarge: minimo(base.bodyLarge),
    bodyMedium: minimo(base.bodyMedium),
    bodySmall: minimo(base.bodySmall),
    labelLarge: minimo(base.labelLarge),
    labelMedium: minimo(base.labelMedium),
    labelSmall: minimo(base.labelSmall),
    titleSmall: minimo(base.titleSmall),
  );
}
