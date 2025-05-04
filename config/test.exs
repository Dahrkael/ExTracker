import Config

config :extracker,
  debug: false,
  http_enabled: true,
  http_port: 6969,
  https_enabled: false,
  https_port: 7070,
  udp_enabled: true,
  udp_port: 6969,
  udp_routers: 1,
  udp_recbuf_size: 16_000,
  udp_sndbuf_size: 32_000,
  udp_buffer_size: 128_000,
  connection_id_secret: 87178291199,
  scrape_enabled: true,
  force_compact_peers: false,
  return_external_ip: true

config :logger,
  level: :debug
