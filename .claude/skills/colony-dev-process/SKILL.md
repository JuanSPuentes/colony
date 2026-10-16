---
name: colony-dev-process
description: >
  Disciplina de trabajo para desarrollar el proyecto "Colony: Under the Earth" (el simulador de
  colonia de hormigas), independiente de en qué lenguaje o motor esté hecho en este momento.
  Actívala siempre que se trabaje dentro de este repositorio: al agregar una fase o funcionalidad
  nueva, al depurar algo que dejó de funcionar, al decidir dónde debe vivir un archivo nuevo, antes
  de dar por buena una corrida de pruebas o un build, al hacer commit/push, o al encontrarse con
  cambios de otra persona/agente en el repo. No sustituye la documentación propia del proyecto
  (README/ARCHITECTURE o el equivalente que exista): la complementa con el *cómo trabajar*, no el
  *cómo está organizado el código*.
---

# Cómo trabajar en Colony: Under the Earth

Este proyecto se construye por fases, a veces con más de una persona (o agente) tocando el mismo
repositorio sin coordinarse en tiempo real. Las reglas de aquí existen porque ya se rompieron cosas
por no seguirlas, y volver a romperlas es el riesgo más probable de esta sesión también. No dependen
de si el proyecto hoy está en GDScript, C#, Python o cualquier otra cosa.

## 1. Antes de tocar código, lee lo que ya existe

1. Busca y lee la documentación de arquitectura/convenciones del proyecto (hoy es
   `ARCHITECTURE.md` y las secciones relevantes del `README.md`; si el proyecto cambia de motor,
   busca el archivo equivalente antes de asumir que no existe).
2. Revisa qué fase está en curso y qué quedó explícitamente pendiente o simplificado a propósito
   (una sección tipo "Simplificaciones deliberadas" o "Hoja de ruta"). Repetir una simplificación ya
   documentada no es un error; ignorarla y "arreglarla" sin que nadie lo pidió, sí puede serlo.
3. Si hay pruebas automatizadas, identifica cuántas suites hay y qué cubre cada una antes de asumir
   qué falta.

## 2. Toda función nueva debe poder estar ausente sin romper lo que ya funcionaba

Esta es la regla más importante del proyecto. En la práctica:

- Lo nuevo se activa con una condición explícita y comprobable (un flag, un modo, un método que hay
  que llamar a propósito), nunca "porque sí" en el camino por defecto que ya usan las partes viejas.
- Si lo nuevo necesita cambiar una estructura de datos vieja, el valor por defecto de ese cambio debe
  reproducir el comportamiento anterior exacto, no una aproximación "parecida".
- Antes de dar algo por terminado, pregúntate: *si yo no hubiera tocado nada de esto, ¿el camino
  viejo seguiría exactamente igual?* Si la respuesta depende de que "probablemente nadie note la
  diferencia", no está aislado de verdad.
- Cuando de verdad haga falta cambiar un comportamiento viejo a propósito (el juego cambió de forma
  real, no por descuido), se hace, se documenta por qué, y se ajusta la prueba vieja correspondiente
  — nunca en silencio.

## 3. Una suite de pruebas (o verificación equivalente) por hito, nunca una que reemplaza a otra

Si el proyecto tiene pruebas automatizadas organizadas por fase/hito, cada una cubre su propio
alcance y no se reescribe para que quepa lo nuevo. Antes de considerar cerrado un cambio, **todas**
las suites anteriores deben seguir pasando, más la que corresponde a lo que se acaba de construir.
Si una suite vieja falla, el default es arreglar el aislamiento de lo nuevo, no relajar esa prueba.

## 4. Verificar de verdad, no asumir

- Si hay manera de ejecutar algo (pruebas, un build, un script, una captura de pantalla), ejecútalo
  antes de decir que algo funciona. "Debería funcionar" y "funciona" no son lo mismo, y la diferencia
  solo la nota quien lea el resultado real.
- Si algo falla una vez, no lo descartes como ruido sin revisar el motivo real primero (lee el
  código que cambió, no solo el número). Si después de revisarlo todo apunta a una causa externa
  (otro proceso consumiendo recursos, el entorno, algo fuera del código), decláralo así
  explícitamente y, si se puede, confírmalo con una segunda corrida en condiciones limpias.
- Nunca reportes como visto u observado algo que no se ejecutó o no se miró de verdad.

## 5. Depurar con método, no por intuición

1. Reproduce el problema con el caso más chico posible.
2. Lee el código real del camino que falla antes de adivinar la causa; un script o `print`/log
   temporal para confirmar una hipótesis es más confiable que una suposición, por razonable que
   parezca.
3. Cambia una sola cosa a la vez y vuelve a verificar.
4. Borra cualquier script o archivo temporal de depuración una vez que cumplió su función — no
   debe quedar basura en el repositorio.

## 6. Si aparece trabajo de otra persona o agente en el repo

Antes de asumir que algo choca con lo que tú ibas a hacer:
1. Revisa qué se agregó de verdad (el diff, no solo el nombre del commit).
2. Corre las pruebas/verificaciones existentes para saber si ese trabajo ya quedó estable.
3. Si hay una posible superposición conceptual con lo que el usuario te pidió, dilo con claridad y
   pregunta cómo reconciliarlo en vez de sobrescribirlo o duplicarlo en silencio.

## 7. Consistencia por encima de la novedad

Antes de inventar un patrón nuevo (de estilo visual, de nombres, de estructura de carpetas, de cómo
se arma una pantalla o un panel), busca si el proyecto ya resuelve algo parecido en otro lado y
reutilízalo. Un proyecto se siente hecho por una sola mano cuando las cosas nuevas se parecen a las
viejas, no cuando cada función introduce su propia forma de hacer lo mismo.

## 8. Git: cambios intencionales y visibles

- Antes de hacer `commit`, revisa qué quedó en el stage (no solo confiar en un `add` masivo):
  archivos que no deberían estar ahí, o cambios hechos por una herramienta externa sin que nadie lo
  pidiera (por ejemplo, un editor que reescribe un archivo de configuración y borra un comentario),
  se corrigen antes de commitear, no después.
- El mensaje de commit explica qué cambió y, cuando no es obvio, por qué.
- `commit` y `push` se hacen cuando se piden, no como parte automática de "terminar una tarea".

## 9. Cuándo preguntar y cuándo decidir solo

Pregunta solo cuando la decisión es genuinamente del usuario y no se puede inferir del proyecto ni
de lo ya acordado (por ejemplo: dos direcciones de diseño igual de válidas que cambian el rumbo del
proyecto). Si la respuesta razonable es clara a partir de lo que el proyecto ya documentó o de cómo
se resolvió algo parecido antes, se decide y se sigue, dejando constancia de qué se eligió y por qué.
