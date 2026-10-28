# Retain the old entry point, but never run the superseded proximity-only match.
script = File.expand_path('MatchCameraRoads.py', __dir__)
exec('python3', script)
