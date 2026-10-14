"""Servicio de emisión: sesiones y recepción de posiciones (CU-02, P05 Figura 19).

En este incremento lo usa el simulador de unidad. En el Sprint 3 lo invocarán los
endpoints autenticados del conductor (POST /sessions y /sessions/{id}/positions),
sin cambiar esta lógica.
"""

from collections import Counter
from collections.abc import Sequence
from datetime import datetime, timedelta
from uuid import UUID

from app.domain.excepciones import (
    AccesoDenegado,
    ErrorDeNegocio,
    RecursoNoEncontrado,
    SesionNoActiva,
    UnidadInactiva,
)
from app.domain.modelos import (
    AcuseLote,
    EstadoSesion,
    MedicionTrazado,
    PosicionEntrante,
    PosicionValidada,
    Ramal,
    ReferenciaPosicion,
    Sentido,
    SesionEmision,
)
from app.domain.umbrales import UMBRALES_POR_DEFECTO, Umbrales
from app.repositories.interfaces import RepositorioEmision
from app.services.validador_posiciones import ValidadorPosiciones

TAMANO_MAXIMO_LOTE = 200


class ServicioEmision:
    def __init__(
        self,
        repositorio: RepositorioEmision,
        validador: ValidadorPosiciones,
        umbrales: Umbrales = UMBRALES_POR_DEFECTO,
    ) -> None:
        self._repo = repositorio
        self._validador = validador
        self._u = umbrales

    # ------------------------------------------------------
    # Sesiones
    # ------------------------------------------------------
    def abrir_sesion(
        self, unidad_id: UUID, cuenta_id: UUID, ramal: Ramal, sentido: Sentido, ahora: datetime
    ) -> SesionEmision:
        """Cierra la sesión anterior de la unidad y abre la nueva (RN-002).

        El inicio de la sesión lo fija el reloj de la aplicación (`ahora`), el mismo
        con el que luego se validan las posiciones. Así ninguna regla compara horas
        tomadas de dos relojes distintos (el del servidor y el de la base de datos).
        """
        activa = self._repo.unidad_activa(unidad_id)
        if activa is None:
            raise RecursoNoEncontrado("La unidad no existe")
        if not activa:
            raise UnidadInactiva("La unidad está deshabilitada; comuníquese con el administrador")

        sesion = self._repo.abrir_sesion(unidad_id, cuenta_id, ramal, sentido, ahora)
        self._repo.registrar_evento(
            "PETICION", "abrir_sesion", unidad_id, {"variante": f"{ramal}-{sentido}"}
        )
        return sesion

    def cerrar_sesion(self, sesion_id: UUID, unidad_id: UUID) -> None:
        sesion = self._sesion_abierta_de(sesion_id, unidad_id)
        self._repo.cerrar_sesion(sesion.id, EstadoSesion.CERRADA_POR_CONDUCTOR)

    # ------------------------------------------------------
    # Posiciones
    # ------------------------------------------------------
    def recibir_lote(
        self,
        sesion_id: UUID,
        unidad_id: UUID,
        posiciones: Sequence[PosicionEntrante],
        ahora: datetime,
    ) -> AcuseLote:
        """Valida, guarda y confirma un lote de posiciones (P06, Tabla 54)."""
        sesion = self._sesion_abierta_de(sesion_id, unidad_id)
        self._validar_forma(posiciones, sesion, ahora)

        # Idempotencia: lo ya registrado se confirma sin volver a guardarse
        ya_registradas = self._repo.ids_registrados([p.id for p in posiciones])
        nuevas = sorted(
            (p for p in posiciones if p.id not in ya_registradas), key=lambda p: p.capturada_en
        )

        validadas, ultima = self._validar_en_orden(sesion, nuevas)

        if validadas:
            self._repo.guardar_posiciones(sesion.id, validadas)
        if ultima is not None:
            posicion, medicion = ultima
            self._repo.actualizar_ultima_posicion(
                sesion.id, posicion, medicion.distancia_recorrida_m
            )

        descartadas = [v for v in validadas if not v.resultado.valida]
        if descartadas:
            motivos = Counter(str(v.resultado.motivo) for v in descartadas)
            self._repo.registrar_evento(
                "POSICION_DESCARTADA", "recibir_lote", sesion.unidad_id, dict(motivos)
            )

        return AcuseLote(
            confirmados=[p.id for p in posiciones],
            publicadas=len(validadas) - len(descartadas),
            descartadas=len(descartadas),
            duplicadas=len(ya_registradas),
        )

    # ------------------------------------------------------
    # Auxiliares
    # ------------------------------------------------------
    def _sesion_abierta_de(self, sesion_id: UUID, unidad_id: UUID) -> SesionEmision:
        sesion = self._repo.obtener_sesion(sesion_id)
        if sesion is None:
            raise RecursoNoEncontrado("La sesión no existe")
        if sesion.unidad_id != unidad_id:
            raise AccesoDenegado("La sesión pertenece a otra unidad")
        if not sesion.estado.abierta:
            raise SesionNoActiva("La sesión está cerrada; inicie una nueva")
        return sesion

    def _validar_forma(
        self, posiciones: Sequence[PosicionEntrante], sesion: SesionEmision, ahora: datetime
    ) -> None:
        if not 1 <= len(posiciones) <= TAMANO_MAXIMO_LOTE:
            raise ErrorDeNegocio(f"El lote debe tener entre 1 y {TAMANO_MAXIMO_LOTE} posiciones")
        # El reloj del teléfono nunca coincide exactamente con el del servidor: se
        # admite la misma tolerancia hacia el futuro y hacia antes del inicio.
        tolerancia = timedelta(seconds=self._u.tolerancia_reloj_s)
        for p in posiciones:
            if p.capturada_en > ahora + tolerancia:
                raise ErrorDeNegocio("Una posición tiene fecha de captura en el futuro")
            if p.capturada_en < sesion.inicio - tolerancia:
                raise ErrorDeNegocio("Una posición es anterior al inicio de la sesión")

    def _validar_en_orden(
        self, sesion: SesionEmision, nuevas: list[PosicionEntrante]
    ) -> tuple[list[PosicionValidada], tuple[PosicionValidada, MedicionTrazado] | None]:
        """Valida cada posición contra la última válida, en orden de captura."""
        if not nuevas:
            return [], None

        mediciones = self._repo.medir_contra_trazado(
            sesion.variante_id, [p.ubicacion for p in nuevas]
        )
        anterior = self._repo.ultima_posicion_valida(sesion.id)
        validadas: list[PosicionValidada] = []
        ultima: tuple[PosicionValidada, MedicionTrazado] | None = None

        for posicion, medicion in zip(nuevas, mediciones, strict=True):
            resultado = self._validador.validar(posicion, medicion, anterior)
            validada = PosicionValidada(posicion, resultado)
            validadas.append(validada)
            if resultado.valida:
                anterior = ReferenciaPosicion(posicion.ubicacion, posicion.capturada_en)
                ultima = (validada, medicion)

        return validadas, ultima
