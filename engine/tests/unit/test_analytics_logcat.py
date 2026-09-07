import unittest

from mobaile.adapters.analytics_logcat import AnalyticsEvent, FirebaseAnalyticsListener


class TestAnalyticsListener(unittest.TestCase):
    def setUp(self):
        self.listener = FirebaseAnalyticsListener()

    def test_parse_logcat_line_case_a(self):
        raw = "09-03 22:06:24.732 V/FA-SVC  (11637): Logging event: origin=app,name=Consent_Device,params=Bundle[{opened_from_app_list=1, ga_event_origin(_o)=app, ga_screen_class(_sc)=MainActivity, ga_screen_id(_si)=-1985242701408864993, ga_screen(_sn)=consent_device}]"
        event = self.listener._parse_line(raw, platform="android")
        self.assertIsNotNone(event)
        self.assertEqual(event.event_name, "Consent_Device")
        self.assertEqual(event.tag, "FA-SVC")
        self.assertEqual(event.time_str, "22:06:24.732")
        self.assertEqual(event.params.get("ga_screen"), "consent_device")
        self.assertEqual(event.params.get("opened_from_app_list"), "1")

    def test_parse_logcat_line_case_b(self):
        raw = "09-03 14:10:00.100 V/FA: Logging event: screen_view, Bundle[{ga_screen_name=app:home, flow_name=credito}]"
        event = self.listener._parse_line(raw, platform="android")
        self.assertIsNotNone(event)
        self.assertEqual(event.event_name, "screen_view")
        self.assertEqual(event.tag, "FA")
        self.assertEqual(event.params.get("flow_name"), "credito")
        self.assertEqual(event.params.get("ga_screen_name"), "app:home")

    def test_parse_ios_log_line(self):
        raw = "2026-09-04 09:30:15.123456-0300 Default [FirebaseAnalytics] Logging event: origin=app, name=screen_view, params={ ga_screen = \"app:home\"; ga_screen_class = \"HomeController\"; flow_name = \"credito\"; }"
        event = self.listener._parse_line(raw, platform="ios")
        self.assertIsNotNone(event)
        self.assertEqual(event.event_name, "screen_view")
        self.assertEqual(event.tag, "iOS (Firebase)")
        self.assertEqual(event.platform, "ios")
        self.assertEqual(event.params.get("ga_screen"), "app:home")
        self.assertEqual(event.params.get("ga_screen_class"), "HomeController")
        self.assertEqual(event.params.get("flow_name"), "credito")

    def test_export_tsv_and_json(self):
        ev = AnalyticsEvent(
            id=1,
            timestamp=1788487587.0,
            time_str="22:06:24.732",
            tag="FA-SVC",
            event_name="Consent_Device",
            params={"ga_screen": "consent_device", "flow": "onboarding"},
            raw_log="sample log line",
        )
        self.listener.events_history.append(ev)

        tsv = self.listener.export_as_tsv()
        self.assertIn("Consent_Device", tsv)
        self.assertIn("consent_device", tsv)
        self.assertIn("\t", tsv)

        json_out = self.listener.export_as_json()
        self.assertIn('"event_name": "Consent_Device"', json_out)
        self.assertIn('"ga_screen": "consent_device"', json_out)


if __name__ == "__main__":
    unittest.main()
