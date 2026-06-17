"""
Celery application instance.

To start the worker::

    celery -A app.workers.celery_app worker --loglevel=info

To start the beat scheduler (periodic tasks)::

    celery -A app.workers.celery_app beat --loglevel=info
"""

from celery import Celery

from app.core.config import settings

celery_app = Celery(
    "revenue_os",
    broker=settings.CELERY_BROKER_URL,
    backend=settings.CELERY_RESULT_BACKEND,
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    result_expires=3600,
    timezone="UTC",
    enable_utc=True,
)

celery_app.autodiscover_tasks(["app.workers.tasks"])
