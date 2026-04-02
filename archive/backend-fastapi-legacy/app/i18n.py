"""Multi-language message templates for CLI Pulse backend alerts and UI text."""

from __future__ import annotations

from typing import ClassVar

_TRANSLATIONS: dict[str, dict[str, str]] = {
    # ── English (default) ──
    "en": {
        "quota_low_risk": "{provider} quota below 20% — check remaining allowance.",
        "device_offline_risk": "{device} helper offline — verify network or service process.",
        "no_risk": "No high-risk issues at this time.",
        "device_offline": "Device {device} has not sent a heartbeat for {minutes} minutes.",
        "usage_spike": "{provider} today usage reached {usage:,}, exceeding threshold {threshold:,}.",
        "session_failing": "Session {session} status {status}, {errors} cumulative errors.",
        "session_too_long": "Session {session} has been running for {duration} minutes, exceeding threshold {threshold} minutes.",
        "project_budget": "Project {project} today cost reached ${cost:.2f}, exceeding budget threshold ${threshold:.2f}.",
        "seed_device_offline": "Device offline for 2 hours, related sessions stopped syncing.",
        "seed_quota_warning": "Weekly cumulative usage approaching limit — consider reducing background tasks.",
        "seed_session_failed": "Last task failed due to provider auth expired, retried 3 times.",
        "seed_budget_exceeded": "Project provider-layer today cost reached $0.28, exceeding budget threshold $0.25.",
        "cost_spike": "{provider} estimated cost today reached ${cost:.2f}, exceeding threshold ${threshold:.2f}.",
        "error_rate_spike": "{provider} error rate spiked: {errors} errors across {sessions} sessions.",
        "quota_critical": "{provider} quota critically low — only {remaining:,} remaining ({percent:.0f}%).",
    },
    # ── 简体中文 ──
    "zh": {
        "quota_low_risk": "{provider} 配额低于 20% — 请检查剩余额度。",
        "device_offline_risk": "{device} 助手离线 — 请检查网络或服务进程。",
        "no_risk": "当前没有高风险问题。",
        "device_offline": "设备 {device} 已超过 {minutes} 分钟未发送心跳。",
        "usage_spike": "{provider} 今日用量达到 {usage:,}，超过阈值 {threshold:,}。",
        "session_failing": "会话 {session} 状态 {status}，累计 {errors} 个错误。",
        "session_too_long": "会话 {session} 已运行 {duration} 分钟，超过阈值 {threshold} 分钟。",
        "project_budget": "项目 {project} 今日费用达 ${cost:.2f}，超过预算阈值 ${threshold:.2f}。",
        "seed_device_offline": "设备离线 2 小时，相关会话已停止同步。",
        "seed_quota_warning": "每周累计用量接近上限 — 建议减少后台任务。",
        "seed_session_failed": "上次任务因服务商认证过期失败，已重试 3 次。",
        "seed_budget_exceeded": "项目 provider-layer 今日费用达 $0.28，超过预算阈值 $0.25。",
        "cost_spike": "{provider} 今日预估费用达 ${cost:.2f}，超过阈值 ${threshold:.2f}。",
        "error_rate_spike": "{provider} 错误率飙升：{sessions} 个会话中出现 {errors} 个错误。",
        "quota_critical": "{provider} 配额严重不足 — 仅剩 {remaining:,}（{percent:.0f}%）。",
    },
    # ── 日本語 ──
    "ja": {
        "quota_low_risk": "{provider} のクォータが20%未満です — 残量を確認してください。",
        "device_offline_risk": "{device} ヘルパーがオフラインです — ネットワークまたはサービスを確認してください。",
        "no_risk": "現在、高リスクの問題はありません。",
        "device_offline": "デバイス {device} が {minutes} 分間ハートビートを送信していません。",
        "usage_spike": "{provider} の本日使用量が {usage:,} に達し、閾値 {threshold:,} を超過しました。",
        "session_failing": "セッション {session} 状態 {status}、累計エラー {errors} 件。",
        "session_too_long": "セッション {session} が {duration} 分間実行中、閾値 {threshold} 分を超過しました。",
        "project_budget": "プロジェクト {project} の本日コストが ${cost:.2f} に達し、予算閾値 ${threshold:.2f} を超過しました。",
        "seed_device_offline": "デバイスが2時間オフライン、関連セッションの同期が停止しました。",
        "seed_quota_warning": "週間累計使用量が上限に近づいています — バックグラウンドタスクの削減を検討してください。",
        "seed_session_failed": "プロバイダー認証切れにより前回タスクが失敗、3回リトライしました。",
        "seed_budget_exceeded": "プロジェクト provider-layer の本日コストが $0.28 に達し、予算閾値 $0.25 を超過しました。",
        "cost_spike": "{provider} の本日推定コストが ${cost:.2f} に達し、閾値 ${threshold:.2f} を超過しました。",
        "error_rate_spike": "{provider} エラー率が急上昇：{sessions} セッションで {errors} エラー。",
        "quota_critical": "{provider} のクォータが危機的です — 残り {remaining:,}（{percent:.0f}%）。",
    },
    # ── 한국어 ──
    "ko": {
        "quota_low_risk": "{provider} 할당량이 20% 미만입니다 — 남은 사용량을 확인하세요.",
        "device_offline_risk": "{device} 도우미가 오프라인입니다 — 네트워크 또는 서비스를 확인하세요.",
        "no_risk": "현재 고위험 문제가 없습니다.",
        "device_offline": "기기 {device}이(가) {minutes}분 동안 하트비트를 전송하지 않았습니다.",
        "usage_spike": "{provider} 오늘 사용량이 {usage:,}에 도달하여 임계값 {threshold:,}을 초과했습니다.",
        "session_failing": "세션 {session} 상태 {status}, 누적 오류 {errors}건.",
        "session_too_long": "세션 {session}이(가) {duration}분 동안 실행 중이며 임계값 {threshold}분을 초과했습니다.",
        "project_budget": "프로젝트 {project} 오늘 비용이 ${cost:.2f}에 도달하여 예산 임계값 ${threshold:.2f}을 초과했습니다.",
        "seed_device_offline": "기기가 2시간 동안 오프라인, 관련 세션 동기화가 중단되었습니다.",
        "seed_quota_warning": "주간 누적 사용량이 한도에 근접합니다 — 백그라운드 작업을 줄이세요.",
        "seed_session_failed": "공급자 인증 만료로 마지막 작업이 실패했으며 3회 재시도했습니다.",
        "seed_budget_exceeded": "프로젝트 provider-layer 오늘 비용이 $0.28에 도달하여 예산 임계값 $0.25을 초과했습니다.",
        "cost_spike": "{provider} 오늘 예상 비용이 ${cost:.2f}에 도달하여 임계값 ${threshold:.2f}을 초과했습니다.",
        "error_rate_spike": "{provider} 오류율 급증: {sessions}개 세션에서 {errors}개 오류.",
        "quota_critical": "{provider} 할당량이 심각한 수준입니다 — {remaining:,}만 남음 ({percent:.0f}%).",
    },
    # ── Español ──
    "es": {
        "quota_low_risk": "Cuota de {provider} por debajo del 20% — verifique la asignación restante.",
        "device_offline_risk": "Asistente {device} fuera de línea — verifique la red o el proceso del servicio.",
        "no_risk": "No hay problemas de alto riesgo en este momento.",
        "device_offline": "El dispositivo {device} no ha enviado latido en {minutes} minutos.",
        "usage_spike": "El uso de {provider} hoy alcanzó {usage:,}, superando el umbral {threshold:,}.",
        "session_failing": "Sesión {session} estado {status}, {errors} errores acumulados.",
        "session_too_long": "La sesión {session} lleva {duration} minutos ejecutándose, superando el umbral de {threshold} minutos.",
        "project_budget": "El costo del proyecto {project} hoy alcanzó ${cost:.2f}, superando el umbral de presupuesto ${threshold:.2f}.",
        "seed_device_offline": "Dispositivo fuera de línea por 2 horas, sesiones relacionadas dejaron de sincronizar.",
        "seed_quota_warning": "El uso acumulado semanal se acerca al límite — considere reducir tareas en segundo plano.",
        "seed_session_failed": "Última tarea falló por autenticación de proveedor expirada, reintentó 3 veces.",
        "seed_budget_exceeded": "Costo del proyecto provider-layer hoy alcanzó $0.28, superando el umbral de presupuesto $0.25.",
        "cost_spike": "El costo estimado de {provider} hoy alcanzó ${cost:.2f}, superando el umbral ${threshold:.2f}.",
        "error_rate_spike": "Pico de tasa de errores en {provider}: {errors} errores en {sessions} sesiones.",
        "quota_critical": "Cuota de {provider} críticamente baja — solo quedan {remaining:,} ({percent:.0f}%).",
    },
}

