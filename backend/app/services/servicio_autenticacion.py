"""Servicio de autenticación (CU-03: iniciar sesión de conductor o del panel).

Reglas (P05 Tabla 34, P06 Tabla 52):
- La contraseña se compara con su hash bcrypt, en tiempo constante.
- Cada fallo suma un intento; al quinto la cuenta se bloquea 15 minutos y se registra
  un evento de seguridad. Un ingreso exitoso reinicia el contador.
- El mensaje de error es el mismo exista o no el usuario, y también si la cuenta o
  su unidad están deshabilitadas: así no se revela qué cuentas existen.
- El token dura 12 horas (un turno) y lleva el rol y, para el conductor, su unidad.
"""

from datetime import datetime, timedelta

from app.core.seguridad import emitir_token, verificar_contrasena
from app.domain.excepciones import CredencialesInvalidas, CuentaBloqueada, TokenInvalido
from app.domain.modelos import CuentaAcceso, Identidad, TokenEmitido
from app.domain.umbrales import UMBRALES_POR_DEFECTO, Umbrales
from app.repositories.interfaces import RepositorioCuentas

MENSAJE_CREDENCIALES = "Usuario o contraseña incorrectos"


class ServicioAutenticacion:
    def __init__(
        self,
        repositorio: RepositorioCuentas,
        secreto: str,
        umbrales: Umbrales = UMBRALES_POR_DEFECTO,
    ) -> None:
        self._repo = repositorio
        self._secreto = secreto
        self._u = umbrales

    def iniciar_sesion(self, usuario: str, contrasena: str, ahora: datetime) -> TokenEmitido:
        cuenta = self._repo.buscar_por_usuario(usuario)
        # Se verifica siempre, aunque la cuenta no exista: misma demora en ambos casos
        correcta = verificar_contrasena(contrasena, cuenta.hash_contrasena if cuenta else None)

        if cuenta is None:
            raise CredencialesInvalidas(MENSAJE_CREDENCIALES)
        self._rechazar_si_bloqueada(cuenta, ahora)
        if not correcta:
            self._registrar_fallo(cuenta, ahora)
        if not cuenta.activa:
            # Contraseña correcta, pero cuenta o unidad deshabilitada: mismo mensaje
            self._repo.registrar_evento(
                "SEGURIDAD", "login", cuenta, {"motivo": "cuenta_deshabilitada", "http": 401}
            )
            raise CredencialesInvalidas(MENSAJE_CREDENCIALES)

        self._repo.registrar_ingreso(cuenta)
        identidad = Identidad(
            cuenta_id=cuenta.id,
            rol=cuenta.rol,
            unidad_id=cuenta.unidad_id,
            etiqueta_unidad=cuenta.etiqueta_unidad,
        )
        token = emitir_token(identidad, self._secreto, self._u.vigencia_token_s, ahora)
        return TokenEmitido(token=token, vigencia_s=self._u.vigencia_token_s, identidad=identidad)

    def verificar_vigente(self, identidad: Identidad) -> None:
        """Un token válido deja de servir si después se deshabilita la cuenta o la unidad."""
        if not self._repo.cuenta_vigente(identidad.cuenta_id, identidad.rol):
            raise TokenInvalido("La cuenta fue deshabilitada; comuníquese con el administrador")

    # ------------------------------------------------------------------
    def _rechazar_si_bloqueada(self, cuenta: CuentaAcceso, ahora: datetime) -> None:
        if cuenta.bloqueada_hasta is not None and cuenta.bloqueada_hasta > ahora:
            restante = int((cuenta.bloqueada_hasta - ahora).total_seconds()) + 1
            raise CuentaBloqueada(
                f"La cuenta está bloqueada; vuelva a intentarlo en {restante // 60 + 1} min",
                restante,
            )

    def _registrar_fallo(self, cuenta: CuentaAcceso, ahora: datetime) -> None:
        hasta = ahora + timedelta(seconds=self._u.bloqueo_s)
        bloqueada = self._repo.registrar_fallo(cuenta, self._u.intentos_antes_de_bloqueo, hasta)
        if bloqueada:
            self._repo.registrar_evento(
                "SEGURIDAD",
                "login",
                cuenta,
                {
                    "motivo": "cuenta_bloqueada",
                    "intentos": self._u.intentos_antes_de_bloqueo,
                    "http": 403,
                },
            )
            raise CuentaBloqueada(
                "Demasiados intentos fallidos; la cuenta queda bloqueada "
                f"{self._u.bloqueo_s // 60} min",
                self._u.bloqueo_s,
            )
        raise CredencialesInvalidas(MENSAJE_CREDENCIALES)
