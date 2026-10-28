import unittest
from MatchCameraRoads import applicable_limits, project, road_name_matches


class RoadChecks(unittest.TestCase):
    def test_chainage_does_not_leak_to_next_restriction(self):
        road = [(0, 0), (100, 0), (200, 0)]
        limits = [({"SPEED_LIMIT": "70 km/h", "SPEED_LIMIT_ID": "first"}, [(0, 0), (90, 0)]),
                  ({"SPEED_LIMIT": "50 km/h", "SPEED_LIMIT_ID": "second"}, [(110, 0), (200, 0)])]
        self.assertEqual(applicable_limits((40, 12), road, limits), [(70, "first")])
        self.assertEqual(applicable_limits((160, 12), road, limits), [(50, "second")])
        self.assertEqual(applicable_limits((100, 12), road, limits), [])

    def test_matching_primary_street_not_a_nearby_landmark(self):
        camera = {"english": "Tolo Highway (Northbound) near Tai Po Road", "name": "吐露港公路（北行）鄰近大埔公路"}
        self.assertTrue(road_name_matches(camera, {"STREET_ENAME": "TOLO HIGHWAY"}))
        self.assertFalse(road_name_matches(camera, {"STREET_ENAME": "TAI PO ROAD", "STREET_CNAME": "大埔公路"}))

    def test_conditional_limits_are_not_treated_as_permanent(self):
        self.assertEqual(applicable_limits((40, 0), [(0, 0), (100, 0)], [
            ({"SPEED_LIMIT": "30 km/h", "SPEED_LIMIT_ID": "school", "REMARKS": "school hours"}, [(0, 0), (100, 0)])]), [])

    def test_project_onto_curve_not_endpoint_chord(self):
        self.assertEqual(project((100, 40), [(0, 0), (100, 0), (100, 100)]), (0, 140))


if __name__ == "__main__":
    unittest.main()
