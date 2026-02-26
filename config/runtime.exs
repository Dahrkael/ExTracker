import Config

if config_env() in [:prod] do

  # base configuration
  config :extracker,
    ipv4_enabled: true, # listen or not on IPv4
    ipv4_bind_address: "0.0.0.0", # IP to bind to when IPv4 is enabled. "0.0.0.0" listens on every address
    ipv6_enabled: true, # listen or not on IPv6
    ipv6_bind_address: "::", # IP to bind to when IPv6 is enabled. "::" listens on every address
    http_enabled: true, # enable the HTTP endpoint to fulfill client requests
    http_port: 6969, # port used by the HTTP endpoint if enabled
    https_enabled: false, # enable the TLS endpoint to fulfill client requests
    https_port: 7070, # port used by the TLS endpoint if enabled
    https_keyfile: "", # path to the certificate file for TLS
    udp_enabled: true, # enable the UDP endpoint to fulfill client requests
    udp_port: 6969, # port used by the UDP endpoint if enabled
    udp_routers: -1, # amount of processes listening to UDP requests. -1 means one per VM scheduler
    udp_recbuf_size: -1, # kernel receive buffer size for the UDP socket. 512_000 is a good number, -1 means the OS decides
    udp_sndbuf_size: -1, # kernel send buffer size for the UDP socket. 512_000 is a good number, -1 means the OS decides
    udp_buffer_size: -1, # buffer size for the UDP socket. 1_048_576 is a good number, -1 means the OS decides
    connection_id_secret: 87178291199, # prime used as salt for connection id's generation
    scrape_enabled: false, # allow scrape requests on all enabled endpoints
    force_compact_peers: false, # always respond to HTTP(S) requests with a compact peer list
    return_external_ip: false, # return the client's visible IP as per BEP24
    max_peers_returned: 100, # non-negative maximum amount of peers sent to announcing clients
    announce_interval: (30 * 60), # seconds that clients SHOULD wait before announcing again
    announce_interval_min: 60, # seconds that clients HAVE to wait before announcing again. below this requests are ignored
    restrict_hashes: "disabled", # optionally filter hashes using access lists (valid options: "whitelist", "blacklist", "disabled"/false/empty)
    restrict_hashes_file: "~/hashes.txt", # file from which the (dis)allowed hash list is loaded
    restrict_useragents: "disabled", # optionally filter user-agents (in the HTTP(S) port) using access lists (valid options: "whitelist", "blacklist", "disabled"/false/empty)
    restrict_useragents_file: "~/useragents.txt", # file from which the (dis)allowed user-agent list is loaded
    cleaning_interval: (60 * 1000), # milliseconds between cleaning passes
    swarm_clean_delay: (10 * 60 * 1_000), # milliseconds after a swarm is marked as 'needs cleaning'
    peer_cleanup_delay: (60 * 60 * 1_000), # milliseconds after a peer is considered stale and removed
    compress_lookups: true, # compressed lookup tables take less space while losing some performance
    named_lookups: false, # identify each swarm lookup table as "swarm_HASH" instead of just "swarm". Will exhaust the atom table at some point
    small_swarm_buckets: 100000, # how many buckets are used to hold swarms with not enough peers to have their own lookup table
    swarm_upgrade_peer_threshold: 100, # how many peers need to be inside a swarm to be considered big enough for its own lookup table
    swarm_downgrade_percentage_threshold: 0.25, # percentage of the peer threshold that a swarm needs to lose to become small again
    backup_auto_enabled: false, # enable automatic backups of current swarms and peers creation
    backup_auto_load_on_startup: false, # load the backup file specified in backup_auto_path when the tracker starts
    backup_auto_interval: (60 * 60 * 1000), # milliseconds between automatic backups
    backup_auto_path: "~/extracker.bck", # file path used for automatic backups
    backup_display_stats: true, # log how many peers and swarms are registered when a backup triggers
    snatches_delete_on_swarm_remove: false, # delete snatch counters when a swarm is removed
    geoip_enabled: false, # lookup and store the country of each peer
    geoip_license_key: "", # MaxMind's license key. Required for the geoip features
    telemetry_enabled: false, # enable telemetry events gathering
    telemetry_port: 9568, # port in which telemetry endpoints are served (via HTTP)
    telemetry_reporter: "basic", # choose reporter for '/tracker-stats.html' ("basic" or "ets")
    telemetry_prometheus: true, # expose a Prometheus scrape endpoint at '/prometheus'
    reverse_proxy_address: "", # specify the address of a reverse proxy if present (caddy, nginx, apache, etc)
    http_request_timeout: 60_000, # time before *outgoing* http requests timeout (mainly for integrations)
    integration: "none", # select which integration (if any) to be enabled (current options: "arcadia", "none")
    fake_peers_in_responses: 0, # amount of fake peers to inject in the responses (prevent mass scraping of torrent peer lists), a recommended value is 3
    debug: false # enable extra debug logs and checks

  config :logger, level: :notice # log minimum level. info and debug may get spammy

  # configuration for integrations
  config :extracker_arcadia,
    api_bind_address: "0.0.0.0", # IP to bind the tracker's REST API
    api_port: 8081, # port used for the tracker's REST API
    site_host: "http://localhost:8080", # address (and port) where Arcadia's backend is listening
    site_api_key: "" # API Key for Arcadia's Tracker user

end
