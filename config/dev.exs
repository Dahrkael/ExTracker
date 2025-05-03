import Config

config :extracker,
  debug: true,
  http_enabled: true,
  http_port: 6969,
  https_enabled: false,
  https_port: 7070,
  udp_enabled: true,
  udp_port: 6969,
  connection_id_secret: 87178291199,
  scrape_enabled: true,
  force_compact_peers: false,
  return_external_ip: true

config :logger,
  level: :debug
