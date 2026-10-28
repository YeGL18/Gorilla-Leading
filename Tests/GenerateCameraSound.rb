rate = 44100
pcm = Array.new((rate * 0.7).to_i) do |i|
  t = i.to_f / rate
  local = t < 0.24 ? t : t - 0.36
  active = (0...0.24).cover?(local)
  envelope = active ? Math.sin(Math::PI * local / 0.24)**2 : 0
  (Math.sin(2 * Math::PI * 880 * t) * envelope * 10000).to_i
end.pack('s<*')
header = 'RIFF' + [36 + pcm.bytesize].pack('V') + 'WAVEfmt ' + [16, 1, 1, rate, rate * 2, 2, 16].pack('VvvVVvv')
File.binwrite(File.expand_path('../GorillaTranslate/Resources/camera_alert.wav', __dir__), header + 'data' + [pcm.bytesize].pack('V') + pcm)
