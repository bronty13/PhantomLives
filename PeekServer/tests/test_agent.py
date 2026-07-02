"""launchd agent tests — validate the plist install-agent.sh emits.

Uses --print-plist (pure string generation, no launchctl side effects) so these
run on any platform. Run: python3 -m unittest discover -s tests
"""
import os
import plistlib
import subprocess
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "install-agent.sh")


class AgentPlistTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        out = subprocess.check_output(["/bin/bash", SCRIPT, "--print-plist"])
        cls.plist = plistlib.loads(out)

    def test_label(self):
        self.assertEqual(self.plist["Label"], "com.phantomlives.peekserver")

    def test_is_persistent_server_not_periodic(self):
        # A long-running server: relaunch on crash/at login, never a StartInterval job.
        self.assertTrue(self.plist["KeepAlive"])
        self.assertTrue(self.plist["RunAtLoad"])
        self.assertNotIn("StartInterval", self.plist)

    def test_launches_run_sh(self):
        args = self.plist["ProgramArguments"]
        self.assertEqual(args[0], "/bin/bash")
        self.assertTrue(args[1].endswith("/run.sh"))

    def test_path_includes_homebrew_for_ffmpeg(self):
        # launchd's minimal PATH can't see brew ffmpeg → proxies would silently fail.
        path = self.plist["EnvironmentVariables"]["PATH"]
        self.assertIn("/opt/homebrew/bin", path)
        self.assertIn("/usr/local/bin", path)

    def test_logs_configured(self):
        self.assertTrue(self.plist["StandardOutPath"].endswith("phantomlives-peekserver.log"))
        self.assertEqual(self.plist["StandardOutPath"], self.plist["StandardErrorPath"])

    def test_usage_error_on_no_args(self):
        r = subprocess.run(["/bin/bash", SCRIPT], capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)
        self.assertIn("usage:", r.stderr)


if __name__ == "__main__":
    unittest.main()
