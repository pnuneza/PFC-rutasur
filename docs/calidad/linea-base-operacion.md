# Línea base de operación de la línea LB (chat del grupo, julio–octubre 2026)

Antes de RutaSur, los pasajeros siguen las combis por un grupo de WhatsApp: el
despachador publica cada salida y la gente pregunta «¿por dónde está la combi?». De ese
chat sale una línea base para comparar en la prueba de campo (Módulo 7).

- **Fuente:** exportación del chat del grupo, del 13/02 al 31/10/2026 (unos 27 000 mensajes).
- **Periodo usado:** del 1/07 al 31/10. Antes de julio los avisos de salida son pocos
  (75 a 200 por mes, frente a 450 a 570 desde julio), así que contarían de menos.
- **Privacidad:** el script descarta el autor de cada mensaje al leerlo y solo imprime
  cifras agregadas. La exportación del chat no se sube al repositorio.
- **Cómo repetirlo:**

  ```
  python database/datos_reales/linea_base_chat.py chat.txt 2026-07-01 2026-10-31
  ```

## Salidas desde Santa Ana

Son 2043 avisos de salida en 101 días: 1038 de Mollebaya y 1005 de Cerrillo. Entre
paréntesis van el primer y el tercer cuartil.

| Ramal | Salidas por día (L-V) | Sábado | Domingo | Primera salida | Última salida | Intervalo entre salidas |
|---|---|---|---|---|---|---|
| Mollebaya | 11 (83 días) | 6 (18 días) | sin avisos | 05:41 (05:41–06:13) | 16:30 (16:05–16:50) | 62 min (51–79) |
| Cerrillo | 11 (83 días) | 5 (18 días) | sin avisos | 06:06 (05:57–06:08) | 16:43 (16:00–17:08) | 62 min (51–80) |

- **Domingos:** el grupo casi no tiene mensajes (47 en 17 domingos, frente a 1500–2300
  por cada otro día de la semana). Con estos datos no se puede afirmar que no haya
  servicio; lo que se sabe es que nadie despacha por el chat.
- **Última salida:** hacia las 16:30–16:45 sale la última combi de bajada desde Santa Ana.
  Los retornos desde el Centro siguen después. El horario que hoy tiene la línea en el
  panel es de 05:00 a 21:00, y conviene confirmarlo con la empresa.

## Tiempos entre puntos de control

Son los tiempos que el despachador anota en cada aviso de salida (de bajada).

| Ramal | Tramo | Casos | Mediana | Cuartiles |
|---|---|---|---|---|
| Cerrillo | Santa Ana → Yanayaco | 873 | 12 min | 12–12 |
| Cerrillo | Yanayaco → Cerrillo | 858 | 5 min | 5–6 |
| Mollebaya | Santa Ana → Plaza Characato | 42 | 15 min | 15–15 |
| Mollebaya | Plaza Characato → Cruce de Characato | 41 | 4 min | 4–4 |
| Cerrillo | Cerrillo → Plaza Characato | 15 | 5 min | 5–5 |
| Cerrillo | Santa Ana → Don Abdón | 6 | 8 min | 8–8 |
| Cerrillo | Don Abdón → Yanayaco | 7 | 4 min | 4–4 |

Los cuartiles son casi iguales a la mediana: en 873 avisos, Santa Ana → Yanayaco
siempre suma 12 minutos. Eso indica que **son tiempos programados**, que el despachador
calcula al publicar la salida, y no tiempos medidos. Sirven como referencia de lo que
la empresa espera, no como medición de lo que pasa en la pista.

Machahuay → Santa Ana (10 min, 191 casos) queda fuera: la combi entra a Machahuay solo
algunas veces, y el recorrido de RutaSur empieza en Santa Ana.

## Qué significa para RutaSur

1. **Con una combi por hora en cada ramal, perder una cuesta una hora de espera.** Saber
   cuándo llega la siguiente es justo el problema que resuelve el ETA de la app.
2. **La prueba de campo se planifica de lunes a viernes, entre las 06:00 y las 16:30.**
   En esa franja hay unas 11 salidas por ramal; los sábados hay la mitad y los domingos
   no hay avisos.
3. **Primera comparación para el ETA (M7).** Para una combi que sale de Santa Ana, el ETA
   que da RutaSur a Yanayaco y a Cerrillo se compara con lo programado (12 y 17 min). Luego
   ambos se comparan con la hora real de llegada, que da el GPS del conductor. Así se
   mide si la app predice mejor que el horario programado.
4. **Preguntas por chat como indicador.** De julio a octubre, el grupo recibió una
   mediana de **24 preguntas por día hábil** (cuartiles 19–30; 2327 en total) del tipo
   «¿por dónde está la combi?» o «¿a qué hora sale?». Si bajan en las semanas de prueba,
   es una señal indirecta de que la app reemplaza esa consulta. Es un indicador
   aproximado: el conteo busca frases, no lee intenciones.
