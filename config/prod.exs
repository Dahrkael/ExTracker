import Config

config :extracker,
  debug: false,
  http_enabled: true,
  http_port: 6969,
  https_enabled: false,
  https_port: 7070,
  udp_enabled: true,
  udp_port: 6969,
  connection_id_secret: 87178291199,
  scrape_enabled: false,
  force_compact_peers: true,
  return_external_ip: false

config :logger,
  level: :info