# Default locale
_current_locale = "en"


def set_locale(locale: str) -> None:
    """Set the active locale (e.g. 'en', 'zh', 'ja', 'ko', 'es')."""
    global _current_locale
    _current_locale = locale if locale in _TRANSLATIONS else "en"


def get_locale() -> str:
    """Return the active locale."""
    return _current_locale


class Msg:
    """Locale-aware message templates.

    Usage:
        Msg.get("quota_low_risk").format(provider="Claude")
        Msg.get("device_offline", locale="zh").format(device="Mac-1", minutes=10)
    """

    # Keep English constants for backward compatibility
    QUOTA_LOW_RISK: ClassVar[str] = _TRANSLATIONS["en"]["quota_low_risk"]
    DEVICE_OFFLINE_RISK: ClassVar[str] = _TRANSLATIONS["en"]["device_offline_risk"]
    NO_RISK: ClassVar[str] = _TRANSLATIONS["en"]["no_risk"]
    DEVICE_OFFLINE: ClassVar[str] = _TRANSLATIONS["en"]["device_offline"]
    USAGE_SPIKE: ClassVar[str] = _TRANSLATIONS["en"]["usage_spike"]
    SESSION_FAILING: ClassVar[str] = _TRANSLATIONS["en"]["session_failing"]
    SESSION_TOO_LONG: ClassVar[str] = _TRANSLATIONS["en"]["session_too_long"]
    PROJECT_BUDGET: ClassVar[str] = _TRANSLATIONS["en"]["project_budget"]
    SEED_DEVICE_OFFLINE: ClassVar[str] = _TRANSLATIONS["en"]["seed_device_offline"]
    SEED_QUOTA_WARNING: ClassVar[str] = _TRANSLATIONS["en"]["seed_quota_warning"]
    SEED_SESSION_FAILED: ClassVar[str] = _TRANSLATIONS["en"]["seed_session_failed"]
    SEED_BUDGET_EXCEEDED: ClassVar[str] = _TRANSLATIONS["en"]["seed_budget_exceeded"]
    COST_SPIKE: ClassVar[str] = _TRANSLATIONS["en"]["cost_spike"]
    ERROR_RATE_SPIKE: ClassVar[str] = _TRANSLATIONS["en"]["error_rate_spike"]
    QUOTA_CRITICAL: ClassVar[str] = _TRANSLATIONS["en"]["quota_critical"]

    @classmethod
    def get(cls, key: str, locale: str | None = None) -> str:
        """Return the message template for the given key and locale."""
        lang = locale or _current_locale
        messages = _TRANSLATIONS.get(lang, _TRANSLATIONS["en"])
        return messages.get(key, _TRANSLATIONS["en"].get(key, key))

    @classmethod
    def supported_locales(cls) -> list[str]:
        """Return list of supported locale codes."""
        return list(_TRANSLATIONS.keys())
