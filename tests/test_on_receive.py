import unittest
from unittest import mock

import on_receive


class TestOnReceive(unittest.TestCase):
    def test_parse_sms_missing_parts(self):
        env = {
            "SMS_MESSAGES": "3",
            "SMS_1_TEXT": "Hello",
            "SMS_3_TEXT": "World",
            "SMS_1_NUMBER": "+123",
        }
        number, text = on_receive.parse_sms(3, getenv=env.get)
        self.assertEqual(number, "+123")
        self.assertEqual(text, "Hello World")

    def test_missing_env(self):
        with self.assertRaises(EnvironmentError):
            on_receive.get_env("MISSING", required=True)

    @mock.patch("on_receive.requests.post")
    def test_send_to_telegram(self, mock_post):
        mock_resp = mock.Mock()
        mock_resp.raise_for_status.return_value = None
        mock_post.return_value = mock_resp
        on_receive.send_to_telegram("token", "chat", "123", "hi")
        mock_post.assert_called()


if __name__ == "__main__":
    unittest.main()
