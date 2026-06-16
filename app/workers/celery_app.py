"""
app/workers/celery_app.py — Celery application factory.

To run the worker locally:

    celery -A app.workers.celery_app.celery worker --loglevel=info

To run the beat scheduler (periodic tasks):

    celery -A app.workers.celery_app.celery beat --loglevel=info
"""

from celery import Celery

from app.core.config import settings

celery = Celery(
    "revenue_os",
    broker=settings.CELERY_BROKER_URL,
    backend=settings.CELERY_RESULT_BACKEND,
)

celery.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    result_expires=3600,
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
)

celery.autodiscover_tasks(["app.workers.tasks"])
