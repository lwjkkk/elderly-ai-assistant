"""Switch models only on an explicit free-tier exhaustion response."""
import hashlib
import logging
import threading
import time

logger = logging.getLogger(__name__)
FREE_TIER_CODE = "AllocationQuota.FreeTierOnly"
COOLDOWN_SECONDS = 24 * 60 * 60
_lock = threading.Lock()
_exhausted_until = {}


class ModelQuotaExhausted(RuntimeError):
    """All configured models are known to have exhausted their free tier."""


def namespace(service: str, endpoint: str, key: str) -> tuple:
    # A key/configuration change must not inherit another account's quota cache.
    return service, endpoint.rstrip('/'), hashlib.sha256(key.encode()).hexdigest()


def free_tier_exhausted(error: Exception) -> bool:
    if getattr(error, 'code', None) == FREE_TIER_CODE:
        return True
    body = getattr(error, 'body', None)
    if not isinstance(body, dict):
        response = getattr(error, 'response', None)
        try:
            body = response.json() if response is not None else None
        except (ValueError, TypeError):
            return False
    if not isinstance(body, dict):
        return False
    nested = body.get('error')
    return body.get('code') == FREE_TIER_CODE or (
        isinstance(nested, dict) and nested.get('code') == FREE_TIER_CODE
    )


def run_with_fallback(primary: str, backup: str, request, *, scope: tuple):
    """Cache explicit exhaustion per process for 24h; never guess quota from 429."""
    models = tuple(dict.fromkeys(m.strip() for m in (primary, backup) if m and m.strip()))
    if not models:
        raise ValueError('未配置可调用的模型')
    for model in models:
        cache_key = (scope, model)
        with _lock:
            if _exhausted_until.get(cache_key, 0) > time.monotonic():
                continue
            _exhausted_until.pop(cache_key, None)
        try:
            return request(model)
        except Exception as error:
            if not free_tier_exhausted(error):
                raise
            with _lock:
                _exhausted_until[cache_key] = time.monotonic() + COOLDOWN_SECONDS
            # Never include provider response bodies, credentials or input text.
            logger.warning('model_free_tier_exhausted model=%s', model)
    raise ModelQuotaExhausted('所配置模型的免费额度均已用尽，请联系管理员') from None
