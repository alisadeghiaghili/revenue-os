"""
Celery task definitions.

Add concrete tasks here. Example::

    @celery_app.task(bind=True, max_retries=3)
    def send_invoice_email(self, store_id: str, invoice_id: str) -> None:
        ...
"""

from app.workers.celery_app import celery_app  # noqa: F401  — ensures tasks are registered
