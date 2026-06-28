"""Basic Auth tests — stdlib unittest."""
import base64
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from peekserver import auth  # noqa: E402


def hdr(user, pw):
    return "Basic " + base64.b64encode(f"{user}:{pw}".encode()).decode()


class AuthTests(unittest.TestCase):
    def setUp(self):
        self.user = "peek"
        self.h = auth.password_hash("s3cret")

    def test_password_hash_deterministic(self):
        self.assertEqual(auth.password_hash("x"), auth.password_hash("x"))
        self.assertNotEqual(auth.password_hash("x"), auth.password_hash("y"))

    def test_open_when_unconfigured(self):
        self.assertTrue(auth.check_basic("", "", ""))          # no user/hash → open
        self.assertTrue(auth.check_basic(hdr("a", "b"), "", ""))

    def test_correct_credentials(self):
        self.assertTrue(auth.check_basic(hdr("peek", "s3cret"), self.user, self.h))

    def test_wrong_password(self):
        self.assertFalse(auth.check_basic(hdr("peek", "nope"), self.user, self.h))

    def test_wrong_user(self):
        self.assertFalse(auth.check_basic(hdr("eve", "s3cret"), self.user, self.h))

    def test_missing_or_malformed_header(self):
        self.assertFalse(auth.check_basic("", self.user, self.h))
        self.assertFalse(auth.check_basic("Bearer xyz", self.user, self.h))
        self.assertFalse(auth.check_basic("Basic !!!notbase64", self.user, self.h))
        self.assertFalse(auth.check_basic("Basic " + base64.b64encode(b"nocolon").decode(),
                                          self.user, self.h))


if __name__ == "__main__":
    unittest.main()
