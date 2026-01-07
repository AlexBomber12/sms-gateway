import json
from unittest import mock

import requests

import on_receive
import queue_worker
import sms_queue


def test_enqueue_message(tmp_path):
    base_dir = tmp_path / "queue"
    path = sms_queue.enqueue_message("123", "Hello", base_dir)
    assert path.exists()
    assert path.parent == base_dir / "pending"
    payload = json.loads(path.read_text())
    assert payload["number"] == "123"
    assert payload["text"] == "Hello"
    assert list((base_dir / "tmp").iterdir()) == []


@mock.patch("queue_worker.time.sleep", return_value=None)
@mock.patch("queue_worker.requests.post")
def test_worker_retries(mock_post, mock_sleep):
    response = mock.Mock()
    response.raise_for_status.return_value = None
    mock_post.side_effect = [requests.RequestException("fail"), response]

    assert queue_worker.send_with_retries("token", "chat", "123", "hi", max_attempts=2, retry_delay=0.01)
    assert mock_post.call_count == 2
    assert mock_sleep.call_count == 1


def test_direct_mode_sends_immediately(monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "token")
    monkeypatch.setenv("TELEGRAM_CHAT_ID", "chat")
    monkeypatch.setenv("SMS_MESSAGES", "1")
    monkeypatch.setenv("SMS_1_NUMBER", "+123")
    monkeypatch.setenv("SMS_1_TEXT", "hello")
    monkeypatch.delenv("DELIVERY_MODE", raising=False)

    with mock.patch("on_receive.send_to_telegram") as mock_send:
        on_receive.main([])
    mock_send.assert_called_once()
