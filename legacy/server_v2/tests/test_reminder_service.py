import datetime as dt
import pytest
from unittest.mock import MagicMock, patch


def _user_settings_row(hour=12, tz="UTC", last=None):
    return {
        "user_id": "u1",
        "reminder_hour": hour,
        "reminder_timezone": tz,
        "last_reminder_sent_date": last,
    }


@pytest.mark.asyncio
async def test_skip_when_hour_mismatch():
    from app.services.reminder_service import ReminderService
    rs = ReminderService()
    rs._fcm_ready = True

    fake_db = MagicMock()
    fake_db.table.return_value.select.return_value.execute.return_value = \
        MagicMock(data=[_user_settings_row(hour=3, tz="UTC")])
    rs._db = fake_db

    fixed_now = dt.datetime(2026, 5, 8, 19, 0, tzinfo=dt.timezone.utc)
    with patch("app.services.reminder_service._utcnow",
               return_value=fixed_now):
        n = await rs.fire_due_reminders()
    assert n == 0


@pytest.mark.asyncio
async def test_skip_when_already_pushed_today():
    from app.services.reminder_service import ReminderService
    rs = ReminderService()
    rs._fcm_ready = True

    today = dt.date(2026, 5, 8).isoformat()
    fake_db = MagicMock()
    fake_db.table.return_value.select.return_value.execute.return_value = \
        MagicMock(data=[_user_settings_row(hour=19, tz="UTC", last=today)])
    rs._db = fake_db

    fixed_now = dt.datetime(2026, 5, 8, 19, 0, tzinfo=dt.timezone.utc)
    with patch("app.services.reminder_service._utcnow",
               return_value=fixed_now):
        n = await rs.fire_due_reminders()
    assert n == 0


@pytest.mark.asyncio
async def test_pushes_when_due():
    from app.services.reminder_service import ReminderService
    rs = ReminderService()
    rs._fcm_ready = True

    fake_db = MagicMock()
    # user_settings select
    fake_db.table.return_value.select.return_value.execute.return_value = \
        MagicMock(data=[_user_settings_row(hour=19, tz="UTC", last=None)])
    # rpc top_mistake_categories
    fake_db.rpc.return_value.execute.return_value = MagicMock(
        data=[{"category": "filler", "n": 5},
              {"category": "agreement", "n": 3},
              {"category": "tense", "n": 2}]
    )
    # token select chain
    fake_db.table.return_value.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = \
        MagicMock(data=[{"token": "tk1"}])
    rs._db = fake_db

    fake_send = MagicMock(return_value="msg-1")
    fixed_now = dt.datetime(2026, 5, 8, 19, 0, tzinfo=dt.timezone.utc)
    with patch("app.services.reminder_service._utcnow",
               return_value=fixed_now), \
         patch("app.services.reminder_service.messaging", create=True) as msg_mod:
        msg_mod.send = fake_send
        msg_mod.Message = MagicMock()
        msg_mod.Notification = MagicMock()
        # Inject the patched messaging into the lazy import — service does
        # `from firebase_admin import messaging` inside fire_due_reminders.
        with patch.dict("sys.modules",
                        {"firebase_admin.messaging": msg_mod}):
            n = await rs.fire_due_reminders()
    assert n == 1
    assert fake_send.called


@pytest.mark.asyncio
async def test_no_top_categories_skips_push():
    from app.services.reminder_service import ReminderService
    rs = ReminderService()
    rs._fcm_ready = True
    fake_db = MagicMock()
    fake_db.table.return_value.select.return_value.execute.return_value = \
        MagicMock(data=[_user_settings_row(hour=19, tz="UTC", last=None)])
    fake_db.rpc.return_value.execute.return_value = MagicMock(data=[])
    rs._db = fake_db

    fixed_now = dt.datetime(2026, 5, 8, 19, 0, tzinfo=dt.timezone.utc)
    with patch("app.services.reminder_service._utcnow",
               return_value=fixed_now):
        n = await rs.fire_due_reminders()
    assert n == 0


@pytest.mark.asyncio
async def test_disabled_when_fcm_not_ready():
    from app.services.reminder_service import ReminderService
    rs = ReminderService()
    rs._fcm_ready = False
    n = await rs.fire_due_reminders()
    assert n == 0
